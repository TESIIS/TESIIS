import 'dart:async';

import 'package:flutter_codefest/data/datasources/request_cache.dart';
import 'package:flutter_codefest/data/models/cluster_page.dart';
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
  Future<ClusterPage> Function(Map<String, String>)? clusters,
  Future<ShelterPage> Function(Map<String, String>)? page,
  Future<List<Shelter>> Function({
    required double lat,
    required double lng,
    double? radiusMeters,
    int limit,
    Set<String>? disasters,
    Set<String>? spaces,
  })?
  nearby,
  Future<CachedResponse?> Function(String key)? cacheGet,
  Future<void> Function(String key, Map<String, dynamic> body)? cachePut,
  Future<Position?> Function()? getLastKnownPosition,
}) => ShelterMapViewModel(
  fetchClusters: clusters ?? (params) async => const ClusterPage(clusters: []),
  fetchShelterPage:
      page ??
      (params) async =>
          const ShelterPage(shelters: [], total: 0, truncated: false),
  fetchNearby:
      nearby ??
      ({
        required lat,
        required lng,
        radiusMeters,
        limit = 10,
        disasters,
        spaces,
      }) async => const [],
  isLocationServiceEnabled: () async => false,
  getLastKnownPosition: getLastKnownPosition ?? () async => null,
  cacheGet: cacheGet ?? (key) async => null,
  cachePut: cachePut ?? (key, body) async {},
);

void main() {
  group('loadClusters', () {
    test('stores the clusters the server returned', () async {
      final near = fakeShelter(id: 1, lat: 25.0, lng: 121.5);
      final vm = _viewModel(
        clusters: (params) async =>
            ClusterPage(clusters: [_singleCluster(near)]),
      );

      await vm.loadClusters(_bounds, 13);

      expect(vm.clusters.single.single, near);
    });

    test('sends bbox, zoom and filter groups as query params', () async {
      Map<String, String>? seen;
      final vm = _viewModel(
        clusters: (params) async {
          seen = params;
          return const ClusterPage(clusters: []);
        },
      );
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
      final vm = _viewModel(
        clusters: (params) async {
          seen = params;
          return const ClusterPage(clusters: []);
        },
      );

      final huge = LatLngBounds(
        const LatLng(18.0, 118.0),
        const LatLng(27.0, 127.0),
      );
      await vm.loadClusters(huge, 6);

      expect(seen?.containsKey('bbox'), isFalse);
    });

    test(
      'ignores a stale response that arrives after a newer request',
      () async {
        final first = fakeShelter(id: 1, lat: 25.0, lng: 121.5);
        final second = fakeShelter(id: 2, lat: 25.1, lng: 121.6);
        final firstCompleter = Completer<ClusterPage>();
        final vm = _viewModel(
          clusters: (params) => params['bbox']!.startsWith('120.0')
              ? firstCompleter.future
              : Future.value(ClusterPage(clusters: [_singleCluster(second)])),
        );

        // The first request hangs; the second completes immediately.
        final firstFetch = vm.loadClusters(
          LatLngBounds(const LatLng(24.0, 120.0), const LatLng(25.0, 121.0)),
          13,
        );
        await vm.loadClusters(_bounds, 13);
        firstCompleter.complete(ClusterPage(clusters: [_singleCluster(first)]));
        await firstFetch;

        expect(vm.clusters.single.single, second);
      },
    );

    test('falls back to the cached viewport when the fetch fails', () async {
      final cached = fakeShelter(id: 9, lat: 25.0, lng: 121.5);
      final cachedAt = DateTime.utc(2026, 1, 1);
      final vm = _viewModel(
        clusters: (params) async => throw Exception('network down'),
        cacheGet: (key) async => CachedResponse(
          body: {
            'clusters': [
              {
                'count': 1,
                'lat': 25.0,
                'lng': 121.5,
                'shelter': cached.toJson(),
              },
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

    test(
      'clears markers and reports when neither fetch nor cache work',
      () async {
        final vm = _viewModel(
          clusters: (params) async => throw Exception('network down'),
        );

        await vm.loadClusters(_bounds, 13);

        expect(vm.clusters, isEmpty);
        expect(vm.isLocationSuccess, isFalse);
        expect(vm.locationMessage, contains('無法連線到伺服器'));
      },
    );

    test('a later successful fetch clears the cached-data flag', () async {
      final fresh = fakeShelter(id: 1, lat: 25.0, lng: 121.5);
      var useFresh = false;
      final vm = _viewModel(
        clusters: (params) async {
          if (useFresh) return ClusterPage(clusters: [_singleCluster(fresh)]);
          throw Exception('network down');
        },
        cacheGet: (key) async => CachedResponse(
          body: {
            'clusters': [
              {
                'count': 1,
                'lat': 25.0,
                'lng': 121.5,
                'shelter': fakeShelter(id: 9, lat: 25.0, lng: 121.5).toJson(),
              },
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
      final vm = _viewModel(
        page: (params) async {
          calls++;
          return const ShelterPage(shelters: [], total: 0, truncated: false);
        },
      );

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
      final vm = _viewModel(
        page: (params) async {
          seen = params;
          return const ShelterPage(shelters: [], total: 0, truncated: false);
        },
      );
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
      final vm = _viewModel(
        page: (params) async {
          calls++;
          final offset = int.parse(params['offset']!);
          return ShelterPage(
            shelters: [fakeShelter(id: offset + 1)],
            total: 2,
            truncated: offset == 0,
          );
        },
      );

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
            : Future.value(
                ShelterPage(
                  shelters: [fakeShelter(id: 2, name: '新的')],
                  total: 1,
                  truncated: false,
                ),
              ),
      );

      final first = vm.search('舊');
      await vm.search('新');
      firstCompleter.complete(
        ShelterPage(
          shelters: [fakeShelter(id: 1, name: '舊的')],
          total: 1,
          truncated: false,
        ),
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

  group('search preview', () {
    Future<ShelterMapViewModel> locatedViewModel({
      required Future<List<Shelter>> Function({
        required double lat,
        required double lng,
        double? radiusMeters,
        int limit,
        Set<String>? disasters,
        Set<String>? spaces,
      })
      nearby,
    }) async {
      final vm = ShelterMapViewModel(
        fetchClusters: (params) async => const ClusterPage(clusters: []),
        fetchShelterPage: (params) async =>
            const ShelterPage(shelters: [], total: 0, truncated: false),
        fetchNearby: nearby,
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.always,
        requestPermission: () async => LocationPermission.always,
        getLastKnownPosition: () async => null,
        getCurrentPosition: () async => fakePosition(lat: 25.0, lng: 121.5),
        cacheGet: (key) async => null,
        cachePut: (key, body) async {},
      );
      await vm.getCurrentLocation();
      return vm;
    }

    test(
      'opening search with a known position shows a nearest-first preview',
      () async {
        final near = fakeShelter(id: 1, lat: 25.0, lng: 121.5, name: '近的');
        final vm = await locatedViewModel(
          nearby:
              ({
                required lat,
                required lng,
                radiusMeters,
                limit = 10,
                disasters,
                spaces,
              }) async => [near],
        );

        vm.toggleSearching();
        await Future<void>.delayed(Duration.zero);

        expect(vm.searchPreview, [near]);
      },
    );

    test('clearing a typed query falls back to the preview again', () async {
      final near = fakeShelter(id: 1, lat: 25.0, lng: 121.5, name: '近的');
      final vm = await locatedViewModel(
        nearby:
            ({
              required lat,
              required lng,
              radiusMeters,
              limit = 10,
              disasters,
              spaces,
            }) async => [near],
      );

      await vm.search('某個關鍵字');
      expect(vm.searchPreview, isEmpty);

      await vm.search('');
      await Future<void>.delayed(Duration.zero);

      expect(vm.searchResults, isEmpty);
      expect(vm.searchPreview, [near]);
    });

    test('without a known position, the preview stays empty', () async {
      final vm = _viewModel();

      vm.toggleSearching();
      await Future<void>.delayed(Duration.zero);

      expect(vm.searchPreview, isEmpty);
    });
  });

  group('toggleFilter', () {
    test('re-issues the current search with the new groups', () async {
      Map<String, String>? seen;
      final vm = _viewModel(
        page: (params) async {
          seen = params;
          return const ShelterPage(shelters: [], total: 0, truncated: false);
        },
      );
      vm.toggleSearching();
      await vm.search('公園');

      vm.toggleFilter('tsunami');
      await Future<void>.delayed(Duration.zero);

      expect(seen?['q'], '公園');
      expect(seen?['disasters'], 'tsunami');
    });

    test('refreshes clusters when not searching', () async {
      var calls = 0;
      final vm = _viewModel(
        clusters: (params) async {
          calls++;
          return const ClusterPage(clusters: []);
        },
      );
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
      final vm = _viewModel(
        clusters: (params) async {
          clusterCalls++;
          return const ClusterPage(clusters: []);
        },
      );
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
        fetchClusters: (params) async => const ClusterPage(clusters: []),
        fetchShelterPage: (params) async =>
            const ShelterPage(shelters: [], total: 0, truncated: false),
        fetchNearby:
            ({
              required lat,
              required lng,
              radiusMeters,
              limit = 10,
              disasters,
              spaces,
            }) async {
              nearbyCall = {
                'lat': lat,
                'lng': lng,
                'radius': radiusMeters ?? 0,
              };
              return [near];
            },
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.always,
        requestPermission: () async => LocationPermission.always,
        getLastKnownPosition: () async => null,
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

    test('falls back to getCurrentPosition when getLastKnownPosition throws '
        '(Flutter Web has no last-known-position concept)', () async {
      final vm = ShelterMapViewModel(
        fetchClusters: (params) async => const ClusterPage(clusters: []),
        fetchShelterPage: (params) async =>
            const ShelterPage(shelters: [], total: 0, truncated: false),
        fetchNearby:
            ({
              required lat,
              required lng,
              radiusMeters,
              limit = 10,
              disasters,
              spaces,
            }) async => const [],
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.always,
        requestPermission: () async => LocationPermission.always,
        getLastKnownPosition: () async =>
            throw UnsupportedError('not supported on the web platform'),
        getCurrentPosition: () async => fakePosition(lat: 25.0, lng: 121.5),
        cacheGet: (key) async => null,
        cachePut: (key, body) async {},
      );

      await vm.getCurrentLocation();

      expect(vm.isLocationSuccess, isTrue);
      expect(vm.currentPosition?.latitude, 25.0);
    });

    test('refreshes nearby shelters with the current zoom radius', () async {
      final radii = <double>[];
      final vm = ShelterMapViewModel(
        fetchClusters: (params) async => const ClusterPage(clusters: []),
        fetchShelterPage: (params) async =>
            const ShelterPage(shelters: [], total: 0, truncated: false),
        fetchNearby:
            ({
              required lat,
              required lng,
              radiusMeters,
              limit = 10,
              disasters,
              spaces,
            }) async {
              radii.add(radiusMeters ?? 0);
              return [fakeShelter(id: radii.length, lat: lat, lng: lng)];
            },
        isLocationServiceEnabled: () async => true,
        checkPermission: () async => LocationPermission.always,
        requestPermission: () async => LocationPermission.always,
        getLastKnownPosition: () async => null,
        getCurrentPosition: () async => fakePosition(lat: 25.0, lng: 121.5),
        cacheGet: (key) async => null,
        cachePut: (key, body) async {},
      );

      await vm.getCurrentLocation(radiusMeters: 1500);
      await vm.refreshNearbyShelters(radiusMeters: 3000);

      expect(radii, [1500, 3000]);
      expect(vm.nearbyRadiusMeters, 3000);
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

  group('dataFreshness', () {
    // The server reports this on every list response and nothing ever read
    // it, so the map could be drawn entirely from the committed offline
    // snapshot with no way for the user to tell.
    test('is taken from the clusters response', () async {
      final vm = _viewModel(
        clusters: (params) async =>
            const ClusterPage(clusters: [], dataFreshness: 'snapshot'),
      );
      await vm.loadClusters(_bounds, 13);

      expect(vm.dataFreshness, 'snapshot');
      expect(vm.isServingStaleData, isTrue);
    });

    test('live data is not flagged as stale', () async {
      final vm = _viewModel(
        clusters: (params) async =>
            const ClusterPage(clusters: [], dataFreshness: 'live'),
      );
      await vm.loadClusters(_bounds, 13);

      expect(vm.isServingStaleData, isFalse);
    });

    test('a server that reports nothing is not assumed stale', () async {
      final vm = _viewModel(
        clusters: (params) async => const ClusterPage(clusters: []),
      );
      await vm.loadClusters(_bounds, 13);

      expect(vm.isServingStaleData, isFalse);
    });

    test('survives the cache round-trip', () async {
      const page = ClusterPage(clusters: [], dataFreshness: 'cached');
      final restored = ClusterPage.fromJson(page.toJson());
      expect(restored.dataFreshness, 'cached');
    });
  });
}
