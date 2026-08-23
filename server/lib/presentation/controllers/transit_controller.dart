import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/config/env.dart';
import '../../domain/entities/transit_stop.dart';
import '../../domain/services/transit_service.dart';

/// `GET /api/transit/nearby?lat=&lng=&city=&radius=&limit=`
///
/// `city` is the Chinese county/city name (e.g. `臺北市`) — optional, but
/// without it bus stops are skipped (TDX has no nationwide bus "nearby"
/// resource). `radius` is clamped to TDX's own 1000m hard limit.
///
/// Returns 503 with `available: false` whenever TDX itself is the problem
/// (not configured, down, or every sub-request failed) — this is a
/// degradable feature, not core to the shelter map, so it never returns 500
/// for a caller to trip over.
class TransitController {
  TransitController({required this.service});

  final TransitService service;
  final Logger _logger = Logger('TransitController');

  static const _defaultRadiusMeters = 500.0;
  static const _maxRadiusMeters = 1000.0;
  static const _defaultLimit = 20;
  static const _maxLimit = 50;

  Router get router {
    final r = Router();
    r.get('/transit/nearby', _getNearbyTransit);
    return r;
  }

  static const _jsonHeaders = {'content-type': 'application/json'};

  Response _badRequest(String message) => Response.badRequest(
    body: jsonEncode({'success': false, 'message': message}),
    headers: _jsonHeaders,
  );

  Response _unavailable(String message) => Response(
    503,
    body: jsonEncode({
      'success': false,
      'available': false,
      'message': message,
    }),
    headers: _jsonHeaders,
  );

  Map<String, dynamic> _toJson(TransitStop s) => {
    'id': s.id,
    'name': s.name,
    'mode': s.mode.name,
    'lat': s.lat,
    'lng': s.lng,
    'distanceMeters': s.distanceMeters.round(),
  };

  Future<Response> _getNearbyTransit(Request request) async {
    if (!Env.tdxEnabled) {
      return _unavailable('TDX not configured');
    }

    try {
      final params = request.url.queryParameters;
      final lat = double.tryParse(params['lat'] ?? '');
      final lng = double.tryParse(params['lng'] ?? '');
      if (lat == null || lng == null) {
        return _badRequest('lat and lng are required and must be numbers');
      }

      final radius =
          (double.tryParse(params['radius'] ?? '') ?? _defaultRadiusMeters)
              .clamp(1, _maxRadiusMeters)
              .toDouble();
      final limit = (int.tryParse(params['limit'] ?? '') ?? _defaultLimit)
          .clamp(1, _maxLimit);

      final result = await service.nearby(
        lat: lat,
        lng: lng,
        city: params['city'],
        radiusMeters: radius,
        limit: limit,
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'available': true,
          'partial': result.partial,
          'origin': {'lat': lat, 'lng': lng},
          'data': [for (final s in result.stops) _toJson(s)],
          'total': result.stops.length,
        }),
        headers: _jsonHeaders,
      );
    } catch (e, s) {
      _logger.warning('GET /transit/nearby failed', e, s);
      return _unavailable('TDX request failed');
    }
  }
}
