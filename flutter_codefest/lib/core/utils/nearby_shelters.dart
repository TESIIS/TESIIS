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

/// Shelters that can actually be placed on a map.
///
/// About 5% of the dataset has no coordinate. Those are still worth listing —
/// see the "尚無座標" handling in the UI — but they cannot be sorted by
/// distance, so distance-based helpers drop them.
List<Shelter> locatableShelters(List<Shelter> shelters) => shelters
    .where((s) => s.hasCoordinate && s.latitude != 0.0 && s.longitude != 0.0)
    .toList(growable: false);

/// Every locatable shelter, ordered by distance. **Does not truncate.**
///
/// Kept separate from [nearestShelters] on purpose. The two used to be one
/// function with `limit = 5`, and the filter and search paths called it just to
/// sort — silently capping every filtered result and every search result at
/// five entries no matter how many actually matched.
List<Shelter> sortedByDistance(List<Shelter> shelters, double lat, double lon) {
  final out = locatableShelters(shelters)
    ..sort(
      (a, b) => distanceToShelter(
        a,
        lat,
        lon,
      ).compareTo(distanceToShelter(b, lat, lon)),
    );
  return out;
}

/// The [limit] closest shelters. Use this only where a cap is intended.
List<Shelter> nearestShelters(
  List<Shelter> shelters,
  double lat,
  double lon, {
  int limit = 5,
}) => sortedByDistance(shelters, lat, lon).take(limit).toList(growable: false);
