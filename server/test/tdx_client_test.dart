import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server/core/config/env.dart';
import 'package:server/core/errors/app_exception.dart';
import 'package:server/data/datasources/external/tdx_client.dart';
import 'package:test/test.dart';

String _tokenBody({int expiresIn = 86400}) => jsonEncode({
  'access_token': 'test-token',
  'token_type': 'Bearer',
  'expires_in': expiresIn,
});

void main() {
  setUp(() {
    Env.loadFromLines([
      'TDX_CLIENT_ID=test-id',
      'TDX_CLIENT_SECRET=test-secret',
    ]);
  });

  test('fetches a token once and reuses it across calls', () async {
    var tokenCalls = 0;
    var dataCalls = 0;

    final client = TdxClient(
      client: MockClient((request) async {
        if (request.url.path.contains('openid-connect/token')) {
          tokenCalls++;
          return http.Response(_tokenBody(), 200);
        }
        dataCalls++;
        return http.Response(jsonEncode([]), 200);
      }),
    );

    await client.nearbyTraStations(lat: 25, lng: 121, radiusMeters: 500);
    await client.nearbyThsrStations(lat: 25, lng: 121, radiusMeters: 500);

    expect(tokenCalls, 1);
    expect(dataCalls, 2);
  });

  test('sends the radius as an integer, never a decimal', () async {
    String? capturedQuery;
    final client = TdxClient(
      client: MockClient((request) async {
        if (request.url.path.contains('openid-connect/token')) {
          return http.Response(_tokenBody(), 200);
        }
        capturedQuery = request.url.query;
        return http.Response(jsonEncode([]), 200);
      }),
    );

    // TDX's odata parser 400s on a decimal distance ("Distance need to be
    // integer type") — confirmed against the live API, not guessed.
    await client.nearbyTraStations(lat: 25, lng: 121, radiusMeters: 500.7);

    expect(capturedQuery, contains('25.0%2C121.0%2C501%29'));
    // The 501 must not be followed by a decimal point before the closing
    // paren — %2C=',' %29=')'.
    expect(capturedQuery, isNot(contains('501.0')));
  });

  test('clamps radius to TDX\'s 1000m hard limit', () async {
    String? capturedQuery;
    final client = TdxClient(
      client: MockClient((request) async {
        if (request.url.path.contains('openid-connect/token')) {
          return http.Response(_tokenBody(), 200);
        }
        capturedQuery = request.url.query;
        return http.Response(jsonEncode([]), 200);
      }),
    );

    await client.nearbyTraStations(lat: 25, lng: 121, radiusMeters: 5000);

    expect(capturedQuery, contains('25.0%2C121.0%2C1000%29'));
  });

  test(
    'a failed request backs off instead of retrying immediately',
    () async {
      var dataCalls = 0;
      final client = TdxClient(
        client: MockClient((request) async {
          if (request.url.path.contains('openid-connect/token')) {
            return http.Response(_tokenBody(), 200);
          }
          dataCalls++;
          return http.Response('{"Message":"boom"}', 500);
        }),
      );

      await expectLater(
        client.nearbyTraStations(lat: 25, lng: 121, radiusMeters: 500),
        throwsA(isA<ServiceUnavailableException>()),
      );
      expect(dataCalls, 1);

      // Immediately retrying should fail fast off the backoff window rather
      // than hitting the network again.
      await expectLater(
        client.nearbyTraStations(lat: 25, lng: 121, radiusMeters: 500),
        throwsA(isA<ServiceUnavailableException>()),
      );
      expect(dataCalls, 1);
    },
  );

  test('missing credentials fails without any network call', () async {
    Env.loadFromLines(const []);
    var networkCalls = 0;
    final client = TdxClient(
      client: MockClient((request) async {
        networkCalls++;
        return http.Response(_tokenBody(), 200);
      }),
    );

    await expectLater(
      client.nearbyTraStations(lat: 25, lng: 121, radiusMeters: 500),
      throwsA(isA<ServiceUnavailableException>()),
    );
    expect(networkCalls, 0);
  });
}
