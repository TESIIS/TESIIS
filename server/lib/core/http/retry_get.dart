import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Retries temporary download failures without accepting an incomplete file.
/// Government data hosts occasionally close a connection mid-response.
Future<http.Response> getWithRetry(
  http.Client client,
  Uri uri, {
  int attempts = 3,
  Duration retryDelay = const Duration(seconds: 2),
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (attempts < 1) throw ArgumentError.value(attempts, 'attempts');

  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode == 200) return response;
      final retryable =
          response.statusCode == 429 || response.statusCode >= 500;
      if (!retryable || attempt == attempts) {
        throw HttpException('GET $uri failed: HTTP ${response.statusCode}');
      }
      stderr.writeln(
        'GET $uri returned HTTP ${response.statusCode}; retrying ($attempt/$attempts)',
      );
    } on http.ClientException catch (error) {
      if (attempt == attempts) rethrow;
      stderr.writeln(
        'GET $uri interrupted: $error; retrying ($attempt/$attempts)',
      );
    } on SocketException catch (error) {
      if (attempt == attempts) rethrow;
      stderr.writeln(
        'GET $uri interrupted: $error; retrying ($attempt/$attempts)',
      );
    } on TimeoutException catch (error) {
      if (attempt == attempts) rethrow;
      stderr.writeln(
        'GET $uri timed out: $error; retrying ($attempt/$attempts)',
      );
    }
    await Future<void>.delayed(retryDelay * attempt);
  }

  throw StateError('Unreachable download retry state');
}
