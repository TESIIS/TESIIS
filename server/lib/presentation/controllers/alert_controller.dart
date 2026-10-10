import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/geo/city_codes.dart';
import '../../domain/entities/shelter_fields.dart';
import '../../domain/services/alert_service.dart';

class AlertController {
  AlertController({required this.service});
  final AlertService service;
  final _logger = Logger('AlertController');
  static const _headers = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  };
  Router get router => Router()..get('/alerts', _getAlerts);
  Response _bad(String message) => Response.badRequest(
    body: jsonEncode({'success': false, 'message': message}),
    headers: _headers,
  );

  Future<Response> _getAlerts(Request request) async {
    final params = request.url.queryParameters;
    if (params.keys.any(
      (k) => !{'city', 'township', 'history', 'limit'}.contains(k),
    )) {
      return _bad('Unknown alert query parameter');
    }
    final city = params['city'] == null
        ? null
        : CityCodes.byNormalizedName(ShelterText.normalizeName(params['city']));
    if (params.containsKey('city') && city == null) {
      return _bad('city must be one of the 22 counties');
    }
    final township = params['township']?.trim().replaceAll('台', '臺');
    if (township != null &&
        (city == null || township.isEmpty || township.length > 20)) {
      return _bad('township requires city and a nonempty name');
    }
    if (params.containsKey('history') &&
        !{'true', 'false'}.contains(params['history'])) {
      return _bad('history must be true or false');
    }
    final limit = int.tryParse(params['limit'] ?? '200');
    if (limit == null || limit < 1 || limit > 200) {
      return _bad('limit must be between 1 and 200');
    }
    try {
      return Response.ok(
        jsonEncode(
          await service.query(
            city: city?.displayName,
            township: township,
            includeHistory: params['history'] == 'true',
            limit: limit,
          ),
        ),
        headers: _headers,
      );
    } catch (e, s) {
      _logger.warning('GET /alerts unavailable', e, s);
      return Response(
        503,
        body: jsonEncode({
          'success': false,
          'available': false,
          'message': 'Alert source temporarily unavailable',
        }),
        headers: _headers,
      );
    }
  }
}
