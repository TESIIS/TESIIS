// lib/data/mappers/nfa_shelter_mapper.dart
//
// Maps one raw row of 消防署避難收容處所點位檔 (the nationwide NFA point file)
// onto the existing Shelter entity.
//
// Verified against a live pull of all 5,973 rows (2026-08-23). Header:
//   序號,縣市及鄉鎮市區,村里,避難收容處所地址,經度,緯度,避難收容處所名稱,
//   預計收容村里,預計收容人數,適用災害類別,管理人姓名,管理人電話,
//   室內,室外,適合避難弱者安置
//
// Pure — no I/O — so it's shared by tool/build_nationwide_snapshot.dart and
// (indirectly, via the snapshot it produces) the runtime repository. The
// snapshot can never disagree with what a live fetch would produce.

import 'dart:convert';

import '../../core/geo/city_codes.dart';
import '../../core/geo/taiwan_bounds.dart';
import '../../domain/entities/shelter.dart';
import '../../domain/entities/shelter_fields.dart';

/// Result of mapping one raw row: either a [Shelter], or a reason it was
/// rejected — never both.
typedef NfaMapResult = ({Shelter? shelter, String? rejectReason});

class NfaShelterMapper {
  const NfaShelterMapper._();

  static const _hazardColumn = '適用災害類別';
  static const _hazardKeys = ['水災', '震災', '土石流', '海嘯', '核子事故'];

  /// Splits `縣市及鄉鎮市區` into (city, township). All 22 county names are
  /// exactly 3 characters, so this is a fixed-width split, not a search.
  ///
  /// One row in the live file (序號 1, 新竹縣) carries no township at all —
  /// returns `('新竹縣', '')` for it rather than throwing.
  static (String city, String township) splitRegion(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length <= 3) return (trimmed, '');
    return (trimmed.substring(0, 3), trimmed.substring(3));
  }

  /// `'水災,震災,土石流'` -> `{'水災':'Y','震災':'Y','土石流':'Y','海嘯':'N',
  /// '核子事故':'N'}`. The column can be empty.
  static Map<String, String> parseHazards(String raw) {
    final present = raw
        .split(RegExp(r'[,、]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    return {
      for (final key in _hazardKeys) key: present.contains(key) ? 'Y' : 'N',
    };
  }

  /// FNV-1a, 64-bit. Not cryptographic and doesn't need to be — this is a
  /// stable de-duplication key over ~6,000 items, not a security control, the
  /// same reasoning `csv_codec.dart` gives for hand-rolling its parser rather
  /// than pulling in a dependency for a few lines.
  static int _fnv1a64(String input) {
    const prime = 0x100000001b3;
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash *= prime;
    }
    return hash;
  }

  /// Dart's native `int` is a fixed 64-bit signed value with no bignum
  /// promotion, so `toUnsigned(64)` on an already-64-bit value is a no-op —
  /// a negative hash still prints with a leading '-'. Split into two 32-bit
  /// unsigned halves instead, which sidesteps the sign entirely.
  static String _fnv1a64Hex(String input) {
    final h = _fnv1a64(input);
    final hi = (h >> 32) & 0xFFFFFFFF;
    final lo = h & 0xFFFFFFFF;
    return hi.toRadixString(16).padLeft(8, '0') +
        lo.toRadixString(16).padLeft(8, '0');
  }

  /// Deterministic, source-stable ID. `序號` is a row ordinal that shifts on
  /// every republish, so it cannot be used as the identifier.
  ///
  /// [ordinal] disambiguates rows whose (city, township, village, address,
  /// name) tuple is not unique — 14 such collisions exist in the live file.
  /// Pass 0 for the first occurrence of a tuple; the caller is responsible
  /// for assigning increasing ordinals to later occurrences of the same key,
  /// in a stable (e.g. file) order, so a rebuild reproduces the same IDs.
  static String sourceId({
    required String city,
    required String township,
    required String village,
    required String address,
    required String name,
    int ordinal = 0,
  }) {
    final key = [city, township, village, address, name].join('|');
    final hex = _fnv1a64Hex(ordinal == 0 ? key : '$key|$ordinal');
    final cityCode =
        CityCodes.byNormalizedName(ShelterText.normalizeName(city))?.isoCode ??
        'UNK';
    return 'NFA-$cityCode-$hex';
  }

  /// Returns, for each row (by index), the ordinal to pass to [sourceId] — 0
  /// for the first row with a given (city,township,village,address,name)
  /// tuple, 1 for the second, etc. Assigned in file order so a rebuild (or a
  /// fresh live fetch) reproduces the same IDs. Shared by the offline build
  /// tool and the runtime repository so they can never disagree.
  static List<int> assignOrdinals(List<Map<String, String>> rows) {
    final seen = <String, int>{};
    final ordinals = List<int>.filled(rows.length, 0);
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final (city, township) = splitRegion(row['縣市及鄉鎮市區'] ?? '');
      final key = [
        city,
        township,
        (row['村里'] ?? '').trim(),
        (row['避難收容處所地址'] ?? '').trim(),
        (row['避難收容處所名稱'] ?? '').trim(),
      ].join('|');
      final count = seen[key] ?? 0;
      ordinals[i] = count;
      seen[key] = count + 1;
    }
    return ordinals;
  }

  /// Maps one raw row. Returns a rejection reason instead of a [Shelter] when
  /// the row fails validation — never both, and never throws on bad data
  /// (this runs over an uncontrolled government export).
  static NfaMapResult toShelter(
    Map<String, String> row, {
    required int rowIndex,
    int ordinal = 0,
    DateTime? sourceUpdatedAt,
  }) {
    final (city, township) = splitRegion(row['縣市及鄉鎮市區'] ?? '');
    final normalizedCity = ShelterText.normalizeName(city);
    if (!TaiwanBounds.byCounty.containsKey(normalizedCity)) {
      return (shelter: null, rejectReason: 'unknown_county');
    }

    final name = (row['避難收容處所名稱'] ?? '').trim();
    final address = (row['避難收容處所地址'] ?? '').trim();
    final village = (row['村里'] ?? '').trim();

    final lng = double.tryParse((row['經度'] ?? '').trim());
    final lat = double.tryParse((row['緯度'] ?? '').trim());
    if (lng == null || lat == null) {
      return (shelter: null, rejectReason: 'no_coordinate');
    }
    if (!TaiwanBounds.containsForCounty(normalizedCity, lng, lat)) {
      return (shelter: null, rejectReason: 'out_of_county_bounds');
    }

    final hazards = parseHazards(row[_hazardColumn] ?? '');
    final cityCode = CityCodes.byNormalizedName(normalizedCity)?.isoCode;

    final shelter = Shelter(
      id: rowIndex,
      importDate: null,
      shelterCode: sourceId(
        city: city,
        township: township,
        village: village,
        address: address,
        name: name,
        ordinal: ordinal,
      ),
      name: name,
      city: city,
      zipcode: '',
      township: township,
      village: village,
      address: address,
      type: '',
      flood: hazards['水災'],
      quake: hazards['震災'],
      landslide: hazards['土石流'],
      tsunami: hazards['海嘯'],
      relief: null,
      accessible: (row['適合避難弱者安置'] ?? '').trim(),
      indoor: (row['室內'] ?? '').trim(),
      outdoor: (row['室外'] ?? '').trim(),
      serviceVillages: (row['預計收容村里'] ?? '').trim(),
      capacity: ShelterNumber.parseInt(row['預計收容人數']),
      area: null,
      contactName: null,
      contactPhone: null,
      managerName: (row['管理人姓名'] ?? '').trim().isEmpty
          ? null
          : (row['管理人姓名'] ?? '').trim(),
      managerPhone: (row['管理人電話'] ?? '').trim().isEmpty
          ? null
          : (row['管理人電話'] ?? '').trim(),
      notes: null,
      x: lng,
      y: lat,
      coordinateSource: 'nfa_point_file',
      coordinateConfidence: 'exact',
      cityCode: cityCode,
      nuclear: hazards['核子事故'],
      sourceName: 'nfa_point_file',
      sourceUpdatedAt: sourceUpdatedAt,
    );
    return (shelter: shelter, rejectReason: null);
  }
}
