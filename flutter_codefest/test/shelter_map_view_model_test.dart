import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/presentation/viewmodels/shelter_map_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'support/fakes.dart';

ShelterMapViewModel _viewModel({
  List<Shelter>? shelters,
  Future<List<Shelter>> Function({String? q})? search,
}) => ShelterMapViewModel(
  fetchAllShelters: () async => shelters ?? const [],
  fetchFilteredShelters: search ?? ({String? q}) async => const [],
  // Location is never exercised by these tests unless overridden below.
  isLocationServiceEnabled: () async => false,
);

void main() {
  group('loadShelters', () {
    test('populates shelters and computes the visible set', () async {
      final near = fakeShelter(id: 1, lat: 25.0375, lng: 121.5651);
      final far = fakeShelter(id: 2, lat: 26.0, lng: 122.0);
      final vm = _viewModel(shelters: [near, far]);

      await vm.loadShelters();

      expect(vm.shelters, [near, far]);
      expect(vm.visibleShelters, [near]);
    });

    test('surfaces a friendly message when the fetch fails', () async {
      final vm = ShelterMapViewModel(
        fetchAllShelters: () async => throw Exception('network down'),
        isLocationServiceEnabled: () async => false,
      );

      await vm.loadShelters();

      expect(vm.isLocationSuccess, isFalse);
      expect(vm.locationMessage, contains('無法連線到伺服器'));
    });
  });

  group('toggleFilter', () {
    test('selecting a filter narrows filteredShelters', () async {
      final flood = fakeShelter(id: 1, flood: 'Y');
      final other = fakeShelter(id: 2, flood: 'N', earthquake: 'N');
      final vm = _viewModel(shelters: [flood, other]);
      await vm.loadShelters();

      vm.toggleFilter('flood');

      expect(vm.isFilterSelected('flood'), isTrue);
      expect(vm.filteredShelters, [flood]);
    });

    test('tapping the same filter again clears it', () async {
      final vm = _viewModel(shelters: [fakeShelter(id: 1, flood: 'Y')]);
      await vm.loadShelters();

      vm.toggleFilter('flood');
      vm.toggleFilter('flood');

      expect(vm.isFilterSelected('flood'), isFalse);
      // No filters and no search query: nothing to list.
      expect(vm.filteredShelters, isEmpty);
    });
  });

  group('selection', () {
    test('selectShelter opens the detail panel', () async {
      final vm = _viewModel();
      final shelter = fakeShelter(id: 1);

      vm.selectShelter(shelter);

      expect(vm.selectedShelter, shelter);
      expect(vm.showShelterDetails, isTrue);
    });

    test('clearSelection closes it again', () async {
      final vm = _viewModel();
      vm.selectShelter(fakeShelter(id: 1));

      vm.clearSelection();

      expect(vm.selectedShelter, isNull);
      expect(vm.showShelterDetails, isFalse);
    });
  });

  group('toggleSearching', () {
    test('opening search while the detail panel is open closes the panel', () {
      final vm = _viewModel();
      vm.selectShelter(fakeShelter(id: 1));

      vm.toggleSearching();

      expect(vm.isSearching, isTrue);
      expect(vm.showShelterDetails, isFalse);
      expect(vm.selectedShelter, isNull);
    });

    test('closing search clears the query and results', () async {
      final match = fakeShelter(id: 1, name: '螢橋國中');
      final vm = _viewModel(
        search: ({q}) async => [match],
      );
      vm.toggleSearching();
      await vm.search('螢橋');
      expect(vm.searchResults, [match]);

      vm.toggleSearching();

      expect(vm.isSearching, isFalse);
      expect(vm.searchResults, isEmpty);
      expect(vm.filteredShelters, isEmpty);
    });
  });

  group('search', () {
    test('an empty query clears results without calling the network', () async {
      var callCount = 0;
      final vm = _viewModel(
        search: ({q}) async {
          callCount++;
          return [fakeShelter(id: 1)];
        },
      );

      await vm.search('');

      expect(vm.searchResults, isEmpty);
      expect(callCount, 0);
    });

    test('propagates a fetch failure to the caller', () async {
      final vm = _viewModel(
        search: ({q}) async => throw Exception('offline'),
      );

      expect(vm.search('螢橋'), throwsException);
    });
  });

  group('getCurrentLocation', () {
    test('reports when the location service is disabled', () async {
      final vm = _viewModel();

      await vm.getCurrentLocation();

      expect(vm.isLocationSuccess, isFalse);
      expect(vm.locationMessage, '請開啟定位服務');
    });

    test('on success, updates position and computes nearby shelters', () async {
      final near = fakeShelter(id: 1, lat: 25.0, lng: 121.5);
      final vm = ShelterMapViewModel(
        fetchAllShelters: () async => [near],
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.always,
        requestPermission: () async => LocationPermission.always,
        getCurrentPosition: () async => fakePosition(lat: 25.0, lng: 121.5),
      );
      await vm.loadShelters();

      await vm.getCurrentLocation();

      expect(vm.isLocationSuccess, isTrue);
      expect(vm.currentPosition?.latitude, 25.0);
      expect(vm.nearbyShelters, [near]);
    });
  });
}
