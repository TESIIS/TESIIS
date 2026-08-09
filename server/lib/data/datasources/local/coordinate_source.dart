// lib/data/datasources/local/coordinate_source.dart
//
// The coordinate table that makes the map work.
//
// 臺北市 OpenData dataset 4c92dbd4 (可供避難收容處所一覽表) returns no
// coordinate columns at all — verified against all 401 records. Every point
// this system plots comes from the CSV loaded here, which is built offline by
// `dart run tool/build_coordinates.dart` from two government datasets and
// committed to the repo.
//
// Committing the table (rather than geocoding at runtime) is what lets a fresh
// clone show shelters on the map with no API key and no external account.

import 'dart:io';

import '../../../core/csv/csv_codec.dart';
import '../../../core/geo/taipei_bounds.dart';
import '../../../domain/entities/shelter_fields.dart';

/// Where a coordinate came from. Surfaced through the API so consumers can
/// tell a surveyed government point from a best-effort name match.
enum CoordinateSourceKind {
  /// 消防署避難收容處所點位檔 (data.gov.tw/dataset/73242).
  nfaPointFile('nfa_point_file'),

  /// 北市警政APP_防空避難設備位置 (data.taipei, 39ca53a1).
  taipeiAirRaid('taipei_airraid'),

  /// OpenStreetMap via Overpass. ODbL — see NOTICE.md.
  osmOverpass('osm_overpass'),

  /// Filled in by hand after visual confirmation.
  manual('manual'),

  /// Known to have no coordinate. Recorded explicitly so coverage is auditable
  /// rather than a silent gap.
  none('none');

  const CoordinateSourceKind(this.wireName);

  final String wireName;

  static CoordinateSourceKind fromWireName(String raw) {
    for (final kind in values) {
      if (kind.wireName == raw.trim()) return kind;
    }
    return CoordinateSourceKind.none;
  }
}

/// How much to trust the point.
enum CoordinateConfidence {
  /// Normalised address matched exactly against a government dataset.
  exact('exact'),

  /// Matched on facility name, not address.
  nameMatch('name_match'),

  /// Approximate — e.g. a park centroid for a shelter with no street address.
  approx('approx'),

  /// No coordinate.
  none('none');

  const CoordinateConfidence(this.wireName);

  final String wireName;

  static CoordinateConfidence fromWireName(String raw) {
    for (final c in values) {
      if (c.wireName == raw.trim()) return c;
    }
    return CoordinateConfidence.none;
  }
}

class ShelterCoordinate {
  const ShelterCoordinate({
    required this.lng,
    required this.lat,
    required this.source,
    required this.confidence,
  });

  final double lng;
  final double lat;
  final CoordinateSourceKind source;
  final CoordinateConfidence confidence;
}

/// Coverage figures, reported through `/api/shelters/stats`.
class CoordinateCoverage {
  const CoordinateCoverage({
    required this.total,
    required this.withCoordinates,
    required this.bySource,
  });

  final int total;
  final int withCoordinates;
  final Map<String, int> bySource;

  double get ratio => total == 0 ? 0 : withCoordinates / total;

  Map<String, dynamic> toJson() => {
    'total': total,
    'withCoordinates': withCoordinates,
    'missing': total - withCoordinates,
    'ratio': double.parse(ratio.toStringAsFixed(4)),
    'bySource': bySource,
  };
}

/// In-memory lookup over the committed coordinate table.
class CoordinateSource {
  CoordinateSource._(this._byCode, this._byAddress, this.coverage);

  /// Primary key: 收容所編號 is stable and unique upstream.
  final Map<String, ShelterCoordinate> _byCode;

  /// Fallback key: normalised 門牌地址, for records whose code changed.
  final Map<String, ShelterCoordinate> _byAddress;

  final CoordinateCoverage coverage;

  static const _requiredColumns = ['shelter_code', 'lng', 'lat'];

  /// An empty table. Lookups return null; the map will simply have no markers.
  factory CoordinateSource.empty() => CoordinateSource._(
    const {},
    const {},
    const CoordinateCoverage(total: 0, withCoordinates: 0, bySource: {}),
  );

  factory CoordinateSource.fromCsv(String csv) {
    final rows = parseCsvAsMaps(csv);
    if (rows.isEmpty) return CoordinateSource.empty();

    final missing = _requiredColumns
        .where((c) => !rows.first.containsKey(c))
        .toList();
    if (missing.isNotEmpty) {
      throw FormatException(
        'Coordinate CSV is missing required column(s): ${missing.join(", ")}',
      );
    }

    final byCode = <String, ShelterCoordinate>{};
    final byAddress = <String, ShelterCoordinate>{};
    final bySource = <String, int>{};
    var total = 0;
    var withCoordinates = 0;

    for (final row in rows) {
      final code = (row['shelter_code'] ?? '').trim();
      if (code.isEmpty) continue;
      total++;

      final lng = double.tryParse((row['lng'] ?? '').trim());
      final lat = double.tryParse((row['lat'] ?? '').trim());
      final kind = CoordinateSourceKind.fromWireName(row['source'] ?? 'none');

      // Re-apply the bounding-box gate at load time. The build tool already
      // filters, but the table is a hand-editable committed file and a typo
      // must not put a shelter in another county.
      if (lng == null || lat == null || !TaipeiBounds.contains(lng, lat)) {
        bySource[CoordinateSourceKind.none.wireName] =
            (bySource[CoordinateSourceKind.none.wireName] ?? 0) + 1;
        continue;
      }

      final coordinate = ShelterCoordinate(
        lng: lng,
        lat: lat,
        source: kind,
        confidence: CoordinateConfidence.fromWireName(
          row['confidence'] ?? 'none',
        ),
      );
      byCode[code] = coordinate;
      withCoordinates++;
      bySource[kind.wireName] = (bySource[kind.wireName] ?? 0) + 1;

      final addressKey = ShelterAddress.normalize(row['address']);
      if (addressKey.isNotEmpty) {
        byAddress.putIfAbsent(addressKey, () => coordinate);
      }
    }

    return CoordinateSource._(
      byCode,
      byAddress,
      CoordinateCoverage(
        total: total,
        withCoordinates: withCoordinates,
        bySource: bySource,
      ),
    );
  }

  /// Loads the table from [path].
  ///
  /// Throws if the file is missing. Unlike the SQLite geocoding database this
  /// replaced, there is no silent fallback: the table is committed to the repo,
  /// so a missing file means something is genuinely wrong with the checkout and
  /// failing loudly beats shipping a map with no markers.
  factory CoordinateSource.loadFromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Coordinate table not found', path);
    }
    return CoordinateSource.fromCsv(file.readAsStringSync());
  }

  ShelterCoordinate? lookupByCode(String? shelterCode) {
    final code = (shelterCode ?? '').trim();
    if (code.isEmpty) return null;
    return _byCode[code];
  }

  ShelterCoordinate? lookupByAddress(String? address, {String? township}) {
    final key = ShelterAddress.normalize(address, township: township);
    if (key.isEmpty) return null;
    return _byAddress[key];
  }

  /// Code first, address as fallback.
  ShelterCoordinate? lookup({
    String? shelterCode,
    String? address,
    String? township,
  }) =>
      lookupByCode(shelterCode) ?? lookupByAddress(address, township: township);
}
