// lib/domain/entities/shelter_fields.dart
//
// Quirks of the Taipei OpenData 避難收容處 dataset, in one place.
//
// Verified on 2026-08-09 against all 401 records of dataset
// 4c92dbd4-d259-495a-8390-52628119a4dd (scope=resourceAquire).

/// Hazard columns (水災/震災/土石流/海嘯/救濟支站/無障礙設施/室內/室外) are not
/// plain Y/N.
///
/// Observed value domains:
///   水災      Y(206) N(195)
///   震災      備用(239) N(100) Y(62)
///   土石流    N(390) Y(6) 老舊聚落(5)
///   海嘯      N(391) 備用(10)      <- no literal 'Y' exists at all
///   救濟支站/無障礙設施/室內/室外   Y/N only
///
/// 備用 and 老舊聚落 both mean "this shelter serves that hazard", so they are
/// reported as 'Y' and count as true when filtering. Dropping the aliases would
/// make `?tsunami=Y` return nothing, since 海嘯 never carries a literal 'Y'.
class HazardFlag {
  /// Upstream spellings that mean yes without saying 'Y'.
  static const yesAliases = {'備用', '老舊聚落'};

  static const _yesLiterals = {'Y', 'YES', 'TRUE', '是'};
  static const _noLiterals = {'N', 'NO', 'FALSE', '否'};

  static bool isYes(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return false;
    if (yesAliases.contains(s)) return true;
    return _yesLiterals.contains(s.toUpperCase());
  }

  static bool isNo(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return false;
    return _noLiterals.contains(s.toUpperCase());
  }

  /// Canonical value for API output: anything that means yes becomes 'Y',
  /// everything else passes through untouched.
  ///
  /// Must stay in sync with [isYes] — a value reported as 'Y' here that [isYes]
  /// rejects would make the API contradict its own filters.
  static String? normalizeForOutput(String? raw) =>
      raw == null ? null : (isYes(raw) ? 'Y' : raw);

  /// True when a query value asks specifically for an alias (`?quake=備用`)
  /// rather than for any usable shelter (`?quake=Y`).
  static bool isAliasRequest(String want) => yesAliases.contains(want.trim());

  /// Exact-alias match, for the [isAliasRequest] case.
  static bool matchesAlias(String? raw, String want) =>
      (raw ?? '').trim() == want.trim();
}

/// Text quirks of the same dataset.
class ShelterText {
  /// 服務里別 is 、-separated, but the raw data also contains a stray 。, a
  /// full-width ，, embedded newlines and one parenthesised note. Splitting on
  /// `[、，,]` alone mangles 4 of the 401 records, e.g.
  ///   _id 67  "…中庄里。"                 -> token "中庄里。" never matches 中庄里
  ///   _id 246 "前港里\n義信里"            -> two villages glued into one token
  ///   _id 273 "豐年里\n(僅寒暑假可安置)"   -> village glued to a free-text note
  static final _villageSeparators = RegExp(r'[、，,;；。\s]+');

  /// Parenthesised notes are commentary, not village names.
  static final _parentheticalNote = RegExp(r'[（(][^）)]*[）)]');

  static List<String> splitVillages(String? raw) {
    if (raw == null) return const [];
    return raw
        .replaceAll(_parentheticalNote, '')
        .split(_villageSeparators)
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// Comparison key for the name-like columns 縣市/鄉鎮/村里/類型.
  ///
  /// All 401 records spell the city 臺北市, while clients routinely send
  /// 台北市, so an exact string compare silently returns zero rows. Fold the
  /// variants the same way ShelterDatabase already folds them for addresses.
  static String normalizeName(String? raw) =>
      (raw ?? '').trim().replaceAll('臺', '台');

  static bool namesEqual(String? a, String? b) =>
      normalizeName(a) == normalizeName(b);
}

/// Address normalisation, used as the join key against every coordinate source.
///
/// The 401 蔽難收容處所 records carry no coordinates, so every coordinate this
/// system shows comes from joining 門牌地址 against another dataset. That makes
/// this class the single most load-bearing piece of string handling in the
/// repo: a rule that is wrong here silently drops shelters off the map.
///
/// Every rule below was derived from an actual mismatch observed while joining
/// dataset 4c92dbd4 against 消防署避難收容處所點位檔 and
/// 北市警政APP_防空避難設備位置 (39ca53a1) on 2026-08-09.
///
/// Do not re-implement any of this elsewhere — see [ShelterText] for why.
class ShelterAddress {
  /// 臺北市的 12 個行政區。Longest-prefix order does not matter here since no
  /// district name is a prefix of another.
  static const districts = {
    '中正區',
    '大同區',
    '中山區',
    '松山區',
    '大安區',
    '萬華區',
    '信義區',
    '士林區',
    '北投區',
    '內湖區',
    '南港區',
    '文山區',
  };

  static final _cityPrefix = RegExp(r'^台北市');

  /// 三段四號 -> 3段4號. Upstream mixes Chinese and Arabic numerals freely
  /// ("汀州路三段四號" vs "汀州路3段4號"), and an unconverted address never
  /// matches its counterpart in the coordinate sources.
  static final _cjkNumbered = RegExp(r'([零一二三四五六七八九十]+)([段號巷弄樓])');

  /// Floor designators carry no positional information and differ between
  /// sources ("公園路52號B1" vs "公園路52號"). Strip them before comparing.
  static final _floor = RegExp(
    r'(地下[0-9]+樓|地下[0-9]+層|[0-9]+樓|[0-9]+層|B[0-9]+|[0-9]+F)',
    caseSensitive: false,
  );

  /// Everything that is decoration rather than address. '-' survives on
  /// purpose: it is the canonical form of 之 (see [normalize]).
  static final _noise = RegExp(r'[\s,、，。．\.:：;；()（）｜|]');

  static const _cjkDigits = {
    '零': 0,
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };

  /// Parses 一..九十九. Returns null for anything it does not understand, so
  /// callers can leave the original text alone rather than corrupt it.
  static int? parseCjkNumber(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (!s.contains('十')) {
      var value = 0;
      for (final ch in s.split('')) {
        final d = _cjkDigits[ch];
        if (d == null) return null;
        value = value * 10 + d;
      }
      return value;
    }
    final parts = s.split('十');
    if (parts.length != 2) return null;
    final tensText = parts[0];
    final onesText = parts[1];
    final tens = tensText.isEmpty ? 1 : _cjkDigits[tensText];
    final ones = onesText.isEmpty ? 0 : _cjkDigits[onesText];
    if (tens == null || ones == null) return null;
    return tens * 10 + ones;
  }

  /// Full-width digits and Latin letters appear in a handful of records.
  static String toHalfWidth(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0x3000) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// Canonical join key for an address.
  ///
  /// [township] is the 鄉鎮 column, used only when the address itself does not
  /// already name a district — dataset 4c92dbd4 writes it both ways
  /// ("公園路29號" and "臺北市中正區公園路29號" both occur).
  ///
  /// Returns an empty string for input that cannot serve as a key.
  static String normalize(String? raw, {String? township}) {
    var s = toHalfWidth((raw ?? '').trim()).replaceAll('臺', '台');
    if (s.isEmpty) return '';

    s = s.replaceFirst(_cityPrefix, '');

    // Pull the district out of the address if it is there, otherwise fall back
    // to the 鄉鎮 column. Either way the key ends up district-prefixed, so a
    // bare "公園路29號" cannot collide with the same street number in another
    // district.
    var district = '';
    for (final d in districts) {
      if (s.startsWith(d)) {
        district = d;
        s = s.substring(d.length);
        break;
      }
    }
    if (district.isEmpty) {
      final fromColumn = toHalfWidth(
        (township ?? '').trim(),
      ).replaceAll('臺', '台');
      if (districts.contains(fromColumn)) district = fromColumn;
    }

    s = s.replaceAllMapped(_cjkNumbered, (m) {
      final value = parseCjkNumber(m[1]!);
      return value == null ? m[0]! : '$value${m[2]}';
    });

    s = s.replaceAll('之', '-');
    s = s.replaceAll(_floor, '');
    s = s.replaceAll(_noise, '');

    return '$district$s';
  }
}

/// Numeric columns arrive as strings and are not always numeric.
///
/// 容納人數 has one non-numeric value ("俟搬遷後重新評估") and
/// 收容所面積（平方公尺） has three ("14,495", "俟搬遷後重新評估",
/// "改建後重新評估"). Only the thousands separator is recoverable.
class ShelterNumber {
  static double? parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim().replaceAll(',', ''));
  }

  static int parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim().replaceAll(',', '')) ?? 0;
  }
}
