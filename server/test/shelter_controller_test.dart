// Contract tests for the HTTP surface.
//
// The Flutter client reads Chinese JSON keys and compares hazard values against
// the literal 'Y'. That is an implicit cross-repo contract with no compiler
// enforcing it, so it gets asserted here.

import 'dart:convert';

import 'package:server/data/datasources/local/coordinate_source.dart';
import 'package:server/domain/entities/shelter.dart';
import 'package:server/domain/repositories/shelter_repository.dart';
import 'package:server/domain/services/shelter_service.dart';
import 'package:server/presentation/controllers/shelter_controller.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

class _FakeRepository implements ShelterRepository {
  _FakeRepository(this.shelters, {this.error});

  final List<Shelter> shelters;
  final Object? error;
  int calls = 0;

  @override
  Future<List<Shelter>> getAllShelters() async {
    calls++;
    if (error != null) throw error!;
    return shelters;
  }

  @override
  CoordinateCoverage get coordinateCoverage => CoordinateCoverage(
    total: shelters.length,
    withCoordinates: shelters.where((s) => s.hasCoordinate).length,
    bySource: const {'manual': 1},
  );

  @override
  ShelterDataFreshness get dataFreshness => ShelterDataFreshness.live;

  @override
  DateTime? get dataUpdatedAt => DateTime.utc(2026, 8, 23);
}

Future<Map<String, dynamic>> get(
  ShelterController controller,
  String path,
) async {
  final response = await controller.router.call(
    Request('GET', Uri.parse('http://localhost$path')),
  );
  return {
    'status': response.statusCode,
    'body': jsonDecode(await response.readAsString()),
  };
}

void main() {
  ShelterController controllerFor(List<Shelter> shelters, {Object? error}) =>
      ShelterController(
        service: ShelterService(
          repository: _FakeRepository(shelters, error: error),
        ),
      );

  group('GET /shelters', () {
    final data = [
      shelter(
        id: 1,
        name: '螢橋國中',
        quake: '備用',
        tsunami: 'N',
        serviceVillages: '板溪里、網溪里。',
        x: 121.5265,
        y: 25.0190,
        coordinateSource: 'nfa_point_file',
        coordinateConfidence: 'exact',
      ),
      shelter(id: 2, name: '無座標公園', township: '大同區'),
    ];

    test('serves the Chinese keys the Flutter client reads', () async {
      final res = await get(controllerFor(data), '/shelters?limit=1');
      expect(res['status'], 200);
      final body = res['body'] as Map<String, dynamic>;
      expect(body['success'], isTrue);
      expect(body['total'], 2, reason: 'total is the filtered count');

      final first = (body['data'] as List).single as Map<String, dynamic>;
      for (final key in [
        '收容所編號',
        '名稱',
        '縣市',
        '鄉鎮',
        '村里',
        '門牌地址',
        '類型',
        '水災',
        '震災',
        '土石流',
        '海嘯',
        '救濟支站',
        '無障礙設施',
        '室內',
        '室外',
        '服務里別',
        '容納人數',
        '座標x',
        '座標y',
      ]) {
        expect(first.containsKey(key), isTrue, reason: 'missing $key');
      }
    });

    test('normalises hazard aliases to Y for the client', () async {
      // The Flutter side compares `== 'Y'`. Leaving 備用 raw makes every
      // earthquake shelter invisible in the app.
      final res = await get(controllerFor(data), '/shelters?limit=1');
      final first = ((res['body'] as Map)['data'] as List).single as Map;
      expect(first['震災'], 'Y');
      expect(first['海嘯'], 'N');
    });

    test('服務里別 is an array, split on the messy separators', () async {
      final res = await get(controllerFor(data), '/shelters?limit=1');
      final first = ((res['body'] as Map)['data'] as List).single as Map;
      expect(first['服務里別'], ['板溪里', '網溪里']);
    });

    test('exposes coordinate provenance', () async {
      final res = await get(controllerFor(data), '/shelters');
      final rows = ((res['body'] as Map)['data'] as List).cast<Map>();
      expect(rows[0]['座標來源'], 'nfa_point_file');
      expect(rows[0]['座標精度'], 'exact');
      // A shelter with no coordinate is still served, with nulls, so the client
      // can list it instead of pretending it does not exist.
      expect(rows[1]['座標x'], isNull);
      expect(rows[1]['座標來源'], isNull);
    });

    test('limit and offset page the filtered result', () async {
      final res = await get(controllerFor(data), '/shelters?limit=1&offset=1');
      final rows = ((res['body'] as Map)['data'] as List).cast<Map>();
      expect(rows.single['名稱'], '無座標公園');
      expect((res['body'] as Map)['total'], 2);
    });

    test('negative paging is rejected', () async {
      final res = await get(controllerFor(data), '/shelters?limit=-1');
      expect(res['status'], 400);
      expect((res['body'] as Map)['success'], isFalse);
    });

    test('filters by township and hazard', () async {
      final res = await get(controllerFor(data), '/shelters?township=大同區');
      expect((res['body'] as Map)['total'], 1);

      final zh = await get(controllerFor(data), '/shelters?鄉鎮=大同區');
      expect((zh['body'] as Map)['total'], 1, reason: 'Chinese alias key');
    });

    test('an internal error does not leak details', () async {
      final res = await get(
        controllerFor(data, error: StateError('upstream https://secret/x')),
        '/shelters',
      );
      expect(res['status'], 500);
      final body = res['body'] as Map;
      expect(body['success'], isFalse);
      expect(body['message'], isNot(contains('secret')));
      expect(body['message'], isNot(contains('StateError')));
    });
  });

  group('GET /shelters/stats', () {
    final data = [shelter(id: 1, x: 121.5, y: 25.03), shelter(id: 2)];

    test('echoes every filter it applied, including villages', () async {
      // `villages` used to be applied but omitted from the echo, so a client
      // could not tell which filters actually took effect.
      final res = await get(
        controllerFor(data),
        '/shelters/stats?villages=林興里,黎明里&match=or&quake=Y',
      );
      final filters = (res['body'] as Map)['filters'] as Map;
      expect(filters['villages'], ['林興里', '黎明里']);
      expect(filters['match'], 'or');
      expect(filters['hazards'], {'震災': 'Y'});
    });

    test('reports coordinate coverage', () async {
      final res = await get(controllerFor(data), '/shelters/stats');
      final coverage = (res['body'] as Map)['coordinateCoverage'] as Map;
      expect(coverage['total'], 2);
      expect(coverage['withCoordinates'], 1);
    });

    test('reports coordinate quality per region', () async {
      final res = await get(controllerFor(data), '/shelters/stats');
      final byRegion = (res['body'] as Map)['byRegion'] as List;
      final taipei = byRegion.first as Map;
      final cityQuality = taipei['coordinateQuality'] as Map;
      expect(cityQuality['total'], 2);
      expect(cityQuality['withCoordinates'], 1);
      expect(cityQuality['missing'], 1);

      final township = (taipei['townships'] as List).first as Map;
      expect(township['coordinateQuality'], isA<Map>());
    });
  });

  group('GET /shelters/nearby', () {
    // 臺北車站 is at roughly 25.0478 / 121.5170.
    final data = [
      shelter(id: 1, name: '近的', x: 121.5180, y: 25.0480),
      shelter(id: 2, name: '遠的', x: 121.5600, y: 25.0800),
      shelter(id: 3, name: '沒座標的'),
    ];

    test('sorts by distance and reports it', () async {
      final res = await get(
        controllerFor(data),
        '/shelters/nearby?lat=25.0478&lng=121.5170',
      );
      final rows = ((res['body'] as Map)['data'] as List).cast<Map>();
      expect(rows.map((r) => r['名稱']), ['近的', '遠的']);
      expect(rows.first['距離公尺'], lessThan(200));
      expect(rows[1]['距離公尺'], greaterThan(rows[0]['距離公尺'] as int));
    });

    test(
      'radius filters, and excluded-without-coordinates is reported',
      () async {
        final res = await get(
          controllerFor(data),
          '/shelters/nearby?lat=25.0478&lng=121.5170&radius=500',
        );
        final body = res['body'] as Map;
        expect((body['data'] as List).length, 1);
        // Without this count the user would think there is nothing else nearby,
        // when really we just cannot place it.
        expect(body['excludedWithoutCoordinates'], 1);
      },
    );

    test('limit caps the result', () async {
      final res = await get(
        controllerFor(data),
        '/shelters/nearby?lat=25.0478&lng=121.5170&limit=1',
      );
      expect(((res['body'] as Map)['data'] as List).length, 1);
      expect((res['body'] as Map)['total'], 2, reason: 'total is pre-limit');
    });

    test('missing or malformed coordinates are a 400', () async {
      for (final query in [
        '/shelters/nearby',
        '/shelters/nearby?lat=25.0',
        '/shelters/nearby?lat=abc&lng=121.5',
      ]) {
        final res = await get(controllerFor(data), query);
        expect(res['status'], 400, reason: query);
      }
    });

    test('hazard filters apply before the distance sort', () async {
      final res = await get(
        controllerFor(data),
        '/shelters/nearby?lat=25.0478&lng=121.5170&tsunami=Y',
      );
      expect(((res['body'] as Map)['data'] as List), isEmpty);
    });
  });
}
