import 'package:flutter_codefest/domain/shelter_filters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('matchesSelectedFilters', () {
    test('empty selections match everything', () {
      final shelter = fakeShelter(id: 1, flood: 'N', indoor: 'N');
      expect(
        matchesSelectedFilters(shelter, disasterTypes: {}, spaceTypes: {}),
        isTrue,
      );
    });

    test('disaster selections are ORed within the category', () {
      final shelter = fakeShelter(id: 1, flood: 'N', earthquake: 'Y');
      expect(
        matchesSelectedFilters(
          shelter,
          disasterTypes: {'flood', 'earthquake'},
          spaceTypes: {},
        ),
        isTrue,
      );
    });

    test('disaster and space categories are ANDed', () {
      final shelter = fakeShelter(id: 1, flood: 'Y', indoor: 'N', outdoor: 'N');
      expect(
        matchesSelectedFilters(
          shelter,
          disasterTypes: {'flood'},
          spaceTypes: {'indoor'},
        ),
        isFalse,
      );
    });
  });

  group('applyShelterFilters', () {
    test('returns the source unchanged when no filters are selected', () {
      final shelters = [fakeShelter(id: 1), fakeShelter(id: 2)];
      final result = applyShelterFilters(
        shelters,
        disasterTypes: {},
        spaceTypes: {},
      );
      expect(result, shelters);
    });

    test('filters by the selected chips', () {
      final match = fakeShelter(id: 1, flood: 'Y');
      final noMatch = fakeShelter(id: 2, flood: 'N', earthquake: 'N');
      final result = applyShelterFilters(
        [match, noMatch],
        disasterTypes: {'flood'},
        spaceTypes: {},
      );
      expect(result, [match]);
    });

    test('sorts located shelters by distance without truncating', () {
      final near = fakeShelter(id: 1, flood: 'Y', lat: 25.0, lng: 121.5);
      final far = fakeShelter(id: 2, flood: 'Y', lat: 25.5, lng: 122.0);
      final result = applyShelterFilters(
        [far, near],
        disasterTypes: {'flood'},
        spaceTypes: {},
        lat: 25.0,
        lon: 121.5,
      );
      expect(result, [near, far]);
    });

    test('shelters without a coordinate sort after located ones, not dropped', () {
      final located = fakeShelter(id: 1, flood: 'Y', lat: 25.0, lng: 121.5);
      final unlocated = fakeShelter(id: 2, flood: 'Y', lat: null, lng: null);
      final result = applyShelterFilters(
        [unlocated, located],
        disasterTypes: {'flood'},
        spaceTypes: {},
        lat: 25.0,
        lon: 121.5,
      );
      expect(result, [located, unlocated]);
    });
  });
}
