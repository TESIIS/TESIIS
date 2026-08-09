// lib/presentation/controllers/shelter_controller.dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../domain/entities/shelter.dart';
import '../../domain/entities/shelter_fields.dart';
import '../../domain/services/shelter_service.dart';

/// The query shared by every endpoint, parsed once.
///
/// Both handlers used to parse the same 16 parameters independently, which is
/// how `/shelters/stats` ended up echoing back a `filters` object that silently
/// omitted `villages`.
class _ShelterQuery {
  _ShelterQuery({
    required this.q,
    required this.city,
    required this.township,
    required this.village,
    required this.villages,
    required this.type,
    required this.hazards,
    required this.matchMode,
  });

  final String? q;
  final String? city;
  final String? township;
  final String? village;
  final List<String>? villages;
  final String? type;
  final Map<String, String> hazards;
  final String matchMode;

  /// Hazard parameters, accepted under both an English and a Chinese name.
  static const _hazardAliases = {
    'flood': '水災',
    'quake': '震災',
    'landslide': '土石流',
    'tsunami': '海嘯',
    'relief': '救濟支站',
    'accessible': '無障礙設施',
    'indoor': '室內',
    'outdoor': '室外',
  };

  factory _ShelterQuery.from(Request request) {
    final params = request.url.queryParameters;

    final hazards = <String, String>{};
    _hazardAliases.forEach((en, zh) {
      final value = params[en] ?? params[zh];
      if (value != null && value.isNotEmpty) hazards[zh] = value;
    });

    // `villages` accepts either repeated parameters (?villages=A&villages=B)
    // or one delimited value (?villages=A,B).
    final rawVillages =
        request.url.queryParametersAll['villages'] ?? const <String>[];
    final villages = <String>[
      for (final value in rawVillages) ...ShelterText.splitVillages(value),
    ];

    return _ShelterQuery(
      q: params['q'],
      city: params['city'] ?? params['縣市'],
      township: params['township'] ?? params['鄉鎮'],
      village: params['village'] ?? params['村里'],
      villages: villages.isEmpty ? null : villages,
      type: params['type'] ?? params['類型'],
      hazards: hazards,
      matchMode: (params['match'] ?? 'and').toLowerCase() == 'or'
          ? 'or'
          : 'and',
    );
  }

  Map<String, dynamic> toJson() => {
    if (q != null) 'q': q,
    if (city != null) 'city': city,
    if (township != null) 'township': township,
    if (village != null) 'village': village,
    if (villages != null) 'villages': villages,
    if (type != null) 'type': type,
    if (hazards.isNotEmpty) 'hazards': hazards,
    'match': matchMode,
  };
}

class ShelterController {
  ShelterController({required this.service});

  final ShelterService service;
  final Logger _logger = Logger('ShelterController');

  Router get router {
    final r = Router();
    r.get('/shelters', _getShelters);
    r.get('/shelters/stats', _getShelterStats);
    r.get('/shelters/nearby', _getNearbyShelters);
    return r;
  }

  static const _jsonHeaders = {'content-type': 'application/json'};

  Response _ok(Object body) =>
      Response.ok(jsonEncode(body), headers: _jsonHeaders);

  Response _badRequest(String message) => Response.badRequest(
    body: jsonEncode({'success': false, 'message': message}),
    headers: _jsonHeaders,
  );

  /// Logs the detail, returns a generic message.
  ///
  /// These handlers used to put `e.toString()` straight into the response body,
  /// which leaks upstream URLs, file paths and stack detail to any caller.
  Response _serverError(String route, Object error, StackTrace stackTrace) {
    _logger.severe('Error in $route', error, stackTrace);
    return Response.internalServerError(
      body: jsonEncode({
        'success': false,
        'message': 'Internal server error. See server logs for details.',
      }),
      headers: _jsonHeaders,
    );
  }

  List<Shelter> _applyFilters(List<Shelter> data, _ShelterQuery query) =>
      service.filterShelters(
        data: data,
        city: query.city,
        township: query.township,
        village: query.village,
        villages: query.villages,
        type: query.type,
        keyword: query.q,
        hazards: query.hazards.isEmpty ? null : query.hazards,
        matchMode: query.matchMode,
      );

  Map<String, dynamic> _toJson(Shelter e, {double? distanceMeters}) => {
    'id': e.id,
    'importDate': e.importDate?.toIso8601String(),
    '收容所編號': e.shelterCode,
    '名稱': e.name,
    '縣市': e.city,
    '郵遞區號': e.zipcode,
    '鄉鎮': e.township,
    '村里': e.village,
    '門牌地址': e.address,
    '類型': e.type,
    '水災': HazardFlag.normalizeForOutput(e.flood),
    '震災': HazardFlag.normalizeForOutput(e.quake),
    '土石流': HazardFlag.normalizeForOutput(e.landslide),
    '海嘯': HazardFlag.normalizeForOutput(e.tsunami),
    '救濟支站': HazardFlag.normalizeForOutput(e.relief),
    '無障礙設施': HazardFlag.normalizeForOutput(e.accessible),
    '室內': HazardFlag.normalizeForOutput(e.indoor),
    '室外': HazardFlag.normalizeForOutput(e.outdoor),
    '服務里別': ShelterText.splitVillages(e.serviceVillages),
    '容納人數': e.capacity,
    '收容所面積(平方公尺)': e.area,
    '聯絡人姓名': e.contactName,
    '聯絡人連絡電話': e.contactPhone,
    '管理人姓名': e.managerName,
    '管理人連絡電話': e.managerPhone,
    '備考': e.notes,
    '座標x': e.x,
    '座標y': e.y,
    // Null for the shelters the coordinate table could not locate, so a
    // client can tell "no coordinate" from "coordinate we are unsure of".
    '座標來源': e.coordinateSource,
    '座標精度': e.coordinateConfidence,
    if (distanceMeters != null) '距離公尺': distanceMeters.round(),
  };

  Future<Response> _getShelters(Request request) async {
    try {
      final query = _ShelterQuery.from(request);
      final params = request.url.queryParameters;
      // limit/offset page the *filtered* result, not the upstream fetch.
      final limit = int.tryParse(params['limit'] ?? '') ?? 1000;
      final offset = int.tryParse(params['offset'] ?? '') ?? 0;
      if (limit < 0 || offset < 0) {
        return _badRequest('limit and offset must not be negative');
      }

      final filtered = _applyFilters(await service.fetchAllShelters(), query);
      final paged = filtered.skip(offset).take(limit);

      return _ok({
        'success': true,
        'data': [for (final e in paged) _toJson(e)],
        'total': filtered.length,
      });
    } catch (e, s) {
      return _serverError('GET /shelters', e, s);
    }
  }

  Future<Response> _getShelterStats(Request request) async {
    try {
      final query = _ShelterQuery.from(request);
      final stats = service.computeStats(
        data: await service.fetchAllShelters(),
        city: query.city,
        township: query.township,
        village: query.village,
        villages: query.villages,
        type: query.type,
        hazards: query.hazards.isEmpty ? null : query.hazards,
        keyword: query.q,
        matchMode: query.matchMode,
      );

      return _ok({
        'success': true,
        'filters': query.toJson(),
        // How much of the dataset can actually be plotted. Surfaced because the
        // upstream dataset has no coordinates at all, so this number is the
        // honest measure of how complete the map is.
        'coordinateCoverage': service.coordinateCoverage.toJson(),
        ...stats,
      });
    } catch (e, s) {
      return _serverError('GET /shelters/stats', e, s);
    }
  }

  /// `GET /api/shelters/nearby?lat=&lng=&radius=&limit=`
  ///
  /// Sorting by distance server-side means a client no longer has to download
  /// every shelter just to find the closest one — the thing you actually want
  /// on a phone, on mobile data, during a disaster.
  Future<Response> _getNearbyShelters(Request request) async {
    try {
      final params = request.url.queryParameters;
      final lat = double.tryParse(params['lat'] ?? '');
      final lng = double.tryParse(params['lng'] ?? '');
      if (lat == null || lng == null) {
        return _badRequest('lat and lng are required and must be numbers');
      }
      final radius = double.tryParse(params['radius'] ?? '');
      final limit = int.tryParse(params['limit'] ?? '') ?? 10;
      if (limit < 0) return _badRequest('limit must not be negative');

      final query = _ShelterQuery.from(request);
      final filtered = _applyFilters(await service.fetchAllShelters(), query);

      final withDistance = <(Shelter, double)>[];
      for (final shelter in filtered) {
        if (!shelter.hasCoordinate) continue;
        final distance = _haversineMeters(lat, lng, shelter.y!, shelter.x!);
        if (radius != null && distance > radius) continue;
        withDistance.add((shelter, distance));
      }
      withDistance.sort((a, b) => a.$2.compareTo(b.$2));

      return _ok({
        'success': true,
        'origin': {'lat': lat, 'lng': lng},
        if (radius != null) 'radius': radius,
        'data': [
          for (final (shelter, distance) in withDistance.take(limit))
            _toJson(shelter, distanceMeters: distance),
        ],
        'total': withDistance.length,
        // Shelters excluded purely because we have no coordinate for them.
        // Reported so a client can tell the user the list is incomplete rather
        // than implying nothing else exists nearby.
        'excludedWithoutCoordinates': filtered
            .where((s) => !s.hasCoordinate)
            .length,
      });
    } catch (e, s) {
      return _serverError('GET /shelters/nearby', e, s);
    }
  }
}

const _earthRadiusMeters = 6371000.0;

double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
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
