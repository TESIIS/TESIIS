import 'dart:io';
import 'app_exception.dart';
import 'error_response.dart';
import '../logger/app_logger.dart';

class ErrorHandler {
  static Future<void> handle(HttpRequest req, Exception error, [StackTrace? st]) async {
    final response = req.response;
    late ErrorResponse errorResponse;

    if (error is AppException) {
      errorResponse = ErrorResponse(
        message: error.message,
        code: error.code,
        status: error.statusCode,
      );
      response.statusCode = error.statusCode;
    } else {
      errorResponse = ErrorResponse(
        message: 'Internal Server Error',
        status: 500,
      );
      response.statusCode = 500;
    }

    response.headers.contentType = ContentType.json;
    response.write(errorResponse.toString());
    await response.close();

    final uri = req.uri.toString();
    final method = req.method;
    final clientIp = req.connectionInfo?.remoteAddress.address ?? 'unknown';

    AppLogger.error(
      "[$method] $uri (${response.statusCode}) from $clientIp",
      error: error,
      stackTrace: st ?? StackTrace.current,
    );
  }
}
