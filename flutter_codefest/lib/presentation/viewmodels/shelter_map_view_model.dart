import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_codefest/core/constants/map_constants.dart';
import 'package:flutter_codefest/core/map/basemap.dart';
import 'package:flutter_codefest/data/datasources/request_cache.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/data/models/shelter_page.dart';
import 'package:flutter_codefest/data/repositories/shelters_repository.dart'
    as repo;
import 'package:flutter_codefest/domain/marker_clustering.dart';
import 'package:flutter_codefest/domain/shelter_filters.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

typedef FetchClusters =
    Future<List<ShelterCluster>> Function(Map<String, String> params);
typedef FetchShelterPage =
    Future<ShelterPage> Function(Map<String, String> params);
typedef FetchNearbyShelters =
    Future<List<Shelter>> Function({
      required double lat,
      required double lng,
      double? radiusMeters,
      int limit,
    });
typedef IsLocationServiceEnabled = Future<bool> Function();
typedef CheckPermission = Future<LocationPermission> Function();
typedef RequestPermission = Future<LocationPermission> Function();
typedef GetCurrentPosition = Future<Position> Function();
typedef CacheGet = Future<CachedResponse?> Function(String key);
typedef CachePut = Future<void> Function(String key, Map<String, dynamic> body);

Future<Position> _defaultGetCurrentPosition() =>
    Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

/// Holds every piece of mutable state the map screen used to keep in its
/// `State` object, plus the logic that used to live in its methods.
///
/// The map no longer holds the full ~5,850-shelter dataset: markers come
/// from the server's `/shelters/clusters` endpoint per viewport, search
/// results are paginated server-side, and the nearby panel uses
/// `/shelters/nearby`. The old full-list fetch (and its multi-megabyte
/// localStorage cache) is gone entirely.
class ShelterMapViewModel extends ChangeNotifier {
  ShelterMapViewModel({
    FetchClusters fetchClusters = repo.fetchClusters,
    FetchShelterPage fetchShelterPage = repo.fetchSheltersPage,
    FetchNearbyShelters fetchNearby = repo.fetchNearbyShelters,
    IsLocationServiceEnabled isLocationServiceEnabled =
        Geolocator.isLocationServiceEnabled,
    CheckPermission checkPermission = Geolocator.checkPermission,
    RequestPermission requestPermission = Geolocator.requestPermission,
    GetCurrentPosition getCurrentPosition = _defaultGetCurrentPosition,
    CacheGet cacheGet = RequestCache.get,
    CachePut cachePut = RequestCache.put,
  }) : _fetchClusters = fetchClusters,
       _fetchShelterPage = fetchShelterPage,
       _fetchNearby = fetchNearby,
       _isLocationServiceEnabled = isLocationServiceEnabled,
       _checkPermission = checkPermission,
       _requestPermission = requestPermission,
       _getCurrentPosition = getCurrentPosition,
       _cacheGet = cacheGet,
       _cachePut = cachePut;

  final FetchClusters _fetchClusters;
  final FetchShelterPage _fetchShelterPage;
  final FetchNearbyShelters _fetchNearby;
  final IsLocationServiceEnabled _isLocationServiceEnabled;
  final CheckPermission _checkPermission;
  final RequestPermission _requestPermission;
  final GetCurrentPosition _getCurrentPosition;
  final CacheGet _cacheGet;
  final CachePut _cachePut;

  Timer? _messageDismissTimer;

  /// How many search results one page carries.
  static const searchPageSize = 50;

  List<ShelterCluster> _clusters = const [];
  List<Shelter> _nearbyShelters = const [];
  List<Shelter> _searchResults = const [];
  int _searchTotal = 0;
  int _searchOffset = 0;
  bool _searchHasMore = false;
  bool _isLoadingMore = false;
  String _searchQuery = '';

  Position? _currentPosition;
  Shelter? _selectedShelter;
  bool _showShelterDetails = false;

  Basemap _basemap = Basemap.emap;

  final Set<String> _selectedDisasterTypes = {};
  final Set<String> _selectedSpaceTypes = {};

  bool _isSearching = false;
  bool _isLoadingLocation = false;
  String? _locationMessage;
  bool _isLocationSuccess = true;

  bool _isShowingCachedData = false;
  DateTime? _cachedAt;

  /// Monotonic ids guarding the async fetch paths: a response that arrives
  /// after the user has moved on (panned again, typed a new query) is a
  /// stale answer and must not overwrite newer state.
  int _clusterRequestId = 0;
  int _searchRequestId = 0;

  LatLngBounds? _lastBounds;
  double _lastZoom = MapConstants.nationwideZoom;

  // ---------------------------------------------------------------------
  // Read-only state
  // ---------------------------------------------------------------------

  List<ShelterCluster> get clusters => _clusters;
  List<Shelter> get nearbyShelters => _nearbyShelters;
  List<Shelter> get searchResults => _searchResults;
  int get searchTotal => _searchTotal;
  bool get searchHasMore => _searchHasMore;
  bool get isLoadingMore => _isLoadingMore;
  String get searchQuery => _searchQuery;

  Position? get currentPosition => _currentPosition;
  LatLng? get currentLatLng => _currentPosition == null
      ? null
      : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

  Shelter? get selectedShelter => _selectedShelter;
  bool get showShelterDetails => _showShelterDetails;
  Basemap get basemap => _basemap;

  Set<String> get selectedDisasterTypes =>
      Set.unmodifiable(_selectedDisasterTypes);
  Set<String> get selectedSpaceTypes => Set.unmodifiable(_selectedSpaceTypes);
  bool isFilterSelected(String filterType) =>
      _selectedDisasterTypes.contains(filterType) ||
      _selectedSpaceTypes.contains(filterType);

  bool get isSearching => _isSearching;
  bool get isLoadingLocation => _isLoadingLocation;
  String? get locationMessage => _locationMessage;
  bool get isLocationSuccess => _isLocationSuccess;
  bool get isShowingCachedData => _isShowingCachedData;
  DateTime? get cachedAt => _cachedAt;

  // ---------------------------------------------------------------------
  // Map clusters
  // ---------------------------------------------------------------------

  /// Fetches clustered markers for the visible viewport. [bounds] is the
  /// current camera bounds; a viewport wider than the server's 6° bbox cap
  /// (i.e. zoomed way out past the country) is sent as "everything".
  ///
  /// On failure, falls back to the cached response for this exact viewport
  /// and flags it via [isShowingCachedData]; with neither, the markers are
  /// cleared — stale pins from a previous viewport are worse than none.
  Future<void> loadClusters(LatLngBounds? bounds, double zoom) async {
    _lastBounds = bounds;
    _lastZoom = zoom;
    final id = ++_clusterRequestId;

    final oversize =
        bounds != null &&
        ((bounds.east - bounds.west) > 6.0 ||
            (bounds.north - bounds.south) > 6.0);
    final capped = oversize ? null : bounds;
    final bbox = capped == null
        ? null
        : '${capped.west},${capped.south},${capped.east},${capped.north}';
    final params = repo.clustersQueryParams(
      bbox: bbox,
      zoom: zoom,
      disasters: _selectedDisasterTypes.isEmpty ? null : _selectedDisasterTypes,
      spaces: _selectedSpaceTypes.isEmpty ? null : _selectedSpaceTypes,
    );
    final key = RequestCache.keyFor('/shelters/clusters', params);

    try {
      final clusters = await _fetchClusters(params);
      if (id != _clusterRequestId) return;
      _clusters = clusters;
      _isShowingCachedData = false;
      _cachedAt = null;
      unawaited(
        _cachePut(key, {
          'clusters': [for (final c in clusters) c.toJson()],
        }),
      );
      notifyListeners();
    } catch (_) {
      final cached = await _cacheGet(key);
      if (id != _clusterRequestId) return;
      if (cached != null) {
        _clusters = [
          for (final c
              in cached.body['clusters'] as List<dynamic>? ?? const <dynamic>[])
            ShelterCluster.fromServerJson(c as Map<String, dynamic>),
        ];
        _isShowingCachedData = true;
        _cachedAt = cached.cachedAt;
      } else {
        _clusters = const [];
        _locationMessage = '無法連線到伺服器,請確認後端已啟動';
        _isLocationSuccess = false;
      }
      notifyListeners();
    }
  }

  /// Re-runs the last cluster query — used when the filters change while the
  /// map is idle.
  Future<void> refreshClusters() => loadClusters(_lastBounds, _lastZoom);

  // ---------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------

  void selectShelter(Shelter shelter) {
    _selectedShelter = shelter;
    _showShelterDetails = true;
    notifyListeners();
  }

  void clearSelection() {
    _selectedShelter = null;
    _showShelterDetails = false;
    notifyListeners();
  }

  void switchBasemap(Basemap basemap) {
    _basemap = basemap;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Search and filtering
  // ---------------------------------------------------------------------

  void toggleSearching() {
    _isSearching = !_isSearching;
    if (!_isSearching) {
      _searchQuery = '';
      _searchResults = const [];
      _searchTotal = 0;
      _searchHasMore = false;
      // The map kept moving (and skipping cluster fetches) while search was
      // open — bring the markers back in sync with the current viewport.
      unawaited(refreshClusters());
    } else if (_showShelterDetails) {
      _showShelterDetails = false;
      _selectedShelter = null;
    }
    notifyListeners();
  }

  /// Closes search and/or the detail panel, e.g. after tapping empty map.
  ///
  /// The caller still owns the search field's `TextEditingController` and
  /// must clear it itself — this only resets view-model state.
  void dismissOverlays() {
    if (!_isSearching && !_showShelterDetails) return;
    if (_isSearching) {
      _isSearching = false;
      _searchQuery = '';
      _searchResults = const [];
      _searchTotal = 0;
      _searchHasMore = false;
      unawaited(refreshClusters());
    }
    if (_showShelterDetails) {
      _showShelterDetails = false;
      _selectedShelter = null;
    }
    notifyListeners();
  }

  void toggleFilter(String filterType) {
    if (_selectedDisasterTypes.contains(filterType) ||
        _selectedSpaceTypes.contains(filterType)) {
      _selectedDisasterTypes.remove(filterType);
      _selectedSpaceTypes.remove(filterType);
    } else if (disasterFilterTypes.contains(filterType)) {
      _selectedDisasterTypes.add(filterType);
    } else if (spaceFilterTypes.contains(filterType)) {
      _selectedSpaceTypes.add(filterType);
    }
    // Filters are applied server-side now, so a chip change means re-asking:
    // the current search (page 1) when searching, the viewport otherwise.
    unawaited(_refreshAfterFilterChange());
  }

  /// Re-fetches whatever the current filters should be applied to. Failures
  /// are swallowed — the user already got a SnackBar for the initial search,
  /// and keeping the previous results on screen beats an unhandled async
  /// error when a chip toggle re-query flakes.
  Future<void> _refreshAfterFilterChange() async {
    try {
      if (_isSearching && _searchQuery.isNotEmpty) {
        await search(_searchQuery);
      } else {
        await refreshClusters();
      }
    } catch (_) {
      // Keep whatever is on screen.
    }
  }

  /// Fetches the first page of results for [query]. Throws on network
  /// failure — the caller decides how to surface that (e.g. a SnackBar),
  /// matching the surrounding page's other API calls.
  Future<void> search(String query) async {
    _searchQuery = query;
    if (query.isEmpty) {
      _searchRequestId++;
      _searchResults = const [];
      _searchTotal = 0;
      _searchHasMore = false;
      _searchOffset = 0;
      notifyListeners();
      return;
    }
    await _fetchSearchPage(offset: 0, requestId: ++_searchRequestId);
  }

  /// Loads the next page of the current search, if one exists. Failures
  /// stop pagination silently — the list already has content to show.
  Future<void> loadMoreSearch() async {
    if (!_searchHasMore || _isLoadingMore) return;
    await _fetchSearchPage(offset: _searchOffset, requestId: _searchRequestId);
  }

  Future<void> _fetchSearchPage({
    required int offset,
    required int requestId,
  }) async {
    _isLoadingMore = offset > 0;
    notifyListeners();

    final params = repo.sheltersPageQueryParams(
      q: _searchQuery,
      disasters: _selectedDisasterTypes.isEmpty ? null : _selectedDisasterTypes,
      spaces: _selectedSpaceTypes.isEmpty ? null : _selectedSpaceTypes,
      limit: searchPageSize,
      offset: offset,
    );
    final key = RequestCache.keyFor('/shelters', params);

    try {
      final page = await _fetchShelterPage(params);
      if (requestId != _searchRequestId) return;
      _searchResults = offset == 0
          ? page.shelters
          : [..._searchResults, ...page.shelters];
      _searchTotal = page.total;
      _searchOffset = offset + page.shelters.length;
      _searchHasMore = page.truncated;
      _isShowingCachedData = false;
      _cachedAt = null;
      unawaited(_cachePut(key, page.toJson()));
    } catch (_) {
      if (requestId != _searchRequestId) return;
      if (offset == 0) {
        final cached = await _cacheGet(key);
        if (requestId != _searchRequestId) return;
        if (cached != null) {
          final page = ShelterPage.fromJson(cached.body);
          _searchResults = page.shelters;
          _searchTotal = page.total;
          _searchOffset = page.shelters.length;
          _searchHasMore = page.truncated;
          _isShowingCachedData = true;
          _cachedAt = cached.cachedAt;
        } else {
          rethrow;
        }
      } else {
        _searchHasMore = false;
      }
    } finally {
      if (requestId == _searchRequestId) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  // ---------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------

  /// Returns null on success, or a message to show the user.
  Future<String?> _ensureLocationPermission() async {
    if (!await _isLocationServiceEnabled()) return '請開啟定位服務';

    var permission = await _checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _requestPermission();
    }
    if (permission == LocationPermission.denied) return '定位權限被拒絕';
    if (permission == LocationPermission.deniedForever) {
      return '定位權限被永久拒絕,請至設定中開啟';
    }
    return null;
  }

  Future<void> getCurrentLocation() async {
    _isLoadingLocation = true;
    _locationMessage = null;
    notifyListeners();

    try {
      final problem = await _ensureLocationPermission();
      if (problem != null) {
        _locationMessage = problem;
        _isLocationSuccess = false;
        return;
      }

      final position = await _getCurrentPosition();
      if (position.latitude == 0.0 && position.longitude == 0.0) {
        _locationMessage = '取得位置失敗: 無效的座標';
        _isLocationSuccess = false;
        return;
      }

      _currentPosition = position;
      // The nearby panel now asks the server instead of scanning the full
      // dataset client-side.
      try {
        _nearbyShelters = await _fetchNearby(
          lat: position.latitude,
          lng: position.longitude,
          radiusMeters: MapConstants.visibleRadiusMeters,
          limit: 5,
        );
      } catch (_) {
        _nearbyShelters = const [];
      }

      _locationMessage =
          '已定位: ${position.latitude.toStringAsFixed(4)}, '
          '${position.longitude.toStringAsFixed(4)}';
      _isLocationSuccess = true;

      _messageDismissTimer?.cancel();
      _messageDismissTimer = Timer(const Duration(seconds: 3), () {
        if (_isLocationSuccess && _locationMessage != null) {
          _locationMessage = null;
          notifyListeners();
        }
      });
    } catch (e) {
      _locationMessage = '無法取得位置: $e';
      _isLocationSuccess = false;
    } finally {
      _isLoadingLocation = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _messageDismissTimer?.cancel();
    super.dispose();
  }
}
