import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server/core/http/retry_get.dart';
import 'package:test/test.dart';

void main() {
  final uri = Uri.parse('https://example.test/data.csv');

  test('retries a response interrupted during download', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      if (calls == 1) {
        throw http.ClientException('Connection closed while receiving data');
      }
      return http.Response('valid data', 200);
    });

    final response = await getWithRetry(client, uri, retryDelay: Duration.zero);
    expect(response.body, 'valid data');
    expect(calls, 2);
  });

  test('retries server errors but not a missing resource', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('unavailable', calls == 1 ? 503 : 200);
    });
    expect(
      (await getWithRetry(client, uri, retryDelay: Duration.zero)).statusCode,
      200,
    );
    expect(calls, 2);

    var missingCalls = 0;
    final missing = MockClient((_) async {
      missingCalls++;
      return http.Response('missing', 404);
    });
    await expectLater(
      getWithRetry(missing, uri, retryDelay: Duration.zero),
      throwsA(isA<HttpException>()),
    );
    expect(missingCalls, 1);
  });
}
