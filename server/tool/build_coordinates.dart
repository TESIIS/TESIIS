// tool/build_coordinates.dart
//
// Builds `data/shelter_coordinates.csv`, the committed coordinate table that
// makes the map work.
//
// Why this exists
// ---------------
// 臺北市 OpenData dataset 4c92dbd4 (可供避難收容處所一覽表, 401 records) has no
// coordinate columns — verified against every record. Previously the server
// read coordinates from a SQLite file that was gitignored and shipped with no
// way to regenerate it, so a fresh clone always rendered an empty map.
//
// This tool rebuilds that table from public sources, deterministically, with a
// coverage report. Run it when upstream data changes:
//
//     dart run tool/build_coordinates.dart --report
//
// Downloads are cached under tool/.cache/ (gitignored) so reruns are offline.
//
// Sources and licences (see NOTICE.md):
//   - 消防署避難收容處所點位檔          政府資料開放授權條款第 1 版
//   - 北市警政APP_防空避難設備位置      政府資料開放授權條款第 1 版
//
// --overpass additionally queries OpenStreetMap for whatever is left over. It
// is opt-in and the committed table is NOT built with it: OSM is ODbL, which is
// share-alike, so one run would put the whole CSV under a copyleft licence. The
// committed table trades 2.5 points of coverage (92.3% instead of 94.8%) for a
// licence that is purely 政府資料開放授權條款第 1 版. Do not flip this default
// without updating NOTICE.md and README.md.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:server/core/csv/csv_codec.dart';
import 'package:server/core/geo/taipei_bounds.dart';
import 'package:server/domain/entities/shelter_fields.dart';

const _shelterDataset = '4c92dbd4-d259-495a-8390-52628119a4dd';
const _airRaidDataset = '39ca53a1-c861-40bc-b329-fc9b28c10e01';
const _nfaPointFile =
    'https://opdadm.moi.gov.tw/api/v1/no-auth/resource/api/dataset/'
    'ED6CF735-6C03-4573-A882-72C1BEC799CB/resource/'
    '54550E2F-4567-4C8F-BD2E-E54E9D0386B8/download';
const _overpassEndpoint = 'https://overpass-api.de/api/interpreter';

/// Overpass rejects the Dart HTTP client's default User-Agent outright
/// (`Dart/3.x (dart:io)` -> HTTP 406 on every request, verified). Its usage
/// policy asks for an identifying agent anyway, so send one.
const _userAgent =
    'taipei-shelter-map/1.0 (2025 Taipei Codefest team 30; coordinate table build)';

const _cacheDir = 'tool/.cache';
const _defaultOutput = 'data/shelter_coordinates.csv';
const _defaultReviewOutput = 'data/coordinates_needs_review.csv';

const _csvHeader = [
  'shelter_code',
  'name',
  'address',
  'lng',
  'lat',
  'source',
  'confidence',
  'updated_at',
];

Future<void> main(List<String> args) async {
  final useOverpass = args.contains('--overpass');
  final showReport = args.contains('--report') || useOverpass;
  final refresh = args.contains('--refresh');
  final output = _flagValue(args, '--output') ?? _defaultOutput;

  final client = http.Client();
  try {
    stdout.writeln('==> Fetching 避難收容處所 (dataset $_shelterDataset)');
    final shelters = await _fetchTaipeiDataset(
      client,
      _shelterDataset,
      cacheName: 'shelters.json',
      refresh: refresh,
    );
    stdout.writeln('    ${shelters.length} records');

    stdout.writeln('==> Fetching 防空避難設備位置 (dataset $_airRaidDataset)');
    final airRaid = await _fetchTaipeiDataset(
      client,
      _airRaidDataset,
      cacheName: 'air_raid.json',
      refresh: refresh,
    );
    stdout.writeln('    ${airRaid.length} records');

    stdout.writeln('==> Fetching 消防署避難收容處所點位檔');
    final nfaRows = await _fetchNfaPointFile(client, refresh: refresh);
    stdout.writeln('    ${nfaRows.length} records nationwide');

    final resolver = _Resolver()
      ..addNfaPointFile(nfaRows)
      ..addAirRaidShelters(airRaid);

    stdout.writeln('==> Joining');
    final results = <_Row>[];
    for (final shelter in shelters) {
      results.add(resolver.resolve(shelter));
    }

    if (useOverpass) {
      final unresolved = results.where((r) => !r.hasCoordinate).toList();
      stdout.writeln(
        '==> Querying Overpass for ${unresolved.length} unresolved facilities',
      );
      await _resolveViaOverpass(client, unresolved);
    }

    stdout.writeln('==> Filling remaining gaps from nearest street number');
    final interpolated = resolver.fillFromNearestOnStreet(results);
    stdout.writeln('    filled $interpolated');

    _writeCsv(output, results);
    stdout.writeln('==> Wrote $output');

    final needsReview = results
        .where((r) => r.hasCoordinate && r.confidence != 'exact')
        .toList();
    if (needsReview.isNotEmpty) {
      _writeCsv(_defaultReviewOutput, needsReview);
      stdout.writeln(
        '==> Wrote $_defaultReviewOutput '
        '(${needsReview.length} rows needing human confirmation)',
      );
    }

    if (showReport) _printReport(results, resolver);
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
  // Government exports are UTF-8 but do not always say so in Content-Type,
  // which would make the http package fall back to latin-1 and mangle 中文.
  final body = utf8.decode(response.bodyBytes);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(body);
  return body;
}

/// data.taipei caps a response at 1000 rows, so page until short.
Future<List<Map<String, dynamic>>> _fetchTaipeiDataset(
  http.Client client,
  String datasetId, {
  required String cacheName,
  required bool refresh,
}) async {
  final cache = File('$_cacheDir/$cacheName');
  if (!refresh && cache.existsSync()) {
    stdout.writeln('    (cached: ${cache.path})');
    return (jsonDecode(cache.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
  }

  const pageSize = 1000;
  final all = <Map<String, dynamic>>[];
  var offset = 0;
  while (true) {
    final uri = Uri.parse('https://data.taipei/api/v1/dataset/$datasetId')
        .replace(
          queryParameters: {
            'scope': 'resourceAquire',
            'limit': '$pageSize',
            'offset': '$offset',
          },
        );
    final response = await client.get(uri);
    if (response.statusCode != 200) {
      throw HttpException('GET $uri failed: HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final batch = ((decoded['result']?['results']) as List? ?? const [])
        .cast<Map<String, dynamic>>();
    all.addAll(batch);
    if (batch.length < pageSize) break;
    offset += pageSize;
  }

  cache.parent.createSync(recursive: true);
  cache.writeAsStringSync(jsonEncode(all));
  return all;
}

Future<List<Map<String, String>>> _fetchNfaPointFile(
  http.Client client, {
  required bool refresh,
}) async {
  final body = await _cachedGet(
    client,
    _nfaPointFile,
    cacheName: 'nfa_point_file.csv',
    refresh: refresh,
  );
  return parseCsvAsMaps(body);
}

// ---------------------------------------------------------------------------
// Joining
// ---------------------------------------------------------------------------

class _Candidate {
  _Candidate(this.lng, this.lat, this.source);

  final double lng;
  final double lat;
  final String source;
}

/// A normalised address split into "which street" and "which number".
typedef _StreetAddress = ({String street, int number});

/// Splits a normalised address such as `中正區汀州路2段265號`.
///
/// The street part keeps the 段/巷/弄 qualifiers, so 汀州路1段 and 汀州路3段 —
/// which can be a kilometre apart — never share a bucket.
_StreetAddress? _parseStreet(String normalized) {
  // `(\d+)(?:-\d+)?號` rather than `(\d+)號` so that 198-20號 yields 198,
  // not 20.
  final match = RegExp(r'^(.*?)(\d+)(?:-\d+)?號').firstMatch(normalized);
  if (match == null) return null;
  final street = match[1]!;
  final number = int.tryParse(match[2]!);
  if (street.isEmpty || number == null) return null;
  return (street: street, number: number);
}

/// Drops the 巷/弄 tail, so 樂群二路266巷 falls back to 樂群二路.
String _baseRoad(String street) {
  final match = RegExp(r'^(.*?[路街道大道](?:\d+段)?)').firstMatch(street);
  return match?[1] ?? street;
}

class _Resolver {
  final Map<String, _Candidate> _byAddress = {};
  final Map<String, _Candidate> _byName = {};

  /// street -> house numbers seen on it, for the nearest-number fallback.
  final Map<String, List<(int number, _Candidate point)>> _byStreet = {};
  final Map<String, List<(int number, _Candidate point)>> _byRoad = {};

  /// How far apart two house numbers may be before the interpolation is
  /// meaningless. Taipei numbering runs roughly 8-15 buildings per 100 m, so
  /// 40 bounds the error at a few hundred metres for ordinary street
  /// addresses. Measured against known-good points the spread is 40-761 m,
  /// median ~200 m — the tail is parks and underground malls, where the
  /// address is one corner of a site that spans several hundred metres.
  /// Anything relying on this must say "數百公尺", not "數十公尺".
  static const _maxHouseNumberGap = 40;

  void _indexStreet(String normalizedAddress, _Candidate candidate) {
    final parsed = _parseStreet(normalizedAddress);
    if (parsed == null) return;
    _byStreet.putIfAbsent(parsed.street, () => []).add((
      parsed.number,
      candidate,
    ));
    _byRoad.putIfAbsent(_baseRoad(parsed.street), () => []).add((
      parsed.number,
      candidate,
    ));
  }

  /// Nearest known house number on the same street.
  _Candidate? _nearestOnStreet(String normalizedAddress) {
    final parsed = _parseStreet(normalizedAddress);
    if (parsed == null) return null;

    for (final index in [_byStreet, _byRoad]) {
      final key = index == _byStreet ? parsed.street : _baseRoad(parsed.street);
      final entries = index[key];
      if (entries == null || entries.isEmpty) continue;

      var best = entries.first;
      var bestGap = (best.$1 - parsed.number).abs();
      for (final entry in entries.skip(1)) {
        final gap = (entry.$1 - parsed.number).abs();
        if (gap < bestGap) {
          best = entry;
          bestGap = gap;
        }
      }
      if (bestGap <= _maxHouseNumberGap) return best.$2;
    }
    return null;
  }

  int nfaAccepted = 0;
  int nfaRejectedOutOfBounds = 0;
  final List<String> rejectedSamples = [];

  int airRaidAccepted = 0;
  int airRaidRejectedOutOfBounds = 0;

  void _index(String key, _Candidate candidate, Map<String, _Candidate> into) {
    if (key.isEmpty) return;
    // First source wins: sources are added in descending order of trust.
    into.putIfAbsent(key, () => candidate);
    if (identical(into, _byAddress)) _indexStreet(key, candidate);
  }

  /// 消防署避難收容處所點位檔 — same facility category as our dataset, so it is
  /// the most trustworthy source. But it ships bad rows: of 272 臺北市 records,
  /// two are geocoded to 屏東. Everything goes through [TaipeiBounds].
  void addNfaPointFile(List<Map<String, String>> rows) {
    for (final row in rows) {
      final region = (row['縣市及鄉鎮市區'] ?? '').replaceAll('臺', '台');
      if (!region.startsWith('台北市')) continue;

      final lng = double.tryParse((row['經度'] ?? '').trim());
      final lat = double.tryParse((row['緯度'] ?? '').trim());
      final name = (row['避難收容處所名稱'] ?? '').trim();
      if (lng == null || lat == null) continue;

      if (!TaipeiBounds.contains(lng, lat)) {
        nfaRejectedOutOfBounds++;
        if (rejectedSamples.length < 10) {
          rejectedSamples.add('$name (${row['避難收容處所地址']}) -> $lng/$lat');
        }
        continue;
      }
      nfaAccepted++;

      final district = region.replaceFirst('台北市', '');
      final candidate = _Candidate(lng, lat, 'nfa_point_file');
      _index(
        ShelterAddress.normalize(row['避難收容處所地址'], township: district),
        candidate,
        _byAddress,
      );
      _index(ShelterText.normalizeName(name), candidate, _byName);
    }
  }

  /// 北市警政APP_防空避難設備位置 — a different facility category (air-raid
  /// shelters), but many occupy the same buildings, so its 座標x/座標y are a
  /// good secondary source for a matching street address.
  void addAirRaidShelters(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final lng = double.tryParse('${row['座標x'] ?? ''}'.trim());
      final lat = double.tryParse('${row['座標y'] ?? ''}'.trim());
      if (lng == null || lat == null) continue;
      if (!TaipeiBounds.contains(lng, lat)) {
        airRaidRejectedOutOfBounds++;
        continue;
      }
      airRaidAccepted++;
      _index(
        ShelterAddress.normalize(
          '${row['地址'] ?? ''}',
          township: '${row['行政區'] ?? ''}',
        ),
        _Candidate(lng, lat, 'taipei_airraid'),
        _byAddress,
      );
    }
  }

  _Row resolve(Map<String, dynamic> shelter) {
    final code = '${shelter['收容所編號'] ?? ''}'.trim();
    final name = '${shelter['名稱'] ?? ''}'.trim();
    final address = '${shelter['門牌地址'] ?? ''}'.trim();
    final township = '${shelter['鄉鎮'] ?? ''}'.trim();

    final byAddress =
        _byAddress[ShelterAddress.normalize(address, township: township)];
    if (byAddress != null) {
      return _Row(
        shelterCode: code,
        name: name,
        address: address,
        township: township,
        lng: byAddress.lng,
        lat: byAddress.lat,
        source: byAddress.source,
        confidence: 'exact',
      );
    }

    // Name matching is weaker: the 消防署 file abbreviates
    // ("北市大附小" for 臺北市立大學附設實驗國民小學), so this only fires on
    // facilities whose names happen to agree verbatim.
    final byName = _byName[ShelterText.normalizeName(name)];
    if (byName != null) {
      return _Row(
        shelterCode: code,
        name: name,
        address: address,
        township: township,
        lng: byName.lng,
        lat: byName.lat,
        source: byName.source,
        confidence: 'name_match',
      );
    }

    return _Row(
      shelterCode: code,
      name: name,
      address: address,
      township: township,
    );
  }

  /// Last-resort pass: place a still-unresolved facility at the nearest known
  /// house number on the same street.
  ///
  /// Off by a building or two, which for "where do I shelter" is far more
  /// useful than no marker at all — but it is labelled `approx` so the UI can
  /// say so. Runs after Overpass, because an actual named place in OSM beats
  /// an interpolated street position.
  int fillFromNearestOnStreet(List<_Row> rows) {
    var filled = 0;
    for (final row in rows) {
      if (row.hasCoordinate) continue;
      final nearby = _nearestOnStreet(
        ShelterAddress.normalize(row.address, township: row.township),
      );
      if (nearby == null) continue;
      row
        ..lng = nearby.lng
        ..lat = nearby.lat
        ..source = nearby.source
        ..confidence = 'approx';
      filled++;
    }
    return filled;
  }
}

class _Row {
  _Row({
    required this.shelterCode,
    required this.name,
    required this.address,
    required this.township,
    this.lng,
    this.lat,
    this.source = 'none',
    this.confidence = 'none',
  });

  final String shelterCode;
  final String name;
  final String address;
  final String township;
  double? lng;
  double? lat;
  String source;
  String confidence;

  bool get hasCoordinate => lng != null && lat != null;

  /// Upstream 名稱 and 門牌地址 contain embedded newlines ("下塔悠\n(公7)公園").
  /// Written verbatim they would produce quoted multi-line CSV rows, which are
  /// valid but make the committed table painful to review in a diff. Neither
  /// field is authoritative here — the runtime name comes from upstream, and
  /// the address is only ever consumed through ShelterAddress.normalize, which
  /// strips whitespace anyway.
  static String _flatten(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  List<String> toCsvFields(String today) => [
    shelterCode,
    _flatten(name),
    _flatten(address),
    lng == null ? '' : lng!.toStringAsFixed(6),
    lat == null ? '' : lat!.toStringAsFixed(6),
    source,
    confidence,
    today,
  ];
}

// ---------------------------------------------------------------------------
// Overpass fallback (opt-in, ODbL)
// ---------------------------------------------------------------------------

/// Name variants to try against OSM, most specific first.
///
/// The upstream 名稱 column is an official register entry, not what the place
/// is called on a map: it carries the 臺北市立 / 臺北市市場處 administrative
/// prefix, embedded newlines ("下塔悠\n(公7)公園") and parenthesised notes.
/// OSM tags the everyday name, so an exact match on the raw string mostly
/// fails.
List<String> _overpassNameVariants(String rawName) {
  final flattened = rawName.replaceAll(RegExp(r'\s+'), ' ').trim();
  final variants = <String>[flattened];

  final withoutNote = flattened
      .replaceAll(RegExp(r'[（(][^）)]*[）)]'), '')
      .trim();
  if (withoutNote.isNotEmpty) variants.add(withoutNote);

  // Longest prefix first, and stop after the first hit: stripping '臺北市' off
  // 臺北市立圖書館城中分館 would leave the nonsense '立圖書館城中分館'.
  const prefixes = ['臺北市市場處臺北市', '臺北市市場處', '臺北市立', '臺北市', '台北市'];
  for (final base in {flattened, withoutNote}) {
    for (final prefix in prefixes) {
      if (base.startsWith(prefix) && base.length > prefix.length) {
        variants.add(base.substring(prefix.length).trim());
        break;
      }
    }
  }

  return variants
      .map((v) => v.trim())
      .where((v) => v.length >= 2)
      .toSet()
      .toList(growable: false);
}

/// Escapes a literal for use inside an Overpass regex.
///
/// Facility names really do contain regex metacharacters — "金泰(公8)公園".
String _escapeRegex(String value) =>
    value.replaceAllMapped(RegExp(r'[\\^$.|?*+()\[\]{}]'), (m) => '\\${m[0]}');

/// How many names to fold into a single Overpass request.
///
/// One name per request is what the obvious implementation does, and it gets
/// you 429s and 504s: ~300 requests for 110 facilities. Batching with a regex
/// alternation turns that into a handful of requests.
const _overpassBatchSize = 25;

/// Looks up remaining facilities by name within the 臺北市 bounding box.
///
/// A bbox filter is used rather than `area[...]["admin_level"="4"]`, which
/// forces Overpass to resolve the city polygon on every call and reliably
/// times out (504).
///
/// Results are written with confidence `approx` and also dumped to
/// data/coordinates_needs_review.csv, because name matching happily returns
/// the wrong 中山公園 — a human has to confirm these before they are trusted.
Future<void> _resolveViaOverpass(http.Client client, List<_Row> rows) async {
  const bbox =
      '${TaipeiBounds.minLat},${TaipeiBounds.minLng},'
      '${TaipeiBounds.maxLat},${TaipeiBounds.maxLng}';

  // Every name variant we are willing to accept, pointing back at its row.
  // Insertion order matters: the first variant of a row is the most specific.
  final wanted = <String, _Row>{};
  for (final row in rows) {
    for (final variant in _overpassNameVariants(row.name)) {
      wanted.putIfAbsent(variant, () => row);
    }
  }

  final names = wanted.keys.toList(growable: false);
  var matched = 0;

  for (var start = 0; start < names.length; start += _overpassBatchSize) {
    final batch = names.skip(start).take(_overpassBatchSize).toList();
    final pattern = batch.map(_escapeRegex).join('|');
    final query =
        '''
[out:json][timeout:90];
(
  node($bbox)["name"~"^($pattern)\$"];
  way($bbox)["name"~"^($pattern)\$"];
  relation($bbox)["name"~"^($pattern)\$"];
);
out center;
''';

    try {
      final response = await client.post(
        Uri.parse(_overpassEndpoint),
        headers: {'user-agent': _userAgent},
        body: {'data': query},
      );
      if (response.statusCode != 200) {
        stderr.writeln(
          '    Overpass HTTP ${response.statusCode} for batch '
          '${start ~/ _overpassBatchSize + 1}',
        );
        continue;
      }

      final elements =
          (jsonDecode(utf8.decode(response.bodyBytes))['elements'] as List?) ??
          const [];
      for (final raw in elements) {
        final element = raw as Map<String, dynamic>;
        final name =
            (element['tags'] as Map<String, dynamic>?)?['name'] as String?;
        final row = name == null ? null : wanted[name];
        // Already resolved by an earlier, more specific variant.
        if (row == null || row.hasCoordinate) continue;

        final center = element['center'] as Map<String, dynamic>?;
        final lat = (center?['lat'] ?? element['lat']) as num?;
        final lng = (center?['lon'] ?? element['lon']) as num?;
        if (lat == null || lng == null) continue;
        if (!TaipeiBounds.contains(lng.toDouble(), lat.toDouble())) continue;

        row
          ..lng = lng.toDouble()
          ..lat = lat.toDouble()
          ..source = 'osm_overpass'
          ..confidence = 'approx';
        matched++;
        stdout.writeln('    matched "$name" -> $lng/$lat  (${row.name})');
      }
    } catch (e) {
      stderr.writeln('    Overpass batch failed: $e');
    }

    // Overpass is a shared free service run on donated hardware.
    await Future<void>.delayed(const Duration(seconds: 3));
  }

  stdout.writeln('    Overpass resolved $matched of ${rows.length}');
}

// ---------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------

void _writeCsv(String path, List<_Row> rows) {
  final today = DateTime.now().toIso8601String().substring(0, 10);
  final buffer = StringBuffer()..writeln(encodeCsvRow(_csvHeader));
  // Sort by shelter code so a rebuild produces a reviewable diff rather than a
  // reshuffled file.
  final sorted = [...rows]
    ..sort((a, b) => a.shelterCode.compareTo(b.shelterCode));
  for (final row in sorted) {
    buffer.writeln(encodeCsvRow(row.toCsvFields(today)));
  }
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(buffer.toString());
}

void _printReport(List<_Row> rows, _Resolver resolver) {
  final total = rows.length;
  final resolved = rows.where((r) => r.hasCoordinate).toList();
  final bySource = <String, int>{};
  final byConfidence = <String, int>{};
  for (final row in resolved) {
    bySource[row.source] = (bySource[row.source] ?? 0) + 1;
    byConfidence[row.confidence] = (byConfidence[row.confidence] ?? 0) + 1;
  }

  stdout
    ..writeln('')
    ..writeln('=== Coverage report ===')
    ..writeln('Shelters:            $total')
    ..writeln(
      'With coordinates:    ${resolved.length} '
      '(${(resolved.length / total * 100).toStringAsFixed(1)}%)',
    )
    ..writeln('Missing:             ${total - resolved.length}')
    ..writeln('')
    ..writeln('By source:');
  for (final entry in bySource.entries) {
    stdout.writeln('  ${entry.key.padRight(20)} ${entry.value}');
  }
  stdout.writeln('By confidence:');
  for (final entry in byConfidence.entries) {
    stdout.writeln('  ${entry.key.padRight(20)} ${entry.value}');
  }

  stdout
    ..writeln('')
    ..writeln('Source quality gate (TaipeiBounds):')
    ..writeln(
      '  nfa_point_file       accepted ${resolver.nfaAccepted}, '
      'rejected ${resolver.nfaRejectedOutOfBounds}',
    )
    ..writeln(
      '  taipei_airraid       accepted ${resolver.airRaidAccepted}, '
      'rejected ${resolver.airRaidRejectedOutOfBounds}',
    );
  if (resolver.rejectedSamples.isNotEmpty) {
    stdout.writeln('  rejected rows (out of bounds):');
    for (final sample in resolver.rejectedSamples) {
      stdout.writeln('    $sample');
    }
  }

  final missing = rows.where((r) => !r.hasCoordinate).toList();
  if (missing.isNotEmpty) {
    stdout
      ..writeln('')
      ..writeln('Unresolved (first 20 of ${missing.length}):');
    for (final row in missing.take(20)) {
      stdout.writeln('  ${row.township}${row.address}  |  ${row.name}');
    }
  }
}
