// Contract test for the `byRegion[*].townships[*].coordinateQuality` shape
// `GET /shelters/stats` sends. Nothing enforces this shape across the two
// packages, so it is asserted here.

import 'package:flutter_codefest/data/models/region_coordinate_stats.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> statsJson() => {
  'total': 4,
  'byRegion': [
    {
      'city': '臺北市',
      'total': 4,
      'coordinateQuality': {
        'total': 4,
        'withCoordinates': 1,
        'missing': 3,
        'bySource': {'nfa_point_file': 1},
        'byConfidence': {'exact': 1},
      },
      'townships': [
        {
          'township': '中正區',
          'total': 1,
          'coordinateQuality': {
            'total': 1,
            'withCoordinates': 0,
            'missing': 1,
            'bySource': <String, int>{},
            'byConfidence': <String, int>{},
          },
          'villages': [],
        },
        {
          'township': '大同區',
          'total': 3,
          'coordinateQuality': {
            'total': 3,
            'withCoordinates': 1,
            'missing': 2,
            'bySource': {'nfa_point_file': 1},
            'byConfidence': {'exact': 1},
          },
          'villages': [],
        },
      ],
    },
  ],
};

void main() {
  group('RegionCoordinateStats.listFromStatsJson', () {
    test('flattens every township across every city', () {
      final rows = RegionCoordinateStats.listFromStatsJson(statsJson());

      expect(rows.length, 2);
      expect(rows.map((r) => r.township), containsAll(['中正區', '大同區']));
      expect(rows.every((r) => r.city == '臺北市'), isTrue);
    });

    test('carries the coordinate-quality counts through', () {
      final rows = RegionCoordinateStats.listFromStatsJson(statsJson());
      final zhongzheng = rows.firstWhere((r) => r.township == '中正區');

      expect(zhongzheng.total, 1);
      expect(zhongzheng.withCoordinates, 0);
      expect(zhongzheng.missing, 1);
    });

    test('sorts by missing count, worst first', () {
      final rows = RegionCoordinateStats.listFromStatsJson(statsJson());

      expect(rows.first.township, '大同區');
      expect(rows.first.missing, 2);
      expect(rows.last.township, '中正區');
    });

    test('an empty byRegion produces an empty list', () {
      expect(
        RegionCoordinateStats.listFromStatsJson({'byRegion': []}),
        isEmpty,
      );
    });
  });
}
