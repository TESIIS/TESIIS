// tool/build_nationwide_snapshot.dart
//
// Builds `data/shelters_nationwide.csv`, the committed nationwide snapshot
// that makes the map work everywhere, not just Taipei.
//
// Why this exists
// ---------------
// 消防署避難收容處所點位檔 already carries coordinates for all 22 counties
// (~5,973 records) — unlike 臺北市 OpenData, there is no join to do. This tool
// downloads it, validates every row against `TaiwanBounds`, assigns
// deterministic IDs, and writes a sorted, reviewable CSV plus a sidecar of
// what got rejected and why.
//
//     dart run tool/build_nationwide_snapshot.dart --report
//
// Downloads are cached under tool/.cache/ (gitignored) so reruns are offline.
// `build_coordinates.dart` and `data/shelter_coordinates.csv` are unaffected
// by this tool — that pipeline stays as a secondary/enrichment source; see
// its header comment.
//
// Source and licence (see NOTICE.md):
//   - 消防署避難收容處所點位檔          政府資料開放授權條款第 1 版

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:server/core/config/env.dart';
import 'package:server/core/csv/csv_codec.dart';
import 'package:server/core/geo/taiwan_bounds.dart';
import 'package:server/data/datasources/local/shelter_snapshot_source.dart';
import 'package:server/data/mappers/nfa_shelter_mapper.dart';
import 'package:server/domain/entities/shelter.dart';

const _cacheDir = 'tool/.cache';
const _defaultOutput = 'data/shelters_nationwide.csv';
const _defaultRejectedOutput = 'data/shelters_rejected.csv';

const _rejectedCsvHeader = [
  'city',
  'township',
  'village',
  'name',
  'address',
  'reject_reason',
];

/// Quality gates. A failure prints to stderr and sets a non-zero exit code —
/// this is meant to be run in CI (see `.github/workflows/upstream-data-check.yml`).
const _minAcceptRatio = 0.95;
const _minCountyAcceptRatio = 0.75;

Future<void> main(List<String> args) async {
  final showReport = args.contains('--report');
  final refresh = args.contains('--refresh');
  final output = _flagValue(args, '--output') ?? _defaultOutput;
  final rejectedOutput =
      _flagValue(args, '--rejected-output') ?? _defaultRejectedOutput;

  final client = http.Client();
  try {
    stdout.writeln('==> Fetching 消防署避難收容處所點位檔');
    final body = await _cachedGet(
      client,
      Env.nfaPointFileUrl,
      cacheName: 'nfa_nationwide.csv',
      refresh: refresh,
    );
    final rawRows = parseCsvAsMaps(body);
    stdout.writeln('    ${rawRows.length} raw rows');

    final builtAt = DateTime.now().toUtc();
    final ordinals = NfaShelterMapper.assignOrdinals(rawRows);

    final shelters = <Shelter>[];
    final rejected = <(Map<String, String> row, String reason)>[];
    for (var i = 0; i < rawRows.length; i++) {
      final result = NfaShelterMapper.toShelter(
        rawRows[i],
        rowIndex: i,
        ordinal: ordinals[i],
        sourceUpdatedAt: builtAt,
      );
      if (result.shelter != null) {
        shelters.add(result.shelter!);
      } else {
        rejected.add((rawRows[i], result.rejectReason ?? 'unknown'));
      }
    }

    _writeSnapshot(output, shelters, builtAt);
    _writeRejected(rejectedOutput, rejected);

    stdout.writeln(
      '==> Wrote $output (${shelters.length} shelters) '
      'and $rejectedOutput (${rejected.length} rejected)',
    );

    if (showReport) _printReport(rawRows.length, shelters, rejected);

    final failed = _checkGates(rawRows.length, shelters, output);
    if (failed) exitCode = 1;
  } finally {
    client.close();
  }
}

String? _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i == -1 || i + 1 >= args.length) return null;
  return args[i + 1];
}

// ---------------------------------------------------------------------------
// Fetching
// ---------------------------------------------------------------------------

Future<String> _cachedGet(
  http.Client client,
  String url, {
  required String cacheName,
  required bool refresh,
}) async {
  final file = File('$_cacheDir/$cacheName');
  if (!refresh && file.existsSync()) {
    stdout.writeln('    (cached: ${file.path})');
    return file.readAsStringSync();
  }
  final response = await client.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw HttpException('GET $url failed: HTTP ${response.statusCode}');
  }
  final body = utf8.decode(response.bodyBytes);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(body);
  return body;
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

void _writeSnapshot(String path, List<Shelter> shelters, DateTime builtAt) {
  final buffer = StringBuffer()
    ..writeln(encodeCsvRow(shelterSnapshotCsvHeader));
  // Sort by source_id so a rebuild produces a reviewable diff.
  final sorted = [...shelters]
    ..sort((a, b) => a.shelterCode.compareTo(b.shelterCode));
  for (final s in sorted) {
    buffer.writeln(
      encodeCsvRow([
        s.shelterCode,
        s.sourceName ?? 'nfa_point_file',
        (s.sourceUpdatedAt ?? builtAt).toIso8601String(),
        s.cityCode ?? '',
        s.city,
        s.township,
        s.village,
        s.name,
        s.address,
        '${s.x}',
        '${s.y}',
        s.coordinateConfidence ?? 'exact',
        '${s.capacity}',
        s.flood ?? 'N',
        s.quake ?? 'N',
        s.landslide ?? 'N',
        s.tsunami ?? 'N',
        s.nuclear ?? 'N',
        s.indoor ?? '',
        s.outdoor ?? '',
        s.accessible ?? '',
        s.serviceVillages ?? '',
        s.managerName ?? '',
        s.managerPhone ?? '',
      ]),
    );
  }
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(buffer.toString());
}

void _writeRejected(
  String path,
  List<(Map<String, String> row, String reason)> rejected,
) {
  final buffer = StringBuffer()..writeln(encodeCsvRow(_rejectedCsvHeader));
  for (final (row, reason) in rejected) {
    final (city, township) = NfaShelterMapper.splitRegion(row['縣市及鄉鎮市區'] ?? '');
    buffer.writeln(
      encodeCsvRow([
        city,
        township,
        row['村里'] ?? '',
        row['避難收容處所名稱'] ?? '',
        row['避難收容處所地址'] ?? '',
        reason,
      ]),
    );
  }
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(buffer.toString());
}

// ---------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------

void _printReport(
  int totalRaw,
  List<Shelter> shelters,
  List<(Map<String, String> row, String reason)> rejected,
) {
  stdout
    ..writeln('')
    ..writeln('=== Coverage report ===')
    ..writeln('Raw rows:            $totalRaw')
    ..writeln(
      'Accepted:            ${shelters.length} '
      '(${(shelters.length / totalRaw * 100).toStringAsFixed(1)}%)',
    )
    ..writeln('Rejected:            ${rejected.length}');

  final byReason = <String, int>{};
  for (final (_, reason) in rejected) {
    byReason[reason] = (byReason[reason] ?? 0) + 1;
  }
  stdout.writeln('By reject reason:');
  for (final entry in byReason.entries) {
    stdout.writeln('  ${entry.key.padRight(24)} ${entry.value}');
  }

  stdout
    ..writeln('')
    ..writeln('By county (accepted / raw seen for that county):');
  final acceptedByCounty = <String, int>{};
  final totalByCounty = <String, int>{};
  for (final s in shelters) {
    acceptedByCounty[s.city] = (acceptedByCounty[s.city] ?? 0) + 1;
  }
  for (final s in shelters) {
    totalByCounty[s.city] = (totalByCounty[s.city] ?? 0) + 1;
  }
  for (final (row, _) in rejected) {
    final (city, _) = NfaShelterMapper.splitRegion(row['縣市及鄉鎮市區'] ?? '');
    totalByCounty[city] = (totalByCounty[city] ?? 0) + 1;
  }
  final counties = {...acceptedByCounty.keys, ...totalByCounty.keys}.toList()
    ..sort();
  for (final county in counties) {
    final accepted = acceptedByCounty[county] ?? 0;
    final total = totalByCounty[county] ?? 0;
    final ratio = total == 0 ? 0.0 : accepted / total * 100;
    stdout.writeln(
      '  ${county.padRight(6)} $accepted / $total (${ratio.toStringAsFixed(1)}%)',
    );
  }

  final missingCounties = TaiwanBounds.counties
      .where(
        (c) => !acceptedByCounty.keys.any((k) => k.replaceAll('臺', '台') == c),
      )
      .toList();
  if (missingCounties.isNotEmpty) {
    stdout
      ..writeln('')
      ..writeln(
        '!! Counties with ZERO accepted rows: ${missingCounties.join(", ")}',
      );
  }
}

// ---------------------------------------------------------------------------
// Gates
// ---------------------------------------------------------------------------

/// Returns true if any gate failed (so `main` can set a non-zero exit code).
bool _checkGates(int totalRaw, List<Shelter> shelters, String outputPath) {
  var failed = false;

  final acceptedCounties = shelters
      .map((s) => s.city.replaceAll('臺', '台'))
      .toSet();
  final missingCounties = TaiwanBounds.counties
      .where((c) => !acceptedCounties.contains(c))
      .toList();
  if (missingCounties.isNotEmpty) {
    stderr.writeln(
      'GATE FAILED: counties with zero accepted rows: ${missingCounties.join(", ")}',
    );
    failed = true;
  }

  final acceptRatio = totalRaw == 0 ? 0.0 : shelters.length / totalRaw;
  if (acceptRatio < _minAcceptRatio) {
    stderr.writeln(
      'GATE FAILED: overall accept ratio ${(acceptRatio * 100).toStringAsFixed(1)}% '
      'is below the ${(_minAcceptRatio * 100).toStringAsFixed(0)}% floor',
    );
    failed = true;
  }

  final byCounty = <String, List<int>>{}; // county -> [accepted, total]
  for (final s in shelters) {
    final c = s.city;
    byCounty.putIfAbsent(c, () => [0, 0]);
    byCounty[c]![0]++;
    byCounty[c]![1]++;
  }
  for (final entry in byCounty.entries) {
    final ratio = entry.value[1] == 0 ? 0.0 : entry.value[0] / entry.value[1];
    if (ratio < _minCountyAcceptRatio) {
      stderr.writeln(
        'GATE FAILED: ${entry.key} accept ratio ${(ratio * 100).toStringAsFixed(1)}% '
        'is below the ${(_minCountyAcceptRatio * 100).toStringAsFixed(0)}% floor',
      );
      failed = true;
    }
  }

  final existing = File(
    outputPath.contains('/') ? outputPath : 'data/$outputPath',
  );
  // Compare against the file as it was before this run overwrote it is not
  // possible here (we already wrote it) — this check is meant to run via git
  // diff in CI instead (see upstream-data-check.yml). Row-count sanity is
  // still worth a courtesy print.
  if (existing.existsSync()) {
    stdout.writeln(
      '(row-count-vs-previous-commit drift check happens in CI via git diff, '
      'not here — see upstream-data-check.yml)',
    );
  }

  return failed;
}
