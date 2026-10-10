// Read-only live integration probe. Unit tests use synthetic CAP fixtures.
import 'dart:convert';
import 'dart:io';
import 'package:server/core/config/env.dart';
import 'package:server/data/datasources/external/ncdr_alert_source.dart';
import 'package:server/domain/services/alert_service.dart';

Future<void> main() async {
  Env.load();
  final service = AlertService(
    source: NcdrAlertSource(feedUri: Uri.parse(Env.alertFeedUrl)),
  );
  final watch = Stopwatch()..start();
  try {
    final result = await service.query();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'elapsedMs': watch.elapsedMilliseconds,
        for (final key in [
          'freshness',
          'fetchedAt',
          'sourceUpdatedAt',
          'feedEntries',
          'failedDocuments',
          'sourceTruncated',
          'omittedExpired',
          'total',
          'unknownRegionCount',
        ])
          key: result[key],
        'sample': [
          for (final row in (result['data'] as List).take(5))
            {
              'headline': row['headline'],
              'state': row['state'],
              'regions': row['regions'],
              'expiresAt': row['expiresAt'],
            },
        ],
      }),
    );
  } catch (e) {
    stderr.writeln('Alert source check failed: $e');
    exitCode = 1;
  }
}
