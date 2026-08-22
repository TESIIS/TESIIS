import 'package:flutter_codefest/data/datasources/api.dart';
import 'package:flutter_codefest/data/models/api_response.dart';
import 'package:flutter_codefest/data/models/shelter.dart';

List<Shelter> _parseShelters(dynamic response) {
  return ApiResponse<List<Shelter>>.fromJson(
    response,
    (json) => (json as List<dynamic>)
        .map((e) => Shelter.fromJson(e as Map<String, dynamic>))
        .toList(),
  ).data;
}

Future<List<Shelter>> fetchAllShelters() async =>
    _parseShelters(await ApiService.get('/shelters'));

Future<List<Shelter>> fetchFilteredShelters({
  String? q,
  String? city,
  String? township,
  String? village,
  String? type,
  String match = 'and',
  String? flood,
  String? quake,
  String? landslide,
  String? tsunami,
  String? relief,
  String? accessible,
  String? indoor,
  String? outdoor,
}) async {
  final queryParams = <String, String>{
    if (q != null && q.isNotEmpty) 'q': q,
    if (city != null) 'city': city,
    if (township != null) 'township': township,
    if (village != null) 'village': village,
    if (type != null) 'type': type,
    'match': match,
  };

  // Hazard conditions go over the wire as 'Y'.
  //
  // This used to send the string 'true'. The server happened to accept it, but
  // it is not what the API documents and it made ?quake=備用 — which asks for
  // that variant specifically — impossible to express. Pass the value through.
  <String, String?>{
    'flood': flood,
    'quake': quake,
    'landslide': landslide,
    'tsunami': tsunami,
    'relief': relief,
    'accessible': accessible,
    'indoor': indoor,
    'outdoor': outdoor,
  }.forEach((key, value) {
    if (value != null && value.isNotEmpty) queryParams[key] = value;
  });

  return _parseShelters(
    await ApiService.get('/shelters', queryParams: queryParams),
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
  return _parseShelters(
    await ApiService.get(
      '/shelters/nearby',
      queryParams: {
        'lat': '$lat',
        'lng': '$lng',
        if (radiusMeters != null) 'radius': '$radiusMeters',
        'limit': '$limit',
      },
    ),
  );
}

/// Raw `GET /shelters/stats` body, including the per-region coordinate
/// quality breakdown. Kept as a `Map` passthrough — see
/// `RegionCoordinateStats.listFromStatsJson` for the model that shapes it.
Future<Map<String, dynamic>> fetchShelterStats() async =>
    (await ApiService.get('/shelters/stats')) as Map<String, dynamic>;
