// lib/core/geo/taiwan_bounds.dart

/// One rectangular quality-gate region.
class GeoBox {
  const GeoBox(this.minLng, this.maxLng, this.minLat, this.maxLat);

  final double minLng;
  final double maxLng;
  final double minLat;
  final double maxLat;

  bool contains(double lng, double lat) =>
      lng >= minLng && lng <= maxLng && lat >= minLat && lat <= maxLat;
}

/// Per-county bounding boxes used to reject obviously-wrong coordinates in the
/// nationwide 消防署避難收容處所點位檔.
///
/// A single national box is useless as a quality gate: it would happily
/// accept a 苗栗縣 shelter mis-geocoded to Taipei. Validated against a live
/// pull of all 5,973 records (2026-08-23): 98.0% pass (5,854/5,973). The 119
/// rejects fall into three clusters worth knowing about, so a *new* one shows
/// up as a real anomaly rather than getting lost in expected noise:
///   - ~36 rows nationwide share one exact point (121.533012/25.042385) — a
///     failed geocode's default-to-Taipei fallback.
///   - ~14 rows in 桃園市新屋區 sit at latitude 26.9x instead of 24.9x — looks
///     like a typo two digits off.
///   - 8 rows in 金門縣金沙鎮 sit ~28 km SW of the real township, in the
///     strait. The box is deliberately NOT widened to swallow these — see
///     `server/tool/build_nationwide_snapshot.dart`.
///
/// 金門縣 needs two boxes: 烏坵鄉 is administratively part of 金門縣 but sits
/// roughly 130 km away, near the Matsu island group.
class TaiwanBounds {
  const TaiwanBounds._();

  static const Map<String, List<GeoBox>> byCounty = {
    '台北市': [GeoBox(121.40, 121.70, 24.90, 25.25)],
    '新北市': [GeoBox(121.25, 122.03, 24.65, 25.32)],
    '基隆市': [GeoBox(121.60, 121.87, 25.00, 25.25)],
    '桃園市': [GeoBox(120.93, 121.50, 24.55, 25.15)],
    '新竹市': [GeoBox(120.85, 121.07, 24.73, 24.90)],
    '新竹縣': [GeoBox(120.88, 121.45, 24.30, 24.92)],
    '苗栗縣': [GeoBox(120.65, 121.17, 24.18, 24.78)],
    '台中市': [GeoBox(120.40, 121.48, 23.95, 24.47)],
    '彰化縣': [GeoBox(120.22, 120.76, 23.75, 24.23)],
    '南投縣': [GeoBox(120.52, 121.35, 23.38, 24.32)],
    '雲林縣': [GeoBox(120.06, 120.75, 23.47, 23.90)],
    '嘉義市': [GeoBox(120.37, 120.53, 23.41, 23.55)],
    '嘉義縣': [GeoBox(120.05, 120.93, 23.17, 23.63)],
    '台南市': [GeoBox(120.00, 120.70, 22.87, 23.45)],
    '高雄市': [GeoBox(120.10, 121.10, 22.43, 23.50)],
    // Includes 小琉球 (120.37/22.34).
    '屏東縣': [GeoBox(120.33, 120.95, 21.85, 22.90)],
    // Includes 龜山島 (121.94/24.84).
    '宜蘭縣': [GeoBox(121.28, 122.05, 24.27, 25.02)],
    '花蓮縣': [GeoBox(120.95, 121.87, 23.05, 24.42)],
    // Includes 綠島 (121.49/22.66) and 蘭嶼 (121.55/22.05).
    '台東縣': [GeoBox(120.68, 121.70, 21.85, 23.50)],
    '澎湖縣': [GeoBox(119.27, 119.75, 23.15, 23.85)],
    // 馬祖. Spans 東引 to 莒光 as one contiguous box — no split needed.
    '連江縣': [GeoBox(119.85, 120.55, 25.90, 26.42)],
    // 金門本島 + 烈嶼, plus 烏坵鄉 as a separate administrative exclave.
    '金門縣': [
      GeoBox(118.10, 118.55, 24.32, 24.58),
      GeoBox(119.40, 119.52, 24.93, 25.02),
    ],
  };

  /// The 22 counties, in a stable display order (roughly north to south on
  /// the main island, then outlying islands), for `GET /api/regions`.
  static const List<String> counties = [
    '台北市',
    '新北市',
    '基隆市',
    '桃園市',
    '新竹市',
    '新竹縣',
    '苗栗縣',
    '台中市',
    '彰化縣',
    '南投縣',
    '雲林縣',
    '嘉義市',
    '嘉義縣',
    '台南市',
    '高雄市',
    '屏東縣',
    '宜蘭縣',
    '花蓮縣',
    '台東縣',
    '澎湖縣',
    '金門縣',
    '連江縣',
  ];

  /// Loose national envelope, for validating a client-supplied `bbox` before
  /// it's worth doing per-county work.
  static const nationwide = GeoBox(118.10, 122.10, 21.85, 26.45);

  /// [county] should already be normalised (see `ShelterText.normalizeName`
  /// — 臺 vs 台 must be folded before calling this).
  static bool containsForCounty(String county, double lng, double lat) {
    final boxes = byCounty[county];
    if (boxes == null) return false;
    return boxes.any((b) => b.contains(lng, lat));
  }
}
