import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  /// Where the Dart backend lives.
  ///
  /// Set at build time, so the same source runs against localhost in
  /// development and against a real host in production:
  ///
  ///   flutter run   --dart-define=API_BASE_URL=http://localhost:8080/api
  ///   flutter build --dart-define=API_BASE_URL=https://api.example.tw/api
  ///
  /// The standalone Docker image builds with `/api`, which keeps browser and
  /// API traffic on one origin. Nginx forwards that path to the Dart service.
  ///
  /// Android emulators reach the host machine at 10.0.2.2, not localhost.
  ///
  /// Use https in production: a Flutter Web app served over https cannot call
  /// an http endpoint — the browser blocks it as mixed content.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api',
  );

  static Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    final url = Uri.parse(
      '$baseUrl$endpoint',
    ).replace(queryParameters: queryParams);
    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('GET $endpoint failed: ${response.statusCode}');
    }
    // The server sends UTF-8; decoding the bytes explicitly avoids the
    // latin-1 fallback that mangles every Chinese field.
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}
