import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:server/data/datasources/external/nfa_shelter_api.dart';
import 'package:server/data/datasources/local/shelter_snapshot_source.dart';
import 'package:server/data/repositories_impl/shelter_repository_impl.dart';
import 'package:server/domain/repositories/shelter_repository.dart';
import 'package:test/test.dart';

const _nfaCsvHeader =
    '序號,縣市及鄉鎮市區,村里,避難收容處所地址,經度,緯度,避難收容處所名稱,'
    '預計收容村里,預計收容人數,適用災害類別,管理人姓名,管理人電話,'
    '室內,室外,適合避難弱者安置';

String _nfaRow({
  int seq = 1,
  String region = '臺北市中正區',
  String village = '林興里',
  String address = '汀州路三段四號',
  String lng = '121.5265',
  String lat = '25.0190',
  String name = '測試避難所',
}) =>
    '$seq,$region,$village,$address,$lng,$lat,$name,'
    '林興里,100,水災,陳大文,02-11111111,是,否,是';

String _nfaCsv(List<String> rows) => '$_nfaCsvHeader\n${rows.join('\n')}\n';

/// Builds a snapshot CSV from column-name-keyed maps rather than a
/// hand-aligned positional string — a single dropped field silently shifts
/// every column after it (lat lands in the confidence slot, etc.) with no
/// error, just a row that fails the coordinate gate and vanishes.
String _snapshotCsv(List<Map<String, String>> rows) {
  final header = shelterSnapshotCsvHeader;
  final buffer = StringBuffer()..writeln(header.join(','));
  for (final row in rows) {
    buffer.writeln(header.map((h) => row[h] ?? '').join(','));
  }
  return buffer.toString();
}

Map<String, String> _snapshotRow({
  required String sourceId,
  required String cityCode,
  required String city,
  String township = '中正區',
  String lng = '121.52',
  String lat = '25.03',
}) => {
  'source_id': sourceId,
  'source': 'nfa_point_file',
  'source_updated_at': '2026-08-01T00:00:00.000Z',
  'city_code': cityCode,
  'city': city,
  'township': township,
  'village': '林興里',
  'name': '舊資料',
  'address': '舊地址',
  'lng': lng,
  'lat': lat,
  'coordinate_confidence': 'exact',
  'capacity': '10',
  'flood': 'N',
  'quake': 'N',
  'landslide': 'N',
  'tsunami': 'N',
  'nuclear': 'N',
  'indoor': '是',
  'outdoor': '否',
  'accessible': '是',
};

/// A snapshot with two counties, small enough to hand-build in a test but
/// enough for the sanity gate (§_looksImplausible) to have something to
/// compare a live fetch against.
final _snapshot = ShelterSnapshotSource.fromCsv(
  _snapshotCsv([
    _snapshotRow(sourceId: 'NFA-TPE-a', cityCode: 'TPE', city: '臺北市'),
    _snapshotRow(
      sourceId: 'NFA-KHH-b',
      cityCode: 'KHH',
      city: '高雄市',
      township: '苓雅區',
      lng: '120.5',
      lat: '22.6',
    ),
  ]),
);

/// A stub upstream that counts how many times it was hit.
class _Upstream {
  _Upstream(this.csvBody);

  final String? csvBody;
  int requests = 0;
  bool fail = false;

  http.Client get client => MockClient((request) async {
    requests++;
    if (fail || csvBody == null) return http.Response('upstream down', 503);
    // Without an explicit charset, package:http encodes `body` -> `bodyBytes`
    // as latin-1, which mangles every Chinese field and makes
    // NfaShelterApi's utf8.decode throw — the exact trap its own comment
    // warns about for the real upstream.
    return http.Response(
      csvBody!,
      200,
      headers: {'content-type': 'text/csv; charset=utf-8'},
    );
  });
}

void main() {
  ShelterRepositoryImpl repositoryFor(
    _Upstream upstream, {
    Duration ttl = const Duration(minutes: 10),
    ShelterSnapshotSource? snapshot,
  }) => ShelterRepositoryImpl(
    api: NfaShelterApi(client: upstream.client),
    snapshot: snapshot ?? ShelterSnapshotSource.empty(),
    cacheTtl: ttl,
  );

  test('maps a live NFA row into a Shelter', () async {
    final upstream = _Upstream(_nfaCsv([_nfaRow()]));
    final shelters = await repositoryFor(upstream).getAllShelters();

    final s = shelters.single;
    expect(s.city, '臺北市');
    expect(s.township, '中正區');
    expect(s.x, 121.5265);
    expect(s.y, 25.0190);
    expect(s.coordinateSource, 'nfa_point_file');
    expect(s.hasCoordinate, isTrue);
  });

  test('caches upstream for the TTL', () async {
    final upstream = _Upstream(_nfaCsv([_nfaRow()]));
    final repository = repositoryFor(upstream);

    await repository.getAllShelters();
    await repository.getAllShelters();
    await repository.getAllShelters();

    expect(upstream.requests, 1);
  });

  test('a zero TTL refetches', () async {
    final upstream = _Upstream(_nfaCsv([_nfaRow()]));
    final repository = repositoryFor(upstream, ttl: Duration.zero);

    await repository.getAllShelters();
    final after = upstream.requests;
    await repository.getAllShelters();

    expect(upstream.requests, greaterThan(after));
  });

  test('concurrent misses trigger a single fetch', () async {
    final upstream = _Upstream(_nfaCsv([_nfaRow()]));
    final repository = repositoryFor(upstream);

    await Future.wait([
      repository.getAllShelters(),
      repository.getAllShelters(),
      repository.getAllShelters(),
    ]);

    expect(upstream.requests, 1);
  });

  test('serves stale data when upstream fails', () async {
    final upstream = _Upstream(_nfaCsv([_nfaRow()]));
    final repository = repositoryFor(upstream, ttl: Duration.zero);

    final fresh = await repository.getAllShelters();
    upstream.fail = true;
    final stale = await repository.getAllShelters();

    expect(stale.single.shelterCode, fresh.single.shelterCode);
    expect(repository.dataFreshness, ShelterDataFreshness.cached);
  });

  test(
    'backs off instead of retrying a failing upstream every request',
    () async {
      final upstream = _Upstream(_nfaCsv([_nfaRow()]));
      final repository = repositoryFor(upstream, ttl: Duration.zero);

      await repository.getAllShelters();
      upstream.fail = true;
      await repository.getAllShelters(); // fails, enters backoff, serves stale
      final afterFirstFailure = upstream.requests;

      for (var i = 0; i < 5; i++) {
        expect((await repository.getAllShelters()).single.city, '臺北市');
      }

      expect(
        upstream.requests,
        afterFirstFailure,
        reason: 'requests during the backoff window must not reach upstream',
      );
    },
  );

  group('snapshot fallback (new: stronger than the old rethrow)', () {
    test(
      'a first-load failure with no cache serves the snapshot, not an error',
      () async {
        final upstream = _Upstream(null)..fail = true;
        final shelters = await repositoryFor(
          upstream,
          snapshot: _snapshot,
        ).getAllShelters();

        expect(shelters, hasLength(2));
        expect(
          shelters.map((s) => s.shelterCode),
          containsAll(['NFA-TPE-a', 'NFA-KHH-b']),
        );
      },
    );

    test(
      'freshness reports snapshot when falling back with nothing cached',
      () async {
        final upstream = _Upstream(null)..fail = true;
        final repository = repositoryFor(upstream, snapshot: _snapshot);
        await repository.getAllShelters();

        expect(repository.dataFreshness, ShelterDataFreshness.snapshot);
      },
    );

    test(
      'an empty snapshot and a failing upstream yields an empty list, not a throw',
      () async {
        final upstream = _Upstream(null)..fail = true;
        final shelters = await repositoryFor(upstream).getAllShelters();
        expect(shelters, isEmpty);
      },
    );
  });

  group(
    'sanity gate — a live fetch that looks worse than the snapshot is rejected',
    () {
      test('too few rows compared to the snapshot falls back to it', () async {
        // Snapshot has 2 rows; a "live" fetch of just 1 is well under the 80%
        // floor and should be rejected in favour of the snapshot.
        final upstream = _Upstream(_nfaCsv([_nfaRow()]));
        final shelters = await repositoryFor(
          upstream,
          snapshot: _snapshot,
        ).getAllShelters();

        expect(shelters, hasLength(2));
        expect(
          shelters.map((s) => s.shelterCode),
          containsAll(['NFA-TPE-a', 'NFA-KHH-b']),
        );
      });

      test(
        'too few counties compared to the snapshot falls back to it',
        () async {
          // Snapshot spans 2 counties (臺北市, 高雄市); a live fetch that only
          // covers one — even with plenty of rows — should still be rejected.
          final manyRowsOneCounty = List.generate(
            5,
            (i) => _nfaRow(seq: i, name: 'facility-$i', address: 'addr-$i'),
          );
          final upstream = _Upstream(_nfaCsv(manyRowsOneCounty));
          final shelters = await repositoryFor(
            upstream,
            snapshot: _snapshot,
          ).getAllShelters();

          expect(
            shelters.map((s) => s.shelterCode),
            containsAll(['NFA-TPE-a', 'NFA-KHH-b']),
          );
        },
      );

      test('a plausible live fetch is adopted normally', () async {
        final tpe = _nfaRow(seq: 1, region: '臺北市中正區');
        final khh = _nfaRow(
          seq: 2,
          region: '高雄市苓雅區',
          lng: '120.5',
          lat: '22.6',
          name: '高雄避難所',
        );
        final upstream = _Upstream(_nfaCsv([tpe, khh]));
        final repository = repositoryFor(upstream, snapshot: _snapshot);

        final shelters = await repository.getAllShelters();

        expect(shelters, hasLength(2));
        expect(repository.dataFreshness, ShelterDataFreshness.live);
      });
    },
  );

  test('coordinateCoverage reflects the currently-served list', () async {
    final upstream = _Upstream(_nfaCsv([_nfaRow()]));
    final repository = repositoryFor(upstream);
    await repository.getAllShelters();

    expect(repository.coordinateCoverage.total, 1);
    expect(repository.coordinateCoverage.withCoordinates, 1);
  });

  test('coordinateCoverage falls back to the snapshot before any fetch', () {
    final repository = repositoryFor(_Upstream(null), snapshot: _snapshot);
    expect(repository.coordinateCoverage.total, 2);
  });
}
