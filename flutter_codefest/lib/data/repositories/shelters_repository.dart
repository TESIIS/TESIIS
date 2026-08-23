import 'package:flutter_codefest/data/datasources/api.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/data/models/shelter_page.dart';
import 'package:flutter_codefest/domain/marker_clustering.dart';

/// Query parameters for one `GET /shelters/clusters` request.
///
/// Kept as a plain map (not a typed call) so the view model can reuse the
/// exact same map as the cache key — see `RequestCache.keyFor` — without
/// the two ever drifting apart. [bbox] is the raw
/// `minLng,minLat,maxLng,maxLat` string; pass null for "the whole country".
Map<String, String> clustersQueryParams({
  String? bbox,
  required double zoom,
  Set<String>? disasters,
  Set<String>? spaces,
}) => {
  if (bbox != null) 'bbox': bbox,
  // Whole-number zooms without the trailing ".0" — the cache key must be
  // stable across clients that format the same zoom differently.
  'zoom': zoom == zoom.truncateToDouble() ? '${zoom.toInt()}' : '$zoom',
  if (disasters != null && disasters.isNotEmpty)
    'disasters': disasters.join(','),
  if (spaces != null && spaces.isNotEmpty) 'spaces': spaces.join(','),
};

/// Grid-clustered markers for a map viewport.
///
/// The server groups shelters into count bubbles (single-member clusters
/// embed the full shelter), so a country-wide view transfers a few hundred
/// centroids instead of ~5,850 records. Omit `bbox` for "the whole country" —
/// the clusters endpoint deliberately has no 2° bbox cap.
Future<List<ShelterCluster>> fetchClusters(Map<String, String> params) async {
  final body = await ApiService.get(
    '/shelters/clusters',
    queryParams: params,
  ) as Map<String, dynamic>;
  return [
    for (final cluster in body['clusters'] as List<dynamic>? ?? const [])
      ShelterCluster.fromServerJson(cluster as Map<String, dynamic>),
  ];
}

/// Query parameters for one page of `GET /shelters`.
Map<String, String> sheltersPageQueryParams({
  String? q,
  Set<String>? disasters,
  Set<String>? spaces,
  required int limit,
  required int offset,
}) => {
  if (q != null && q.isNotEmpty) 'q': q,
  if (disasters != null && disasters.isNotEmpty)
    'disasters': disasters.join(','),
  if (spaces != null && spaces.isNotEmpty) 'spaces': spaces.join(','),
  'limit': '$limit',
  'offset': '$offset',
};

/// One page of shelters, matching the search text and filter groups
/// **server-side** — the client no longer downloads the whole dataset to
/// filter a few hundred rows out of it.
Future<ShelterPage> fetchSheltersPage(Map<String, String> params) async {
  return ShelterPage.fromJson(
    await ApiService.get('/shelters', queryParams: params)
        as Map<String, dynamic>,
  );
}

/// Shelters near a point, sorted by distance, computed server-side.
///
/// Preferred over downloading everything and sorting locally: on mobile data
/// during an emergency, transferring 400 records to find the nearest three is
/// the wrong trade.
Future<List<Shelter>> fetchNearbyShelters({
  required double lat,
  required double lng,
  double? radiusMeters,
  int limit = 10,
}) async {
  final body = await ApiService.get(
    '/shelters/nearby',
    queryParams: {
      'lat': '$lat',
      'lng': '$lng',
      if (radiusMeters != null) 'radius': '$radiusMeters',
      'limit': '$limit',
    },
  ) as Map<String, dynamic>;
  return [
    for (final entry in body['data'] as List<dynamic>? ?? const [])
      Shelter.fromJson(entry as Map<String, dynamic>),
  ];
}

/// Raw `GET /shelters/stats` body, including the per-region coordinate
/// quality breakdown. Kept as a `Map` passthrough — see
/// `RegionCoordinateStats.listFromStatsJson` for the model that shapes it.
Future<Map<String, dynamic>> fetchShelterStats() async =>
    (await ApiService.get('/shelters/stats')) as Map<String, dynamic>;
