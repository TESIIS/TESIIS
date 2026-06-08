import 'logger_config.dart';

class LoggerPrinter {
  static String format(LogLevel level, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final levelTag = _colorize(level, _levelLabel(level));

    final output = StringBuffer();
    if (LoggerConfig.showTimestamp) output.write('[$timestamp] ');
    output.write('$levelTag ');
    output.write(message);

    return output.toString();
  }

  static String _levelLabel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '[DEBUG]';
      case LogLevel.info:
        return '[INFO]';
      case LogLevel.warn:
        return '[WARN]';
      case LogLevel.error:
        return '[ERROR]';
      case LogLevel.none:
        return '';
    }
  }

  static String _colorize(LogLevel level, String text) {
    if (!LoggerConfig.useColor) return text;

    switch (level) {
      case LogLevel.debug:
        return '\x1B[36m$text\x1B[0m'; // cyan
      case LogLevel.info:
        return '\x1B[32m$text\x1B[0m'; // green
      case LogLevel.warn:
        return '\x1B[33m$text\x1B[0m'; // yellow
      case LogLevel.error:
        return '\x1B[31m$text\x1B[0m'; // red
      default:
        return text;
    }
  }
}
