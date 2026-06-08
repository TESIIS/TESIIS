import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://localhost:8080/api';

  // GET
  static Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
  }) async {
    final url = Uri.parse(
      '$baseUrl$endpoint',
    ).replace(queryParameters: queryParams);
    final response = await http.get(url);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('GET $endpoint failed: ${response.statusCode}');
    }
  }

  // POST with JSON body
  static Future<dynamic> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('POST $endpoint failed: ${response.statusCode}');
    }
  }
}
