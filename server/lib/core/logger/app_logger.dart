import 'dart:developer';
import 'logger_config.dart';
import 'logger_printer.dart';

class AppLogger {
  static void debug(String message, {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.debug, message, error: error, stackTrace: stackTrace);
  }

  static void info(String message, {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.info, message, error: error, stackTrace: stackTrace);
  }

  static void warn(String message, {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.warn, message, error: error, stackTrace: stackTrace);
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message, error: error, stackTrace: stackTrace);
  }

  static void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    // 比對目前 log level，過濾不重要訊息
    if (level.index < LoggerConfig.level.index) return;

    final formatted = LoggerPrinter.format(level, message);
    print(formatted);

    if (error != null) {
      print('  ↳ Error: $error');
    }
    if (stackTrace != null) {
      print('  ↳ Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}');
    }

    // 在 debug 模式可使用 dart:developer log
    if (level == LogLevel.error) {
      log(message, error: error, stackTrace: stackTrace);
    }
  }
}
