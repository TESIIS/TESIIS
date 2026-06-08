import 'package:server/core/errors/app_exception.dart';

/// Domain 層用的錯誤物件，不會拋出，只用於返回。
class Failure {
  final String message;         // 錯誤訊息
  final String? code;           // 自訂錯誤代碼
  final StackTrace? stackTrace; // 堆疊追蹤

  const Failure(this.message, {this.code, this.stackTrace});

  @override
  String toString() => 'Failure(message: $message, code: $code)';
}

/// 轉換 Exception -> Failure
Failure mapExceptionToFailure(Exception e, [StackTrace? st]) {
  if (e is AppException) {
    return Failure(e.message, code: e.code, stackTrace: st);
  }
  return Failure(e.toString(), stackTrace: st);
}
