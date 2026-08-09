abstract class AppException implements Exception {
  final String message; // 錯誤訊息
  final int statusCode; // HTTP 狀態碼
  final String? code; // 自訂錯誤代碼

  AppException(this.message, {this.statusCode = 500, this.code});

  @override
  String toString() => '[$runtimeType] $message';
}

/// 語法錯誤
class BadRequestException extends AppException {
  BadRequestException(super.message, {super.code}) : super(statusCode: 400);
}

/// 未授權
class UnauthorizedException extends AppException {
  UnauthorizedException(super.message, {super.code}) : super(statusCode: 401);
}

/// 禁止存取
class ForbiddenException extends AppException {
  ForbiddenException(super.message, {super.code}) : super(statusCode: 403);
}

/// 找不到資源
class NotFoundException extends AppException {
  NotFoundException(super.message, {super.code}) : super(statusCode: 404);
}

/// 衝突錯誤
class ConflictException extends AppException {
  ConflictException(super.message, {super.code}) : super(statusCode: 409);
}

/// 伺服器錯誤
class ServerException extends AppException {
  ServerException(super.message, {super.code}) : super(statusCode: 500);
}
