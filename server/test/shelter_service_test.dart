import 'package:server/core/geo/taiwan_bounds.dart';
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
      final byRegion =
          service.computeStats(data: data, includeShelters: true)['byRegion']
              as List;
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
      final items =
          service.computeStats(data: located, includeItems: true)['items']
              as List;
      expect((items.single as Map)['座標x'], 121.5);
      expect((items.single as Map)['座標y'], 25.03);
    });

    test('items and per-village/township shelters are omitted by default', () {
      // ~5,850 nationwide records embedding full shelter detail at every
      // city/township/village level would be multi-megabyte JSON with each
      // shelter repeated 2-3 times — this must stay opt-in.
      final stats = service.computeStats(data: data);
      expect(stats.containsKey('items'), isFalse);

      final byRegion = stats['byRegion'] as List;
      final townships =
          (byRegion.first as Map<String, dynamic>)['townships'] as List;
      final firstTownship = townships.first as Map<String, dynamic>;
      expect(firstTownship.containsKey('shelters'), isFalse);
      final firstVillage =
          (firstTownship['villages'] as List).first as Map<String, dynamic>;
      expect(firstVillage.containsKey('shelters'), isFalse);
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

  group('filterShelters — bbox', () {
    test('keeps only shelters inside the box', () {
      final inside = shelter(id: 1, x: 121.5, y: 25.03);
      final outside = shelter(id: 2, x: 120.5, y: 22.6);
      final box = const GeoBox(121.0, 122.0, 24.5, 25.5);
      final out = service.filterShelters(data: [inside, outside], bbox: box);
      expect(out.map((s) => s.id), [1]);
    });

    test('a shelter with no coordinate never matches a bbox query', () {
      final noCoordinate = shelter(id: 1);
      final box = const GeoBox(120.0, 122.0, 21.0, 26.0);
      expect(service.filterShelters(data: [noCoordinate], bbox: box), isEmpty);
    });
  });

  group('computeRegions', () {
    final nationwide = [
      shelter(id: 1, city: '臺北市', township: '中正區'),
      shelter(id: 2, city: '臺北市', township: '大同區'),
      shelter(id: 3, city: '高雄市', township: '苓雅區'),
    ];

    test('with no city, lists all 22 counties', () {
      final regions =
          service.computeRegions(data: nationwide)['regions'] as List;
      expect(regions.length, 22);
      final taipei =
          regions.firstWhere((r) => (r as Map)['city'] == '臺北市') as Map;
      expect(taipei['count'], 2);
      expect(taipei['cityCode'], 'TPE');
    });

    test('a county with zero shelters still appears, with count 0', () {
      final regions =
          service.computeRegions(data: nationwide)['regions'] as List;
      final penghu =
          regions.firstWhere((r) => (r as Map)['city'] == '澎湖縣') as Map;
      expect(penghu['count'], 0);
    });

    test('folds 臺/台 city-name variants together', () {
      final mixedSpelling = [
        shelter(id: 1, city: '臺北市'),
        shelter(id: 2, city: '台北市'),
      ];
      final regions =
          service.computeRegions(data: mixedSpelling)['regions'] as List;
      final taipei =
          regions.firstWhere((r) => (r as Map)['city'] == '臺北市') as Map;
      expect(taipei['count'], 2);
    });

    test("with a city, lists that city's townships instead", () {
      final result = service.computeRegions(data: nationwide, city: '臺北市');
      expect(result['total'], 2);
      final townships = result['townships'] as List;
      expect(townships.length, 2);
      expect(
        townships.map((t) => (t as Map)['township']),
        containsAll(['中正區', '大同區']),
      );
    });
  });

  group('filterShelters — disasters/spaces groups', () {
    final data = [
      shelter(
        id: 1,
        flood: 'Y',
        landslide: 'N',
        quake: 'N',
        indoor: 'Y',
        outdoor: 'N',
      ),
      shelter(
        id: 2,
        flood: 'N',
        landslide: 'Y',
        quake: 'N',
        indoor: 'N',
        outdoor: 'N',
      ),
      shelter(
        id: 3,
        flood: 'Y',
        landslide: 'N',
        quake: 'N',
        indoor: 'N',
        outdoor: 'Y',
      ),
    ];

    test('disasters are ORed within the group', () {
      final out = service.filterShelters(
        data: data,
        disasters: const {'水災', '土石流'},
      );
      expect(out.map((s) => s.id), [1, 2, 3]);
    });

    test('spaces are ORed within the group', () {
      final out = service.filterShelters(
        data: data,
        spaces: const {'室內', '室外'},
      );
      expect(out.map((s) => s.id), [1, 3]);
    });

    test('the two groups are ANDed against each other', () {
      final out = service.filterShelters(
        data: data,
        disasters: const {'水災'},
        spaces: const {'室內'},
      );
      expect(out.map((s) => s.id), [1]);
    });

    test('a group is ANDed with the flat hazards params', () {
      final out = service.filterShelters(
        data: data,
        hazards: const {'震災': 'N'},
        disasters: const {'水災'},
      );
      expect(out.map((s) => s.id), [1, 3]);
    });
  });

  group('clusterShelters', () {
    test('groups shelters that share a grid cell into one count cluster', () {
      // ~10 m apart — the same cell at any zoom a map view uses.
      final data = [
        shelter(id: 1, x: 121.5000, y: 25.0300),
        shelter(id: 2, x: 121.5001, y: 25.0301),
      ];
      final clusters = service.clusterShelters(data: data, zoom: 13);
      expect(clusters, hasLength(1));
      expect(clusters.single.count, 2);
      expect(clusters.single.shelter, isNull);
    });

    test('a lone shelter stays individual with the shelter attached', () {
      final data = [shelter(id: 1, x: 121.50, y: 25.03)];
      final clusters = service.clusterShelters(data: data, zoom: 13);
      expect(clusters.single.count, 1);
      expect(clusters.single.shelter?.id, 1);
      expect(clusters.single.lat, 25.03);
      expect(clusters.single.lng, 121.50);
    });

    test('shelters without coordinates are dropped', () {
      final data = [shelter(id: 1), shelter(id: 2, x: 121.5, y: 25.03)];
      final clusters = service.clusterShelters(data: data, zoom: 13);
      expect(clusters.single.shelter?.id, 2);
    });

    test('clusters break apart as zoom increases', () {
      // ~0.02° apart: the same cell at zoom 8 (cells are ~0.44° wide),
      // different cells at zoom 13 (cells are ~0.014° wide).
      final data = [
        shelter(id: 1, x: 121.5000, y: 25.0300),
        shelter(id: 2, x: 121.5200, y: 25.0300),
      ];
      final coarse = service.clusterShelters(data: data, zoom: 8);
      final fine = service.clusterShelters(data: data, zoom: 13);
      expect(coarse, hasLength(1));
      expect(coarse.single.count, 2);
      expect(fine, hasLength(2));
      expect(fine.every((c) => c.count == 1), isTrue);
    });

    test('an empty list yields no clusters', () {
      expect(service.clusterShelters(data: const [], zoom: 13), isEmpty);
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
