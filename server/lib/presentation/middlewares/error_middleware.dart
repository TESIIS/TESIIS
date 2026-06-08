import 'package:shelf/shelf.dart';
import '../../core/errors/app_exception.dart';
import '../responses/json_response.dart';
import 'package:logging/logging.dart';

final _logger = Logger('ErrorMiddleware');

/// Global error handling middleware that converts exceptions to proper JSON responses
Middleware handleErrors() {
  return (Handler innerHandler) {
    return (Request request) async {
      try {
        final response = await innerHandler(request);
        return response;
      } on BadRequestException catch (e, st) {
        _logger.warning('Bad request: ${e.message}', e, st);
        return JsonResponse.error(e.message, code: e.code, statusCode: e.statusCode);
      } on NotFoundException catch (e, st) {
        _logger.warning('Not found: ${e.message}', e, st);
        return JsonResponse.error(e.message, code: e.code, statusCode: e.statusCode);
      } on AppException catch (e, st) {
        _logger.severe('Application error: ${e.message}', e, st);
        return JsonResponse.error(e.message, code: e.code, statusCode: e.statusCode);
      } catch (e, st) {
        _logger.severe('Unhandled error', e, st);
        return JsonResponse.error('伺服器發生未預期的錯誤');
      }
    };
  };
}