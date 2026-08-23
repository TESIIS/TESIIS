import 'dart:math' as math;

import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:latlong2/latlong.dart';

/// One marker's worth of shelters — a single shelter when [isSingle], or a
/// group close enough together at the current zoom to draw as one.
class ShelterCluster {
  const ShelterCluster({
    required this.center,
    required this.members,
    int? count,
  }) : count = count ?? members.length;

  final LatLng center;
  final List<Shelter> members;

  /// Member count. Multi-member clusters built from server data carry the
  /// count in the payload but no members (the whole point of the clusters
  /// endpoint is that members are not transferred), hence the override.
  final int count;

  bool get isSingle => count == 1;

  /// A single-member cluster's shelter, for tap handling. Only valid when
  /// [isSingle].
  Shelter get single => members.single;

  /// A cluster as returned by `GET /shelters/clusters`: single-member
  /// clusters arrive with their full shelter embedded, multi-member ones
  /// with just a centroid and count.
  factory ShelterCluster.fromServerJson(Map<String, dynamic> json) {
    final shelterJson = json['shelter'] as Map<String, dynamic>?;
    return ShelterCluster(
      center: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lng'] as num).toDouble(),
      ),
      members: shelterJson == null ? const [] : [Shelter.fromJson(shelterJson)],
      count: (json['count'] as num).toInt(),
    );
  }

  /// Serialises back into the server's wire shape, so cached cluster
  /// responses can be stored and re-read with [fromServerJson].
  Map<String, dynamic> toJson() => {
    'count': count,
    'lat': center.latitude,
    'lng': center.longitude,
    if (isSingle) 'shelter': single.toJson(),
  };
}

/// Grid-buckets [shelters] (which must all have a coordinate) into clusters
/// whose on-screen footprint is roughly [cellPixels] wide at [zoom].
///
/// Nationwide scale (~5,850 shelters) makes clustering a legibility need,
/// not just a performance one — a broad search or filter can return
/// thousands of results, and Taipei's dense districts already stack markers
/// close enough to be unreadable without it. Implemented as a plain grid
/// rather than a real spatial index: `shelters.length` is a few thousand at
/// most, so an O(n) single pass is not worth trading for the complexity of
/// an R-tree — see `flutter_codefest/pubspec.yaml`'s standing
/// minimal-dependency stance for why this is hand-rolled rather than a
/// pulled-in clustering package.
///
/// Cell size is derived from [zoom] using the standard Web Mercator
/// degrees-per-pixel formula, so clusters break apart naturally as the user
/// zooms in with no per-zoom-level tuning table to maintain.
List<ShelterCluster> clusterShelters(
  List<Shelter> shelters, {
  required double zoom,
  double cellPixels = 80,
  int minPointsToCluster = 2,
}) {
  if (shelters.isEmpty) return const [];

  // Longitude degrees per pixel at this zoom (Web Mercator, tile size 256).
  final lngPerPixel = 360 / (256 * math.pow(2, zoom));
  final cellLng = lngPerPixel * cellPixels;

  final buckets = <(int, int), List<Shelter>>{};
  for (final shelter in shelters) {
    // Latitude degrees per pixel scales with cos(latitude) under Web
    // Mercator, so it's computed per-shelter rather than once — cheap at a
    // few thousand shelters, and correct at both the equator-ish south
    // (Taiwan is ~22-26°N, so the difference matters less than at high
    // latitudes, but there is no reason to hardcode an approximation when
    // the real formula is one `cos` call).
    final latRad = shelter.latitude! * math.pi / 180;
    final cellLat =
        (lngPerPixel * cellPixels) / math.cos(latRad).abs().clamp(0.01, 1.0);
    final cellX = (shelter.longitude! / cellLng).floor();
    final cellY = (shelter.latitude! / cellLat).floor();
    buckets.putIfAbsent((cellX, cellY), () => []).add(shelter);
  }

  final clusters = <ShelterCluster>[];
  for (final members in buckets.values) {
    if (members.length < minPointsToCluster) {
      for (final s in members) {
        clusters.add(
          ShelterCluster(
            center: LatLng(s.latitude!, s.longitude!),
            members: [s],
          ),
        );
      }
      continue;
    }
    final centerLat =
        members.map((s) => s.latitude!).reduce((a, b) => a + b) /
        members.length;
    final centerLng =
        members.map((s) => s.longitude!).reduce((a, b) => a + b) /
        members.length;
    clusters.add(
      ShelterCluster(center: LatLng(centerLat, centerLng), members: members),
    );
  }
  return clusters;
}
