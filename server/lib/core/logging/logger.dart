import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';

class LogManager {
  final IOSink sink;
  final StreamSubscription<LogRecord> subscription;
  LogManager(this.sink, this.subscription);

  Future<void> close() async {
    await subscription.cancel();
    await sink.flush();
    await sink.close();
  }
}

/// 初始化檔案日誌與 Logger.root，回傳可在關閉時釋放的 LogManager
Future<LogManager> initFileLogging({
  String path = 'logs/server.log',
  Level level = Level.ALL,
}) async {
  Logger.root.level = level;
  final file = File(path);
  await file.parent.create(recursive: true);
  final sink = file.openWrite(mode: FileMode.append);
  final sub = Logger.root.onRecord.listen((record) {
    final msg = '${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}';
    sink.writeln(msg);
  });
  return LogManager(sink, sub);
}
