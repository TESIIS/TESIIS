import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_codefest/core/constants/map_constants.dart';
import 'package:flutter_codefest/core/map/basemap.dart';
import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_codefest/data/datasources/shelter_cache.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/data/repositories/shelters_repository.dart'
    as repo;
import 'package:flutter_codefest/domain/shelter_filters.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

typedef FetchAllShelters = Future<List<Shelter>> Function();
typedef FetchFilteredShelters = Future<List<Shelter>> Function({String? q});
typedef IsLocationServiceEnabled = Future<bool> Function();
typedef CheckPermission = Future<LocationPermission> Function();
typedef RequestPermission = Future<LocationPermission> Function();
typedef GetCurrentPosition = Future<Position> Function();
typedef CacheShelters = Future<void> Function(List<Shelter> shelters);
typedef LoadCachedShelters = Future<CachedShelters?> Function();

Future<List<Shelter>> _defaultFetchFilteredShelters({String? q}) =>
    repo.fetchFilteredShelters(q: q);

Future<Position> _defaultGetCurrentPosition() =>
    Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

/// Holds every piece of mutable state the map screen used to keep in its
/// `State` object, plus the logic that used to live in its methods.
///
/// The `MapController` and the idle-debounce `Timer` are framework/lifecycle
/// objects tied to the widget tree, so they stay in `MapPage`'s State rather
/// than here — this class only holds data and pure state transitions.
class ShelterMapViewModel extends ChangeNotifier {
  ShelterMapViewModel({
    FetchAllShelters fetchAllShelters = repo.fetchAllShelters,
    FetchFilteredShelters fetchFilteredShelters = _defaultFetchFilteredShelters,
    IsLocationServiceEnabled isLocationServiceEnabled =
        Geolocator.isLocationServiceEnabled,
    CheckPermission checkPermission = Geolocator.checkPermission,
    RequestPermission requestPermission = Geolocator.requestPermission,
    GetCurrentPosition getCurrentPosition = _defaultGetCurrentPosition,
    CacheShelters cacheShelters = ShelterCache.save,
    LoadCachedShelters loadCachedShelters = ShelterCache.load,
  }) : _fetchAllShelters = fetchAllShelters,
       _fetchFilteredShelters = fetchFilteredShelters,
       _isLocationServiceEnabled = isLocationServiceEnabled,
       _checkPermission = checkPermission,
       _requestPermission = requestPermission,
       _getCurrentPosition = getCurrentPosition,
       _cacheShelters = cacheShelters,
       _loadCachedShelters = loadCachedShelters;

  final FetchAllShelters _fetchAllShelters;
  final FetchFilteredShelters _fetchFilteredShelters;
  final IsLocationServiceEnabled _isLocationServiceEnabled;
  final CheckPermission _checkPermission;
  final RequestPermission _requestPermission;
  final GetCurrentPosition _getCurrentPosition;
  final CacheShelters _cacheShelters;
  final LoadCachedShelters _loadCachedShelters;

  Timer? _messageDismissTimer;

  List<Shelter> _shelters = const [];
  List<Shelter> _visibleShelters = const [];
  LatLng? _visibleCenter;
  List<Shelter> _filteredShelters = const [];
  List<Shelter> _searchResults = const [];
  List<Shelter> _nearbyShelters = const [];
  String _searchQuery = '';

  Position? _currentPosition;
  Shelter? _selectedShelter;
  bool _showShelterDetails = false;

  Basemap _basemap = Basemap.emap;

  final Set<String> _selectedDisasterTypes = {};
  final Set<String> _selectedSpaceTypes = {};

  bool _isSearching = false;
  bool _isLoadingLocation = false;
  bool _showOutOfRangeWarning = false;
  String? _locationMessage;
  bool _isLocationSuccess = true;

  bool _isShowingCachedData = false;
  DateTime? _cachedAt;

  // ---------------------------------------------------------------------
  // Read-only state
  // ---------------------------------------------------------------------

  List<Shelter> get shelters => _shelters;
  List<Shelter> get visibleShelters => _visibleShelters;
  LatLng? get visibleCenter => _visibleCenter;
  List<Shelter> get filteredShelters => _filteredShelters;
  List<Shelter> get searchResults => _searchResults;
  List<Shelter> get nearbyShelters => _nearbyShelters;
  String get searchQuery => _searchQuery;

  /// Shelters that should currently be pinned on the map.
  List<Shelter> get markerShelters =>
      _isSearching && _filteredShelters.isNotEmpty
      ? _filteredShelters
      : _visibleShelters;

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
  bool get showOutOfRangeWarning => _showOutOfRangeWarning;
  String? get locationMessage => _locationMessage;
  bool get isLocationSuccess => _isLocationSuccess;
  bool get isShowingCachedData => _isShowingCachedData;
  DateTime? get cachedAt => _cachedAt;

  // ---------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------

  Future<void> loadShelters() async {
    try {
      _shelters = await _fetchAllShelters();
      _isShowingCachedData = false;
      _cachedAt = null;
      updateVisibleShelters(currentLatLng ?? MapConstants.taipeiCenter);
      unawaited(_cacheShelters(_shelters));
    } catch (_) {
      final cached = await _loadCachedShelters();
      if (cached != null && cached.shelters.isNotEmpty) {
        _shelters = cached.shelters;
        _isShowingCachedData = true;
        _cachedAt = cached.cachedAt;
        updateVisibleShelters(currentLatLng ?? MapConstants.taipeiCenter);
        return;
      }
      _locationMessage = '無法連線到伺服器,請確認後端已啟動';
      _isLocationSuccess = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------
  // Map viewport
  // ---------------------------------------------------------------------

  /// Recomputes which shelters fall inside the visible radius of [center].
  void updateVisibleShelters(LatLng center) {
    if (_shelters.isEmpty) return;
    _visibleCenter = center;
    _visibleShelters = [
      for (final shelter in locatableShelters(_shelters))
        if (calculateDistance(
              center.latitude,
              center.longitude,
              shelter.latitude!,
              shelter.longitude!,
            ) <=
            MapConstants.visibleRadiusMeters)
          shelter,
    ];
    notifyListeners();
  }

  /// Flags whether [center] has panned outside 臺北市, for the warning banner.
  void checkTaipeiRange(LatLng center) {
    final isOutOfRange = !MapConstants.isWithinTaipei(center);
    if (_showOutOfRangeWarning != isOutOfRange) {
      _showOutOfRangeWarning = isOutOfRange;
      notifyListeners();
    }
  }

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
      _filteredShelters = const [];
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
      _filteredShelters = const [];
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
    _recomputeFiltered();
  }

  /// Throws on network failure — the caller decides how to surface that
  /// (e.g. a SnackBar), matching the surrounding page's other API calls.
  Future<void> search(String query) async {
    _searchQuery = query;
    if (query.isEmpty) {
      _searchResults = const [];
      _recomputeFiltered();
      return;
    }
    _searchResults = await _fetchFilteredShelters(q: query);
    _recomputeFiltered();
  }

  void _recomputeFiltered() {
    final hasQuery = _searchQuery.isNotEmpty;
    final hasFilters =
        _selectedDisasterTypes.isNotEmpty || _selectedSpaceTypes.isNotEmpty;
    final source = hasQuery ? _searchResults : _shelters;

    _filteredShelters = (!hasFilters && !hasQuery)
        ? const []
        : applyShelterFilters(
            source,
            disasterTypes: _selectedDisasterTypes,
            spaceTypes: _selectedSpaceTypes,
            lat: _currentPosition?.latitude,
            lon: _currentPosition?.longitude,
          );
    notifyListeners();
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
      updateVisibleShelters(LatLng(position.latitude, position.longitude));
      _nearbyShelters = nearestShelters(
        _shelters,
        position.latitude,
        position.longitude,
      );

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
