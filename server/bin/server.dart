import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:server/core/config/env.dart';
import 'package:server/core/di/injection.dart' as di;
import 'package:server/data/datasources/local/shelter_snapshot_source.dart';
import 'package:server/domain/repositories/shelter_repository.dart';
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

  Logger.root.onRecord.listen((record) {
    final sink = record.level.value >= Level.WARNING.value ? stderr : stdout;
    sink.writeln(
      '${record.level.name}: ${record.time}: '
      '${record.loggerName}: ${record.message}',
    );
    if (record.error != null) sink.writeln('  error: ${record.error}');
    if (record.stackTrace != null) sink.writeln('  ${record.stackTrace}');
  });

  final logger = Logger('Server');
  logger.info('Starting server...');

  // Check the one precondition that cannot be recovered from before wiring
  // anything up, so a missing snapshot produces an explanation rather than a
  // DI stack trace.
  final ShelterSnapshotSource snapshot;
  try {
    snapshot = di.loadShelterSnapshot();
  } on di.SnapshotUnavailable catch (e) {
    stderr.writeln('\n$e\n');
    exit(1);
  }

  di.setupDependencies(snapshot: snapshot);
  final shelterController = di.getIt<ShelterController>();
  final shelterRepository = di.getIt<ShelterRepository>();

  final router = Router()
    ..get('/healthz', (Request _) {
      return Response.ok(
        jsonEncode({
          'status': 'ok',
          'service': 'taiwan-shelter-api',
          'dataSource': 'nfa_point_file',
          'dataFreshness': shelterRepository.dataFreshness.name,
          'dataUpdatedAt': shelterRepository.dataUpdatedAt?.toIso8601String(),
          'snapshotUpdatedAt': snapshot.snapshotUpdatedAt?.toIso8601String(),
          'countsByCity': snapshot.countsByCity,
          'coordinateCoverage': shelterRepository.coordinateCoverage.toJson(),
        }),
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    })
    ..mount('/api/', shelterController.router.call);

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
    exit(0);
  }

  // SIGTERM matters as much as SIGINT: it is what container runtimes and
  // process supervisors send, and ignoring it means being killed mid-write.
  //
  // Windows has no real SIGTERM — watching for it throws a SignalException
  // that would otherwise crash the whole server on startup. Container
  // deployments (see compose.yaml) run on Linux regardless of the host OS,
  // so skipping it on Windows costs nothing there.
  ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen(shutdown);
  }
}
