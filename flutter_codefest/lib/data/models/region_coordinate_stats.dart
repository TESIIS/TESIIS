/// One township's coordinate-quality slice, flattened out of the nested
/// `byRegion[*].townships[*].coordinateQuality` shape `GET /shelters/stats`
/// returns — the data-quality page only ever needs a flat, sortable list.
class RegionCoordinateStats {
  const RegionCoordinateStats({
    required this.city,
    required this.township,
    required this.total,
    required this.withCoordinates,
    required this.missing,
  });

  final String city;
  final String township;
  final int total;
  final int withCoordinates;
  final int missing;

  factory RegionCoordinateStats.fromTownshipJson(
    String city,
    Map<String, dynamic> json,
  ) {
    final quality = json['coordinateQuality'] as Map<String, dynamic>;
    return RegionCoordinateStats(
      city: city,
      township: json['township'] as String,
      total: quality['total'] as int,
      withCoordinates: quality['withCoordinates'] as int,
      missing: quality['missing'] as int,
    );
  }

  /// Parses the raw `GET /shelters/stats` body into one row per township,
  /// sorted by missing-coordinate count descending — the whole point of the
  /// page is to surface the worst-covered areas first.
  static List<RegionCoordinateStats> listFromStatsJson(
    Map<String, dynamic> statsJson,
  ) {
    final byRegion = statsJson['byRegion'] as List<dynamic>? ?? const [];
    final rows = [
      for (final cityEntry in byRegion.cast<Map<String, dynamic>>())
        for (final township
            in (cityEntry['townships'] as List<dynamic>)
                .cast<Map<String, dynamic>>())
          RegionCoordinateStats.fromTownshipJson(
            cityEntry['city'] as String,
            township,
          ),
    ];
    rows.sort((a, b) => b.missing.compareTo(a.missing));
    return rows;
  }
}
