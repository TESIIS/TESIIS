import 'package:server/data/datasources/local/coordinate_source.dart';
import 'package:server/domain/entities/shelter.dart';
import 'package:server/domain/repositories/shelter_repository.dart';
import 'package:server/domain/services/shelter_service.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  final service = ShelterService(repository: _NullRepository());

  group('filterShelters — region, type and keyword are always ANDed', () {
    final data = [
      shelter(
        id: 1,
        township: '中正區',
        type: '學校',
        name: '螢橋國中',
        address: '汀州路三段四號',
      ),
      shelter(
        id: 2,
        township: '大同區',
        type: '學校',
        name: '建成國中',
        address: '長安西路37號',
      ),
      shelter(
        id: 3,
        township: '中正區',
        type: '公園',
        name: '二二八和平公園',
        address: '凱達格蘭大道3號',
      ),
    ];

    test('township', () {
      final out = service.filterShelters(data: data, township: '中正區');
      expect(out.map((s) => s.id), [1, 3]);
    });

    test('臺/台 folding applies to region and type', () {
      expect(
        service.filterShelters(data: data, city: '台北市').length,
        data.length,
      );
    });

    test('township AND type', () {
      final out = service.filterShelters(
        data: data,
        township: '中正區',
        type: '學校',
      );
      expect(out.map((s) => s.id), [1]);
    });

    test('matchMode does not loosen region or type', () {
      // `match` is documented as applying to hazards only.
      final out = service.filterShelters(
        data: data,
        township: '中正區',
        type: '學校',
        matchMode: 'or',
      );
      expect(out.map((s) => s.id), [1]);
    });

    test('keyword tokens are ANDed across the searchable fields', () {
      final out = service.filterShelters(data: data, keyword: '中正 公園');
      expect(out.map((s) => s.id), [3]);
      expect(service.filterShelters(data: data, keyword: 'zzzz'), isEmpty);
    });
  });

  group('filterShelters — villages', () {
    final data = [
      shelter(id: 1, village: '林興里', serviceVillages: '板溪里、網溪里'),
      shelter(id: 2, village: '黎明里', serviceVillages: '建國里'),
    ];

    test('matches the shelter own village', () {
      expect(
        service.filterShelters(data: data, village: '林興里').map((s) => s.id),
        [1],
      );
    });

    test('also matches through 服務里別', () {
      expect(
        service.filterShelters(data: data, village: '網溪里').map((s) => s.id),
        [1],
      );
    });

    test('multiple villages are ORed with each other', () {
      final out = service.filterShelters(data: data, villages: ['網溪里', '建國里']);
      expect(out.map((s) => s.id), [1, 2]);
    });
  });

  group('filterShelters — hazards', () {
    final data = [
      shelter(id: 1, quake: '備用', tsunami: 'N', landslide: 'N'),
      shelter(id: 2, quake: 'Y', tsunami: '備用', landslide: 'N'),
      shelter(id: 3, quake: 'N', tsunami: 'N', landslide: '老舊聚落'),
    ];

    test('aliases count as Y', () {
      // 震災 is 備用 for most of the dataset; 土石流 has 老舊聚落.
      final out = service.filterShelters(data: data, hazards: {'震災': 'Y'});
      expect(out.map((s) => s.id), [1, 2]);
      expect(
        service
            .filterShelters(data: data, hazards: {'土石流': 'Y'})
            .map((s) => s.id),
        [3],
      );
    });

    test('海嘯=Y works even though no record spells it Y', () {
      final out = service.filterShelters(data: data, hazards: {'海嘯': 'Y'});
      expect(out.map((s) => s.id), [2]);
    });

    test('an explicit alias query returns only that variant', () {
      expect(
        service
            .filterShelters(data: data, hazards: {'震災': '備用'})
            .map((s) => s.id),
        [1],
      );
    });

    test('N filters for the negative', () {
      expect(
        service
            .filterShelters(data: data, hazards: {'震災': 'N'})
            .map((s) => s.id),
        [3],
      );
    });

    test('match=or evaluates only the requested hazards', () {
      // Folding in the eight unrequested keys made match=or true for every
      // record, since nearly every shelter is N for something.
      final out = service.filterShelters(
        data: data,
        hazards: {'海嘯': 'Y', '土石流': 'Y'},
        matchMode: 'or',
      );
      expect(out.map((s) => s.id), [2, 3]);

      final and = service.filterShelters(
        data: data,
        hazards: {'海嘯': 'Y', '土石流': 'Y'},
        matchMode: 'and',
      );
      expect(and, isEmpty);
    });

    test('an unrecognised request value is treated as unset', () {
      expect(
        service.filterShelters(data: data, hazards: {'震災': '???'}).length,
        data.length,
      );
    });
  });

  group('computeStats', () {
    final data = [
      shelter(
        id: 1,
        township: '中正區',
        type: '學校',
        village: '林興里',
        serviceVillages: '林興里、板溪里',
      ),
      shelter(id: 2, township: '中正區', type: '學校', village: '黎明里'),
      shelter(id: 3, township: '大同區', type: '公園', village: '國慶里'),
    ];

    test('agrees with filterShelters about what matches', () {
      final stats = service.computeStats(data: data, township: '中正區');
      final filtered = service.filterShelters(data: data, township: '中正區');
      expect(stats['total'], filtered.length);
    });

    test('byType is sorted by count descending', () {
      final byType = service.computeStats(data: data)['byType'] as List;
      expect(byType.first, {'type': '學校', 'count': 2});
    });

    test('a village reached twice is counted once', () {
      // Shelter 1 is in 林興里 and also serves 林興里. Counting the 村里 column
      // and the 服務里別 expansion separately double-counts it.
      final byRegion = service.computeStats(data: data)['byRegion'] as List;
      final taipei = byRegion.first as Map<String, dynamic>;
      final townships = taipei['townships'] as List;
      final zhongzheng =
          townships.firstWhere((t) => (t as Map)['township'] == '中正區')
              as Map<String, dynamic>;

      final villages = zhongzheng['villages'] as List;
      final linxing =
          villages.firstWhere((v) => (v as Map)['village'] == '林興里')
              as Map<String, dynamic>;
      expect(linxing['count'], 1);
      expect((linxing['shelters'] as List).length, 1);
    });

    test('township totals count each shelter once', () {
      final byRegion = service.computeStats(data: data)['byRegion'] as List;
      final townships =
          (byRegion.first as Map<String, dynamic>)['townships'] as List;
      final total = townships.fold<int>(
        0,
        (sum, t) => sum + ((t as Map)['total'] as int),
      );
      expect(total, data.length);
    });

    test('items carry coordinates so a client can map them', () {
      final located = [shelter(id: 9, x: 121.5, y: 25.03)];
      final items = service.computeStats(data: located)['items'] as List;
      expect((items.single as Map)['座標x'], 121.5);
      expect((items.single as Map)['座標y'], 25.03);
    });

    group('coordinateQuality', () {
      final mixed = [
        shelter(
          id: 1,
          township: '中正區',
          village: '林興里',
          serviceVillages: '林興里、板溪里',
          x: 121.5,
          y: 25.03,
          coordinateSource: 'nfa_point_file',
          coordinateConfidence: 'exact',
        ),
        shelter(
          id: 2,
          township: '中正區',
          village: '黎明里',
          x: 121.52,
          y: 25.04,
          coordinateSource: 'taipei_airraid',
          coordinateConfidence: 'approx',
        ),
        // No coordinate at all — the "missing" case.
        shelter(id: 3, township: '中正區', village: '黎明里'),
        shelter(id: 4, township: '大同區', village: '國慶里'),
      ];

      test('city level aggregates across every shelter in the city', () {
        final byRegion = service.computeStats(data: mixed)['byRegion'] as List;
        final taipei = byRegion.first as Map<String, dynamic>;
        final quality = taipei['coordinateQuality'] as Map<String, dynamic>;

        expect(quality['total'], 4);
        expect(quality['withCoordinates'], 2);
        expect(quality['missing'], 2);
        expect(quality['bySource'], {'nfa_point_file': 1, 'taipei_airraid': 1});
        expect(quality['byConfidence'], {'exact': 1, 'approx': 1});
      });

      test('township level scopes to that township only', () {
        final byRegion = service.computeStats(data: mixed)['byRegion'] as List;
        final townships =
            (byRegion.first as Map<String, dynamic>)['townships'] as List;
        final zhongzheng =
            townships.firstWhere((t) => (t as Map)['township'] == '中正區')
                as Map<String, dynamic>;
        final quality = zhongzheng['coordinateQuality'] as Map<String, dynamic>;

        expect(quality['total'], 3);
        expect(quality['withCoordinates'], 2);
        expect(quality['missing'], 1);
      });

      test('village level counts a shelter once even if reached via 服務里別', () {
        final byRegion = service.computeStats(data: mixed)['byRegion'] as List;
        final townships =
            (byRegion.first as Map<String, dynamic>)['townships'] as List;
        final zhongzheng =
            townships.firstWhere((t) => (t as Map)['township'] == '中正區')
                as Map<String, dynamic>;
        final villages = zhongzheng['villages'] as List;
        final linxing =
            villages.firstWhere((v) => (v as Map)['village'] == '林興里')
                as Map<String, dynamic>;
        final quality = linxing['coordinateQuality'] as Map<String, dynamic>;

        expect(quality['total'], 1);
        expect(quality['withCoordinates'], 1);
      });
    });
  });
}

/// computeStats/filterShelters are pure; the repository is never touched.
class _NullRepository implements ShelterRepository {
  @override
  Future<List<Shelter>> getAllShelters() async => const [];

  @override
  CoordinateCoverage get coordinateCoverage =>
      const CoordinateCoverage(total: 0, withCoordinates: 0, bySource: {});

  @override
  ShelterDataFreshness get dataFreshness => ShelterDataFreshness.live;

  @override
  DateTime? get dataUpdatedAt => null;
}
