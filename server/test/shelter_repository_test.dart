import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server/data/datasources/external/shelter_api.dart';
import 'package:server/data/datasources/local/coordinate_source.dart';
import 'package:server/data/repositories_impl/shelter_repository_impl.dart';
import 'package:test/test.dart';

const _coordinateCsv = '''
shelter_code,name,address,lng,lat,source,confidence,updated_at
SA100-0002,螢橋國中,汀州路三段四號,121.5265,25.0190,nfa_point_file,exact,2026-08-09
SA100-0009,只有地址對得上,中正區公園路29號,121.5153,25.0363,taipei_airraid,exact,2026-08-09
''';

Map<String, dynamic> _upstreamRecord({
  required int id,
  required String code,
  String address = '汀州路三段四號',
}) => {
  '_id': id,
  '_importdate': {'date': '2025-11-28 14:50:10.208313'},
  '收容所編號': code,
  '名稱': '測試避難所',
  '縣市': '臺北市',
  '郵遞區號': '100',
  '鄉鎮': '中正區',
  '村里': '林興里',
  '門牌地址': address,
  '類型': '學校',
  '水災': 'Y',
  '震災': '備用',
  '土石流': 'N',
  '海嘯': 'N',
  '救濟支站': 'Y',
  '無障礙設施': 'Y',
  '室內': 'Y',
  '室外': 'N',
  '服務里別': '板溪里、網溪里',
  '容納人數': '1,581',
  '收容所面積（平方公尺）': '14,495',
  '聯絡人姓名': '王小明',
  '備考': '',
};

/// A stub upstream that counts how many times it was hit.
class _Upstream {
  _Upstream(this.records);

  final List<Map<String, dynamic>> records;
  int requests = 0;
  bool fail = false;

  http.Client get client => MockClient((request) async {
    requests++;
    if (fail) return http.Response('upstream down', 503);
    final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
    return http.Response(
      jsonEncode({
        'result': {'results': offset == 0 ? records : <Map<String, dynamic>>[]},
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

void main() {
  final coordinates = CoordinateSource.fromCsv(_coordinateCsv);

  ShelterRepositoryImpl repositoryFor(
    _Upstream upstream, {
    Duration ttl = const Duration(minutes: 10),
  }) => ShelterRepositoryImpl(
    api: ShelterApi(client: upstream.client),
    coordinates: coordinates,
    cacheTtl: ttl,
  );

  test('joins coordinates in by shelter code', () async {
    final upstream = _Upstream([_upstreamRecord(id: 1, code: 'SA100-0002')]);
    final shelters = await repositoryFor(upstream).getAllShelters();

    final s = shelters.single;
    expect(s.x, 121.5265);
    expect(s.y, 25.0190);
    expect(s.coordinateSource, 'nfa_point_file');
    expect(s.coordinateConfidence, 'exact');
    expect(s.hasCoordinate, isTrue);
  });

  test('falls back to the address when the code is unknown', () async {
    final upstream = _Upstream([
      _upstreamRecord(id: 1, code: 'UNKNOWN', address: '公園路29號'),
    ]);
    final shelters = await repositoryFor(upstream).getAllShelters();
    expect(shelters.single.coordinateSource, 'taipei_airraid');
  });

  test('a shelter with no coordinate is still returned', () async {
    final upstream = _Upstream([
      _upstreamRecord(id: 1, code: 'UNKNOWN', address: '沒有這條路999號'),
    ]);
    final shelters = await repositoryFor(upstream).getAllShelters();
    expect(shelters.single.hasCoordinate, isFalse);
    expect(shelters.single.coordinateSource, isNull);
    expect(shelters.single.name, '測試避難所');
  });

  test('parses the messy numeric columns', () async {
    final upstream = _Upstream([_upstreamRecord(id: 1, code: 'SA100-0002')]);
    final s = (await repositoryFor(upstream).getAllShelters()).single;
    expect(s.capacity, 1581, reason: 'thousands separator');
    expect(s.area, 14495.0);
  });

  test('caches upstream for the TTL', () async {
    // Before this cache every single request re-downloaded the whole dataset.
    final upstream = _Upstream([_upstreamRecord(id: 1, code: 'SA100-0002')]);
    final repository = repositoryFor(upstream);

    await repository.getAllShelters();
    await repository.getAllShelters();
    await repository.getAllShelters();

    // One page fetch plus the terminating empty page.
    expect(upstream.requests, lessThanOrEqualTo(2));
  });

  test('a zero TTL refetches', () async {
    final upstream = _Upstream([_upstreamRecord(id: 1, code: 'SA100-0002')]);
    final repository = repositoryFor(upstream, ttl: Duration.zero);

    await repository.getAllShelters();
    final after = upstream.requests;
    await repository.getAllShelters();

    expect(upstream.requests, greaterThan(after));
  });

  test('concurrent misses trigger a single fetch', () async {
    final upstream = _Upstream([_upstreamRecord(id: 1, code: 'SA100-0002')]);
    final repository = repositoryFor(upstream);

    await Future.wait([
      repository.getAllShelters(),
      repository.getAllShelters(),
      repository.getAllShelters(),
    ]);

    expect(upstream.requests, lessThanOrEqualTo(2));
  });

  test('serves stale data when upstream fails', () async {
    // During a disaster a slightly old shelter list beats an error page.
    final upstream = _Upstream([_upstreamRecord(id: 1, code: 'SA100-0002')]);
    final repository = repositoryFor(upstream, ttl: Duration.zero);

    final fresh = await repository.getAllShelters();
    upstream.fail = true;
    final stale = await repository.getAllShelters();

    expect(stale.single.shelterCode, fresh.single.shelterCode);
  });

  test('a first-load failure propagates rather than serving nothing', () async {
    final upstream = _Upstream([])..fail = true;
    expect(() => repositoryFor(upstream).getAllShelters(), throwsA(anything));
  });

  test('coverage is passed through to the service layer', () async {
    final upstream = _Upstream([]);
    expect(repositoryFor(upstream).coordinateCoverage.total, 2);
  });
}
