import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:logging/logging.dart';

import 'package:server/core/di/injection.dart' as di;
import 'package:server/presentation/controllers/shelter_controller.dart';
import 'package:server/data/datasources/database/shelter_database.dart';
import 'dart:convert';

Future<void> main(List<String> args) async {
  Logger.root.level = Level.ALL;

  final logFile = File('logs/server.log');
  await logFile.parent.create(recursive: true);
  final logSink = logFile.openWrite(mode: FileMode.append);

  Logger.root.onRecord.listen((record) {
    final logMessage = '${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}';
    logSink.writeln(logMessage);
  });

  final logger = Logger('Server');
  logger.info('Starting server...');
  // DI
  di.setupDependencies();
  final shelterController = di.getIt<ShelterController>();

  final router = Router();

  router.mount('/api/', shelterController.router);

  // Debug endpoints to inspect local geocoding DB (safe to call)
  final _db = di.getIt<ShelterDatabase>();
  // GET /api/debug/geocoding_schema?table=<name>
  // If ?table is omitted, returns columns for the default 'geocoding' table (if exists).
  router.get('/api/debug/geocoding_schema', (Request req) async {
    final table = req.url.queryParameters['table'] ?? 'geocoding';
    try {
      final cols = _db.tableColumns(table);
      return Response.ok(jsonEncode({'success': true, 'table': table, 'columns': cols}), headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  // GET /api/debug/geocoding_sample?table=<name>&limit=5
  router.get('/api/debug/geocoding_sample', (Request req) async {
    final table = req.url.queryParameters['table'] ?? 'geocoding';
    final limitParam = req.url.queryParameters['limit'];
    final limit = int.tryParse(limitParam ?? '') ?? 5;
    try {
      final rows = _db.sampleRows(table, limit: limit);
      return Response.ok(jsonEncode({'success': true, 'table': table, 'rows': rows}), headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  // GET /api/debug/geocoding_tables -> list all user tables and their columns
  router.get('/api/debug/geocoding_tables', (Request req) async {
    try {
      final tables = _db.listTables();
      final map = <String, List<String>>{};
      for (final t in tables) {
        map[t] = _db.tableColumns(t);
      }
      return Response.ok(jsonEncode({'success': true, 'tables': map}), headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  // GET /api/debug/geocoding_index -> index status (size)
  router.get('/api/debug/geocoding_index', (Request req) async {
    try {
      // Build index if not built; buildAddressIndex is idempotent
      _db.buildAddressIndex();
      // There is no public getter; expose via a test lookup count endpoint.
      // We'll sample a known address param if provided.
      final sample = req.url.queryParameters['sample'];
      final sampleHit = sample != null ? (_db.lookupAddress(sample) != null) : null;
      return Response.ok(jsonEncode({'success': true, 'indexReady': true, 'sampleMatched': sampleHit}), headers: {'content-type': 'application/json'});
    } catch (e) {
      return Response.internalServerError(body: jsonEncode({'success': false, 'error': e.toString()}), headers: {'content-type': 'application/json'});
    }
  });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(router);

  // 從環境變數或命令列參數讀取連接埠，預設 8080
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 
               (args.isNotEmpty ? int.tryParse(args[0]) : null) ?? 
               8080;

  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('✅ Server running on http://${server.address.host}:${server.port}');

  // Catch-all 404 route
  router.all('/<ignored|.*>', (Request req) {
    return Response.notFound('Route not found: ${req.url.path}');
  });

  // 處理關閉事件，關閉 logSink
  ProcessSignal.sigint.watch().listen((signal) async {
    logger.info('Received signal $signal, shutting down...');
    await logSink.close();
    await server.close();
    exit(0);
  });
}