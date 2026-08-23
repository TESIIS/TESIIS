import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../../../core/errors/app_exception.dart';

/// Thin client for the three TDX resources this project uses:
///
///   - `Bus/Stop/City/{City}` — bus stops, scoped per county/city. TDX has
///     no nationwide "nearby" bus resource, so the city must be known
///     up front (see `city_codes.dart`'s `tdxName`).
///   - `Rail/TRA/Station` — nationwide, no city scoping needed.
///   - `Rail/THSR/Station` — nationwide, no city scoping needed.
///
/// All three are queried with `$spatialFilter=nearby(lat,lng,radius)`. TDX
/// itself caps `radius` at 1000 meters (a larger value 400s) — callers must
/// clamp before calling in here.
///
/// Handles OAuth2 client-credentials token caching and a failure backoff so
/// an outage doesn't turn every request into a fresh retry against a
/// dependency that is already unwell — same reasoning as
/// `ShelterRepositoryImpl`'s `_retryNotBefore`.
class TdxClient {
  TdxClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  String? _token;
  DateTime? _tokenExpiresAt;

  /// Re-fetch this long before actual expiry, so a request never races a
  /// token that's about to lapse mid-flight.
  static const _tokenRefreshBuffer = Duration(seconds: 60);

  /// How long to refuse new attempts after a failure, so a TDX outage
  /// doesn't turn every incoming request into its own retry storm.
  static const _failureBackoff = Duration(seconds: 30);

  DateTime? _retryNotBefore;

  bool get _inBackoff {
    final until = _retryNotBefore;
    return until != null && DateTime.now().isBefore(until);
  }

  bool get _hasFreshToken {
    final token = _token;
    final expiresAt = _tokenExpiresAt;
    return token != null &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt.subtract(_tokenRefreshBuffer));
  }

  Future<String> _fetchToken() async {
    final clientId = Env.tdxClientId;
    final clientSecret = Env.tdxClientSecret;
    if (clientId == null || clientSecret == null) {
      throw ServiceUnavailableException('TDX credentials not configured');
    }

    final resp = await _client
        .post(
          Uri.parse(Env.tdxAuthUrl),
          headers: const {'content-type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'client_credentials',
            'client_id': clientId,
            'client_secret': clientSecret,
          },
        )
        .timeout(Env.tdxTimeout);

    if (resp.statusCode != 200) {
      throw ServiceUnavailableException(
        'TDX token request failed: ${resp.statusCode}',
      );
    }

    final body =
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final token = body['access_token'] as String?;
    final expiresIn = body['expires_in'] as int?;
    if (token == null || expiresIn == null) {
      throw ServiceUnavailableException('TDX token response malformed');
    }

    _token = token;
    _tokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    return token;
  }

  Future<String> _ensureToken() async {
    if (_hasFreshToken) return _token!;
    return _fetchToken();
  }

  Future<List<dynamic>> _get(String path, Map<String, String> query) async {
    if (_inBackoff) {
      throw ServiceUnavailableException('TDX temporarily unavailable');
    }

    try {
      final token = await _ensureToken();
      final uri = Uri.parse(
        '${Env.tdxApiBaseUrl}$path',
      ).replace(queryParameters: {...query, r'$format': 'JSON'});

      final resp = await _client
          .get(uri, headers: {'authorization': 'Bearer $token'})
          .timeout(Env.tdxTimeout);

      if (resp.statusCode != 200) {
        throw ServiceUnavailableException(
          'TDX request failed: ${resp.statusCode} for $path: '
          '${utf8.decode(resp.bodyBytes)}',
        );
      }

      _retryNotBefore = null;
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      return decoded is List ? decoded : const [];
    } catch (e) {
      _retryNotBefore = DateTime.now().add(_failureBackoff);
      if (e is ServiceUnavailableException) rethrow;
      throw ServiceUnavailableException('TDX request errored: $e');
    }
  }

  /// Clamped to TDX's own hard limit — a larger value 400s. Rounded to an
  /// int: TDX's odata `nearby()` parser rejects a decimal distance outright
  /// ("Distance need to be integer type"), confirmed against a live 400.
  static int _clampRadius(double radiusMeters) =>
      radiusMeters.clamp(1, 1000).round();

  Future<List<dynamic>> nearbyBusStops({
    required String tdxCity,
    required double lat,
    required double lng,
    required double radiusMeters,
    int top = 30,
  }) => _get('/v2/Bus/Stop/City/$tdxCity', {
    r'$spatialFilter': 'nearby($lat,$lng,${_clampRadius(radiusMeters)})',
    r'$top': '$top',
  });

  Future<List<dynamic>> nearbyTraStations({
    required double lat,
    required double lng,
    required double radiusMeters,
    int top = 10,
  }) => _get('/v2/Rail/TRA/Station', {
    r'$spatialFilter': 'nearby($lat,$lng,${_clampRadius(radiusMeters)})',
    r'$top': '$top',
  });

  Future<List<dynamic>> nearbyThsrStations({
    required double lat,
    required double lng,
    required double radiusMeters,
    int top = 10,
  }) => _get('/v2/Rail/THSR/Station', {
    r'$spatialFilter': 'nearby($lat,$lng,${_clampRadius(radiusMeters)})',
    r'$top': '$top',
  });
}
