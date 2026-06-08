import 'dart:io';

enum LogLevel { debug, info, warn, error, none }

class LoggerConfig {
  static final LogLevel level = _resolveLevel();
  static final bool useColor = stdout.supportsAnsiEscapes;
  static final bool showTimestamp = true;

  static LogLevel _resolveLevel() {
    final env = Platform.environment['LOG_LEVEL']?.toLowerCase();
    switch (env) {
      case 'debug':
        return LogLevel.debug;
      case 'info':
        return LogLevel.info;
      case 'warn':
        return LogLevel.warn;
      case 'error':
        return LogLevel.error;
      default:
        return LogLevel.info;
    }
  }
}
