import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:server/core/config/env.dart';
import 'package:server/core/di/injection.dart' as di;
import 'package:server/presentation/controllers/shelter_controller.dart';

/// Maps the LOG_LEVEL config value onto a `package:logging` level.
Level _logLevelFrom(String name) {
  switch (name) {
    case 'debug':
      return Level.ALL;
    case 'warn':
      return Level.WARNING;
    case 'error':
      return Level.SEVERE;
    case 'info':
    default:
      return Level.INFO;
  }
}

Future<void> main(List<String> args) async {
  Env.load();
  Logger.root.level = _logLevelFrom(Env.logLevel);

  final logFile = File('logs/server.log');
  await logFile.parent.create(recursive: true);
  final logSink = logFile.openWrite(mode: FileMode.append);

  Logger.root.onRecord.listen((record) {
    logSink.writeln(
      '${record.level.name}: ${record.time}: '
      '${record.loggerName}: ${record.message}',
    );
    if (record.error != null) logSink.writeln('  error: ${record.error}');
    if (record.stackTrace != null) logSink.writeln('  ${record.stackTrace}');
  });

  final logger = Logger('Server');
  logger.info('Starting server...');

  di.setupDependencies();
  final shelterController = di.getIt<ShelterController>();

  final router = Router()..mount('/api/', shelterController.router.call);

  // Must be registered before serving, otherwise unmatched requests fall
  // through to shelf's default handler instead of this one.
  router.all('/<ignored|.*>', (Request req) {
    return Response.notFound('Route not found: ${req.url.path}');
  });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(router.call);

  // An explicit CLI argument wins; otherwise Env resolves PORT from the
  // process environment, then `.env`, then the default.
  final port = (args.isNotEmpty ? int.tryParse(args[0]) : null) ?? Env.port;

  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    '✅ Server running on http://${server.address.host}:${server.port}',
  );

  Future<void> shutdown(ProcessSignal signal) async {
    logger.info('Received signal $signal, shutting down...');
    await server.close();
    await logSink.flush();
    await logSink.close();
    exit(0);
  }

  // SIGTERM matters as much as SIGINT: it is what container runtimes and
  // process supervisors send, and ignoring it means being killed mid-write.
  ProcessSignal.sigint.watch().listen(shutdown);
  ProcessSignal.sigterm.watch().listen(shutdown);
}
