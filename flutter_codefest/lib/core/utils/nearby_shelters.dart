import 'dart:math';

import 'package:flutter_codefest/data/models/shelter.dart';

/// Distance between two WGS84 points, in metres.
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);

  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);

  return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _deg2rad(double deg) => deg * pi / 180;

double distanceToShelter(Shelter shelter, double lat, double lon) =>
    calculateDistance(lat, lon, shelter.latitude!, shelter.longitude!);

const _walkingSpeedMetersPerSecond = 1.4;

/// A rough walking-time estimate from straight-line distance. Not real
/// routing — no path-following, no road network — so it undercounts actual
/// walking time on non-direct routes.
Duration estimateWalkingDuration(double meters) =>
    Duration(seconds: (meters / _walkingSpeedMetersPerSecond).round());

/// e.g. "約 12 分鐘（步行，直線距離估算）". Always at least 1 minute so the
/// label never reads as instantaneous.
String formatWalkingTime(double meters) {
  final minutes = (estimateWalkingDuration(meters).inSeconds / 60).ceil();
  return '約 ${minutes < 1 ? 1 : minutes} 分鐘（步行，直線距離估算）';
}
