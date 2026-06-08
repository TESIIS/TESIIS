import 'dart:convert';

class ErrorResponse {
  final bool success;
  final String message;
  final String? code;
  final int status;
  final Map<String, dynamic>? details;

  ErrorResponse({
    required this.message,
    this.code,
    required this.status,
    this.details,
  }) : success = false;

  Map<String, dynamic> toJson() => {
        'success': success,
        'status': status,
        'message': message,
        if (code != null) 'code': code,
        if (details != null) 'details': details,
      };

  @override
  String toString() => jsonEncode(toJson());
}
