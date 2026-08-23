import 'dart:math' as math;

const _earthRadiusMeters = 6371000.0;

/// Great-circle distance between two WGS84 points, in meters.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  double toRadians(double degrees) => degrees * math.pi / 180.0;

  final dLat = toRadians(lat2 - lat1);
  final dLng = toRadians(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRadians(lat1)) *
          math.cos(toRadians(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return _earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
