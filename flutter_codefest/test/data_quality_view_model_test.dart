import 'package:flutter_codefest/presentation/viewmodels/data_quality_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _statsJson() => {
  'byRegion': [
    {
      'city': '臺北市',
      'townships': [
        {
          'township': '中正區',
          'coordinateQuality': {'total': 1, 'withCoordinates': 0, 'missing': 1},
        },
        {
          'township': '大同區',
          'coordinateQuality': {'total': 3, 'withCoordinates': 1, 'missing': 2},
        },
      ],
    },
  ],
};

void main() {
  group('DataQualityViewModel.load', () {
    test('populates townships sorted worst-missing-first', () async {
      final vm = DataQualityViewModel(
        fetchShelterStats: () async => _statsJson(),
      );

      await vm.load();

      expect(vm.isLoading, isFalse);
      expect(vm.errorMessage, isNull);
      expect(vm.townships.map((t) => t.township), ['大同區', '中正區']);
    });

    test('surfaces a friendly message when the fetch fails', () async {
      final vm = DataQualityViewModel(
        fetchShelterStats: () async => throw Exception('network down'),
      );

      await vm.load();

      expect(vm.isLoading, isFalse);
      expect(vm.errorMessage, isNotNull);
      expect(vm.townships, isEmpty);
    });
  });
}
