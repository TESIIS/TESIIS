// lib/core/geo/taipei_bounds.dart

/// Bounding box used to reject obviously-wrong coordinates.
///
/// This is a *quality gate*, not the map viewport — it is deliberately looser
/// than 臺北市's actual extent so that a correct point near the boundary is
/// never discarded.
///
/// It exists because the 消防署避難收容處所點位檔 ships bad data: of its 272
/// 臺北市 rows, two are geocoded hundreds of kilometres away
/// (北市大附小, 公園路29號 -> 120.913/22.4797, which is in 屏東). Without this
/// gate those points would place shelters in the wrong county.
class TaipeiBounds {
  static const minLng = 121.40;
  static const maxLng = 121.70;
  static const minLat = 24.90;
  static const maxLat = 25.25;

  static bool contains(double lng, double lat) =>
      lng >= minLng && lng <= maxLng && lat >= minLat && lat <= maxLat;

  const TaipeiBounds._();
}
