import 'dart:async';

import 'package:flutter_codefest/data/datasources/request_cache.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/data/models/shelter_page.dart';
import 'package:flutter_codefest/domain/marker_clustering.dart';
import 'package:flutter_codefest/presentation/viewmodels/shelter_map_view_model.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'support/fakes.dart';

final _bounds = LatLngBounds(
  const LatLng(24.5, 121.0),
  const LatLng(25.5, 122.0),
);

ShelterCluster _singleCluster(Shelter shelter) => ShelterCluster(
  center: LatLng(shelter.latitude!, shelter.longitude!),
  members: [shelter],
);

ShelterMapViewModel _viewModel({
  Future<List<ShelterCluster>> Function(Map<String, String>)? clusters,
  Future<ShelterPage> Function(Map<String, String>)? page,
  Future<List<Shelter>> Function({
    required double lat,
    required double lng,
    double? radiusMeters,
    int limit,
  })? nearby,
  Future<CachedResponse?> Function(String key)? cacheGet,
  Future<void> Function(String key, Map<String, dynamic> body)? cachePut,
}) => ShelterMapViewModel(
  fetchClusters: clusters ?? (params) async => const [],
  fetchShelterPage: page ?? (params) async => const ShelterPage(
    shelters: [],
    total: 0,
    truncated: false,
  ),
  fetchNearby:
      nearby ??
      ({required lat, required lng, radiusMeters, limit = 10}) async =>
          const [],
  isLocationServiceEnabled: () async => false,
  cacheGet: cacheGet ?? (key) async => null,
  cachePut: cachePut ?? (key, body) async {},
);

void main() {
  group('loadClusters', () {
    test('stores the clusters the server returned', () async {
      final near = fakeShelter(id: 1, lat: 25.0, lng: 121.5);
      final vm = _viewModel(clusters: (params) async => [_singleCluster(near)]);

      await vm.loadClusters(_bounds, 13);

      expect(vm.clusters.single.single, near);
    });

    test('sends bbox, zoom and filter groups as query params', () async {
      Map<String, String>? seen;
      final vm = _viewModel(clusters: (params) async {
        seen = params;
        return const [];
      });
      await vm.loadClusters(_bounds, 13);

      vm.toggleFilter('flood');
      vm.toggleFilter('indoor');
      // toggleFilter re-fetches immediately; wait for it to settle.
      await Future<void>.delayed(Duration.zero);

      expect(seen?['bbox'], '121.0,24.5,122.0,25.5');
      expect(seen?['zoom'], '13');
      expect(seen?['disasters'], 'flood');
      expect(seen?['spaces'], 'indoor');
    });

    test('omits bbox when the viewport exceeds the 6° cap', () async {
      Map<String, String>? seen;
      final vm = _viewModel(clusters: (params) async {
        seen = params;
        return const [];
      });

      final huge = LatLngBounds(const LatLng(18.0, 118.0), const LatLng(27.0, 127.0));
      await vm.loadClusters(huge, 6);

      expect(seen?.containsKey('bbox'), isFalse);
    });

    test('ignores a stale response that arrives after a newer request', () async {
      final first = fakeShelter(id: 1, lat: 25.0, lng: 121.5);
      final second = fakeShelter(id: 2, lat: 25.1, lng: 121.6);
      final firstCompleter = Completer<List<ShelterCluster>>();
      final vm = _viewModel(
        clusters: (params) => params['bbox']!.startsWith('120.0')
            ? firstCompleter.future
            : Future.value([_singleCluster(second)]),
      );

      // The first request hangs; the second completes immediately.
      final firstFetch = vm.loadClusters(
        LatLngBounds(const LatLng(24.0, 120.0), const LatLng(25.0, 121.0)),
        13,
      );
      await vm.loadClusters(_bounds, 13);
      firstCompleter.complete([_singleCluster(first)]);
      await firstFetch;

      expect(vm.clusters.single.single, second);
    });

    test('falls back to the cached viewport when the fetch fails', () async {
      final cached = fakeShelter(id: 9, lat: 25.0, lng: 121.5);
      final cachedAt = DateTime.utc(2026, 1, 1);
      final vm = _viewModel(
        clusters: (params) async => throw Exception('network down'),
        cacheGet: (key) async => CachedResponse(
          body: {
            'clusters': [
              {'count': 1, 'lat': 25.0, 'lng': 121.5, 'shelter': cached.toJson()},
            ],
          },
          cachedAt: cachedAt,
        ),
      );

      await vm.loadClusters(_bounds, 13);

      expect(vm.clusters.single.single.name, cached.name);
      expect(vm.isShowingCachedData, isTrue);
      expect(vm.cachedAt, cachedAt);
      expect(vm.locationMessage, isNull);
    });

    test('clears markers and reports when neither fetch nor cache work', () async {
      final vm = _viewModel(
        clusters: (params) async => throw Exception('network down'),
      );

      await vm.loadClusters(_bounds, 13);

      expect(vm.clusters, isEmpty);
      expect(vm.isLocationSuccess, isFalse);
      expect(vm.locationMessage, contains('無法連線到伺服器'));
    });

    test('a later successful fetch clears the cached-data flag', () async {
      final fresh = fakeShelter(id: 1, lat: 25.0, lng: 121.5);
      var useFresh = false;
      final vm = _viewModel(
        clusters: (params) async {
          if (useFresh) return [_singleCluster(fresh)];
          throw Exception('network down');
        },
        cacheGet: (key) async => CachedResponse(
          body: {
            'clusters': [
              {'count': 1, 'lat': 25.0, 'lng': 121.5, 'shelter': fakeShelter(id: 9, lat: 25.0, lng: 121.5).toJson()},
            ],
          },
          cachedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await vm.loadClusters(_bounds, 13);
      expect(vm.isShowingCachedData, isTrue);

      useFresh = true;
      await vm.loadClusters(_bounds, 13);

      expect(vm.isShowingCachedData, isFalse);
      expect(vm.cachedAt, isNull);
      expect(vm.clusters.single.single, fresh);
    });
  });

  group('search', () {
    test('an empty query clears results without calling the network', () async {
      var calls = 0;
      final vm = _viewModel(page: (params) async {
        calls++;
        return const ShelterPage(shelters: [], total: 0, truncated: false);
      });

      await vm.search('');

      expect(vm.searchResults, isEmpty);
      expect(calls, 0);
    });

    test('populates results, total and hasMore from the first page', () async {
      final vm = _viewModel(
        page: (params) async => ShelterPage(
          shelters: [fakeShelter(id: 1)],
          total: 120,
          truncated: true,
        ),
      );

      await vm.search('螢橋');

      expect(vm.searchResults, hasLength(1));
      expect(vm.searchTotal, 120);
      expect(vm.searchHasMore, isTrue);
    });

    test('sends the query and filter groups server-side', () async {
      Map<String, String>? seen;
      final vm = _viewModel(page: (params) async {
        seen = params;
        return const ShelterPage(shelters: [], total: 0, truncated: false);
      });
      vm.toggleSearching();
      vm.toggleFilter('landslide');
      vm.toggleFilter('outdoor');

      await vm.search('公園');

      expect(seen?['q'], '公園');
      expect(seen?['disasters'], 'landslide');
      expect(seen?['spaces'], 'outdoor');
      expect(seen?['limit'], '${ShelterMapViewModel.searchPageSize}');
      expect(seen?['offset'], '0');
    });

    test('loadMoreSearch appends the next page', () async {
      var calls = 0;
      final vm = _viewModel(page: (params) async {
        calls++;
        final offset = int.parse(params['offset']!);
        return ShelterPage(
          shelters: [fakeShelter(id: offset + 1)],
          total: 2,
          truncated: offset == 0,
        );
      });

      await vm.search('國小');
      expect(vm.searchResults, hasLength(1));
      expect(vm.searchHasMore, isTrue);

      await vm.loadMoreSearch();

      expect(calls, 2);
      expect(vm.searchResults, hasLength(2));
      expect(vm.searchHasMore, isFalse);
    });

    test('a stale first page is dropped when a newer search wins', () async {
      final firstCompleter = Completer<ShelterPage>();
      final vm = _viewModel(
        page: (params) => params['q'] == '舊'
            ? firstCompleter.future
            : Future.value(ShelterPage(
                shelters: [fakeShelter(id: 2, name: '新的')],
                total: 1,
                truncated: false,
              )),
      );

      final first = vm.search('舊');
      await vm.search('新');
      firstCompleter.complete(
        ShelterPage(shelters: [fakeShelter(id: 1, name: '舊的')], total: 1, truncated: false),
      );
      await first;

      expect(vm.searchResults.single.name, '新的');
    });

    test('propagates a fetch failure when there is no cache', () async {
      final vm = _viewModel(page: (params) async => throw Exception('offline'));

      expect(vm.search('螢橋'), throwsException);
    });

    test('falls back to the cached page when the fetch fails', () async {
      final cached = fakeShelter(id: 9, name: '快取的');
      final vm = _viewModel(
        page: (params) async => throw Exception('offline'),
        cacheGet: (key) async => CachedResponse(
          body: ShelterPage(
            shelters: [cached],
            total: 1,
            truncated: false,
          ).toJson(),
          cachedAt: DateTime.utc(2026, 1, 1),
        ),
      );

      await vm.search('螢橋');

      expect(vm.searchResults.single.name, cached.name);
      expect(vm.isShowingCachedData, isTrue);
    });
  });

  group('toggleFilter', () {
    test('re-issues the current search with the new groups', () async {
      Map<String, String>? seen;
      final vm = _viewModel(page: (params) async {
        seen = params;
        return const ShelterPage(shelters: [], total: 0, truncated: false);
      });
      vm.toggleSearching();
      await vm.search('公園');

      vm.toggleFilter('tsunami');
      await Future<void>.delayed(Duration.zero);

      expect(seen?['q'], '公園');
      expect(seen?['disasters'], 'tsunami');
    });

    test('refreshes clusters when not searching', () async {
      var calls = 0;
      final vm = _viewModel(clusters: (params) async {
        calls++;
        return const [];
      });
      await vm.loadClusters(_bounds, 13);
      expect(calls, 1);

      vm.toggleFilter('flood');
      await Future<void>.delayed(Duration.zero);

      expect(calls, 2);
    });
  });

  group('toggleSearching', () {
    test('closing search refreshes the viewport clusters', () async {
      var clusterCalls = 0;
      final vm = _viewModel(clusters: (params) async {
        clusterCalls++;
        return const [];
      });
      await vm.loadClusters(_bounds, 13);
      expect(clusterCalls, 1);

      vm.toggleSearching();
      vm.toggleSearching();
      await Future<void>.delayed(Duration.zero);

      expect(clusterCalls, 2);
    });
  });

  group('getCurrentLocation', () {
    test('reports when the location service is disabled', () async {
      final vm = _viewModel();

      await vm.getCurrentLocation();

      expect(vm.isLocationSuccess, isFalse);
      expect(vm.locationMessage, '請開啟定位服務');
    });

    test('on success, asks the server for nearby shelters', () async {
      final near = fakeShelter(id: 1, lat: 25.0, lng: 121.5);
      Map<String, double>? nearbyCall;
      final vm = ShelterMapViewModel(
        fetchClusters: (params) async => const [],
        fetchShelterPage: (params) async =>
            const ShelterPage(shelters: [], total: 0, truncated: false),
        fetchNearby: ({required lat, required lng, radiusMeters, limit = 10}) async {
          nearbyCall = {'lat': lat, 'lng': lng, 'radius': radiusMeters ?? 0};
          return [near];
        },
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.always,
        requestPermission: () async => LocationPermission.always,
        getCurrentPosition: () async => fakePosition(lat: 25.0, lng: 121.5),
        cacheGet: (key) async => null,
        cachePut: (key, body) async {},
      );

      await vm.getCurrentLocation();

      expect(vm.isLocationSuccess, isTrue);
      expect(vm.nearbyShelters, [near]);
      expect(nearbyCall?['lat'], 25.0);
      expect(nearbyCall?['lng'], 121.5);
      expect(nearbyCall?['radius'], 1500);
    });
  });

  group('selection', () {
    test('selectShelter opens the detail panel', () {
      final vm = _viewModel();
      final shelter = fakeShelter(id: 1);

      vm.selectShelter(shelter);

      expect(vm.selectedShelter, shelter);
      expect(vm.showShelterDetails, isTrue);
    });

    test('clearSelection closes it again', () {
      final vm = _viewModel();
      vm.selectShelter(fakeShelter(id: 1));

      vm.clearSelection();

      expect(vm.selectedShelter, isNull);
      expect(vm.showShelterDetails, isFalse);
    });
  });
}
