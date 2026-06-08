import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Standardized JSON response helpers.
/// Success shape: { success: true, data?, total?, filters? }
/// Error shape:   { success: false, message, code? }
class JsonResponse {
  static const _headers = {'content-type': 'application/json'};

  static Response ok({Object? data, int? total, Map<String, dynamic>? filters}) {
    final body = <String, dynamic>{'success': true};
    if (data != null) body['data'] = data;
    if (total != null) body['total'] = total;
    if (filters != null && filters.isNotEmpty) body['filters'] = filters;
    return Response.ok(jsonEncode(body), headers: _headers);
  }

  static Response created({Object? data}) {
    final body = {'success': true, if (data != null) 'data': data};
    return Response(201, body: jsonEncode(body), headers: _headers);
  }

  static Response badRequest(String message, {String? code, Map<String, dynamic>? details}) {
    final body = {
      'success': false,
      'message': message,
      if (code != null) 'code': code,
      if (details != null && details.isNotEmpty) 'details': details,
    };
    return Response(400, body: jsonEncode(body), headers: _headers);
  }

  static Response notFound(String message) {
    return Response(404, body: jsonEncode({'success': false, 'message': message}), headers: _headers);
  }

  static Response error(String message, {String? code, int statusCode = 500}) {
    final body = {
      'success': false,
      'message': message,
      if (code != null) 'code': code,
    };
    return Response(statusCode, body: jsonEncode(body), headers: _headers);
  }
}
