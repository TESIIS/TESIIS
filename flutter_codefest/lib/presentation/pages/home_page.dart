import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/map/basemap.dart';
import 'package:flutter_codefest/core/utils/get_platform.dart';
import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/data/repositories/shelters_repository.dart';
import 'package:flutter_codefest/presentation/pages/user_manual_page.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  /// MapController throws if it is driven before the map has laid out.
  bool _isMapReady = false;

  static const LatLng _taipeiCenter = LatLng(25.0375, 121.5651);

  /// Radius of the "what is around here" circle, in metres.
  static const double _visibleRadiusMeters = 1500;

  /// How long the map must sit still before recomputing what is in range.
  static const Duration _idleDebounce = Duration(milliseconds: 300);

  /// Rough 臺北市 extent, used only to warn that the user has panned away.
  static const double _taipeiMinLat = 24.95;
  static const double _taipeiMaxLat = 25.21;
  static const double _taipeiMinLng = 121.45;
  static const double _taipeiMaxLng = 121.65;

  final TextEditingController _searchController = TextEditingController();

  bool _isSearching = false;
  bool _isLoadingLocation = false;
  List<Shelter> _shelters = [];
  List<Shelter> _filteredShelters = []; // 最終顯示的列表(經過搜尋和篩選)
  List<Shelter> _searchResults = []; // 搜尋結果(未經分類篩選)
  List<Shelter> _nearbyShelters = [];
  List<Shelter> _visibleShelters = []; // 地圖可視範圍內的避難所
  Position? _currentPosition;
  Shelter? _selectedShelter;
  bool _showShelterDetails = false;

  Basemap _basemap = Basemap.emap;

  List<Marker> _markers = const [];
  List<CircleMarker> _circles = const [];

  // 分類篩選狀態
  final Set<String> _selectedDisasterTypes =
      {}; // 災害類型: landslide, tsunami, earthquake, flood
  final Set<String> _selectedSpaceTypes = {}; // 空間類型: indoor, outdoor

  Timer? _idleTimer;
  bool _showOutOfRangeWarning = false;
  String? _locationMessage;
  bool _isLocationSuccess = true;

  // Shelters the coordinate table could not locate are deliberately kept in
  // the data rather than dropped: they exist, people can walk to them, and the
  // UI offers to open the address in an external map instead of silently
  // pretending they are not there. See _buildResultSummary and
  // _buildCoordinateNotice.

  @override
  void initState() {
    super.initState();
    _getAllShelters();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _getAllShelters() async {
    try {
      final shelters = await fetchAllShelters();
      if (!mounted) return;
      setState(() => _shelters = shelters);
      _updateVisibleShelters(_currentLatLng ?? _taipeiCenter);
    } catch (e) {
      debugPrint('載入避難所失敗: $e');
      if (mounted) {
        setState(() {
          _locationMessage = '無法連線到伺服器,請確認後端已啟動';
          _isLocationSuccess = false;
        });
      }
    }
  }

  LatLng? get _currentLatLng => _currentPosition == null
      ? null
      : LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

  // ---------------------------------------------------------------------
  // Map state
  // ---------------------------------------------------------------------

  /// Recomputes which shelters fall inside [_visibleRadiusMeters] of [center].
  void _updateVisibleShelters(LatLng center) {
    if (_shelters.isEmpty) return;

    final inRange = <Shelter>[
      for (final shelter in locatableShelters(_shelters))
        if (calculateDistance(
              center.latitude,
              center.longitude,
              shelter.latitude!,
              shelter.longitude!,
            ) <=
            _visibleRadiusMeters)
          shelter,
    ];

    if (!mounted) return;
    setState(() {
      _visibleShelters = inRange;
      _circles = [
        CircleMarker(
          point: center,
          radius: _visibleRadiusMeters,
          useRadiusInMeter: true,
          color: const Color(0xFF5AB4C5).withValues(alpha: 0.15),
          borderColor: const Color(0xFF5AB4C5).withValues(alpha: 0.5),
          borderStrokeWidth: 2,
        ),
      ];
      _updateMapMarkers();
    });
  }

  /// Rebuilds [_markers]. Call inside a setState.
  void _updateMapMarkers() {
    final shelters = _isSearching && _filteredShelters.isNotEmpty
        ? _filteredShelters
        : _visibleShelters;

    _markers = [
      for (final shelter in shelters)
        if (shelter.hasCoordinate) _shelterMarker(shelter),
      if (_currentLatLng != null) _currentLocationMarker(_currentLatLng!),
    ];
  }

  /// Marker colour encodes coordinate confidence, not category.
  ///
  /// About 20% of the located shelters sit at an interpolated street position
  /// rather than a surveyed point (see 座標精度 in the API). Showing that
  /// difference is more useful than colour-coding the facility type, which the
  /// detail panel already states in words.
  String _markerAsset(Shelter shelter, {required bool isSelected}) {
    if (isSelected) return 'assets/icons/red-refuge.svg';
    return shelter.isCoordinateExact
        ? 'assets/icons/green-refuge.svg'
        : 'assets/icons/yellow-refuge.svg';
  }

  Marker _shelterMarker(Shelter shelter) {
    final isSelected = _selectedShelter?.shelterId == shelter.shelterId;
    final size = isSelected ? 46.0 : 34.0;

    return Marker(
      key: ValueKey('shelter-${shelter.shelterId}-$isSelected'),
      point: LatLng(shelter.latitude!, shelter.longitude!),
      width: size,
      height: size,
      // Bottom-centre: the pin tip is the location, not the middle of the icon.
      alignment: Alignment.topCenter,
      child: Semantics(
        button: true,
        label:
            '${shelter.name}，${shelter.address}'
            '${shelter.isCoordinateExact ? '' : '，位置為概略值'}',
        child: GestureDetector(
          onTap: () => _onMarkerTapped(shelter),
          child: SvgPicture.asset(
            _markerAsset(shelter, isSelected: isSelected),
            width: size,
            height: size,
          ),
        ),
      ),
    );
  }

  Marker _currentLocationMarker(LatLng point) => Marker(
    key: const ValueKey('current-location'),
    point: point,
    width: 48,
    height: 48,
    child: Semantics(
      label: '我的位置',
      child: SvgPicture.asset(
        'assets/icons/now_location.svg',
        width: 48,
        height: 48,
      ),
    ),
  );

  void _onMarkerTapped(Shelter shelter) {
    setState(() {
      _selectedShelter = shelter;
      _showShelterDetails = true;
      _updateMapMarkers();
    });

    if (_isMapReady && shelter.hasCoordinate) {
      _mapController.move(
        LatLng(shelter.latitude!, shelter.longitude!),
        _mapController.camera.zoom,
      );
    }
  }

  void _onMapReady() {
    _isMapReady = true;
    _updateVisibleShelters(_currentLatLng ?? _taipeiCenter);
  }

  /// Fires continuously while the map moves, so the real work is debounced
  /// until it stops.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleDebounce, () {
      if (!mounted || _isSearching) return;
      _checkTaipeiRange(camera.center);
      _updateVisibleShelters(camera.center);
    });
  }

  void _checkTaipeiRange(LatLng center) {
    final isOutOfRange =
        center.latitude < _taipeiMinLat ||
        center.latitude > _taipeiMaxLat ||
        center.longitude < _taipeiMinLng ||
        center.longitude > _taipeiMaxLng;

    if (_showOutOfRangeWarning != isOutOfRange && mounted) {
      setState(() => _showOutOfRangeWarning = isOutOfRange);
    }
  }

  // ---------------------------------------------------------------------
  // Navigation hand-off
  // ---------------------------------------------------------------------

  /// Hands the selected shelter to whatever map app the device has.
  ///
  /// This is a plain https URL, so it needs no API key even though the app no
  /// longer embeds Google Maps.
  Future<void> _openGoogleMapsNavigation() async {
    final shelter = _selectedShelter;
    if (shelter == null) return;

    final String url;
    if (shelter.hasCoordinate) {
      final destination = '${shelter.latitude},${shelter.longitude}';
      url = _currentPosition != null
          ? 'https://www.google.com/maps/dir/?api=1'
                '&origin=${_currentPosition!.latitude},${_currentPosition!.longitude}'
                '&destination=$destination&travelmode=driving'
          : 'https://www.google.com/maps/search/?api=1&query=$destination';
    } else {
      // No coordinate: fall back to a text search on the address, which is the
      // whole reason these shelters stay in the list.
      final query = Uri.encodeComponent(
        '臺北市${shelter.district}${shelter.address}',
      );
      url = 'https://www.google.com/maps/search/?api=1&query=$query';
    }

    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: AppPlatform.isWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      if (!launched) _showSnackBar('無法開啟地圖應用程式');
    } catch (e) {
      debugPrint('開啟導航失敗: $e');
      _showSnackBar('開啟導航失敗');
    }
  }

  // ---------------------------------------------------------------------
  // Search and filtering
  // ---------------------------------------------------------------------

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _filteredShelters = [];
      } else if (_showShelterDetails) {
        _showShelterDetails = false;
        _selectedShelter = null;
      }
      _updateMapMarkers();
    });
  }

  void _toggleFilter(String filterType) {
    setState(() {
      if (_selectedDisasterTypes.contains(filterType) ||
          _selectedSpaceTypes.contains(filterType)) {
        _selectedDisasterTypes.remove(filterType);
        _selectedSpaceTypes.remove(filterType);
      } else if (const [
        'landslide',
        'tsunami',
        'earthquake',
        'flood',
      ].contains(filterType)) {
        _selectedDisasterTypes.add(filterType);
      } else if (const ['indoor', 'outdoor'].contains(filterType)) {
        _selectedSpaceTypes.add(filterType);
      }
    });
    _applyFilters();
  }

  bool _matchesSelectedFilters(Shelter shelter) {
    // Within a category the selections are ORed; the two categories are ANDed.
    final matchesDisaster =
        _selectedDisasterTypes.isEmpty ||
        _selectedDisasterTypes.any((type) {
          switch (type) {
            case 'landslide':
              return shelter.landslide == 'Y';
            case 'tsunami':
              return shelter.tsunami == 'Y';
            case 'earthquake':
              return shelter.earthquake == 'Y';
            case 'flood':
              return shelter.flood == 'Y';
            default:
              return false;
          }
        });

    final matchesSpace =
        _selectedSpaceTypes.isEmpty ||
        _selectedSpaceTypes.any((type) {
          switch (type) {
            case 'indoor':
              return shelter.indoor == 'Y';
            case 'outdoor':
              return shelter.outdoor == 'Y';
            default:
              return false;
          }
        });

    return matchesDisaster && matchesSpace;
  }

  void _applyFilters() {
    final hasQuery = _searchController.text.isNotEmpty;
    final hasFilters =
        _selectedDisasterTypes.isNotEmpty || _selectedSpaceTypes.isNotEmpty;

    final source = hasQuery ? _searchResults : _shelters;

    List<Shelter> result;
    if (!hasFilters) {
      // With neither a query nor a filter there is nothing to list; the map
      // already shows what is nearby.
      result = hasQuery ? source : const [];
    } else {
      result = source.where(_matchesSelectedFilters).toList();
    }

    // Sort by distance — without truncating.
    //
    // This used to call a helper whose `limit` defaulted to 5, so every
    // filtered and searched result was silently capped at five entries no
    // matter how many matched.
    final position = _currentPosition;
    if (position != null && result.isNotEmpty) {
      final located = sortedByDistance(
        result,
        position.latitude,
        position.longitude,
      );
      final unlocated = result.where((s) => !s.hasCoordinate);
      result = [...located, ...unlocated];
    }

    if (!mounted) return;
    setState(() {
      _filteredShelters = result;
      _updateMapMarkers();
    });
  }

  Future<void> _onSearch(String query) async {
    if (query.isEmpty) {
      _searchResults = [];
      _applyFilters();
      return;
    }

    try {
      _searchResults = await fetchFilteredShelters(q: query);
    } catch (e) {
      debugPrint('搜尋失敗: $e');
      _showSnackBar('搜尋失敗,請確認網路連線');
      return;
    }
    _applyFilters();
  }

  // ---------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------

  /// Ensures location services are on and permission is granted.
  /// Returns null on success, or a message to show the user.
  Future<String?> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return '請開啟定位服務';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return '定位權限被拒絕';
    }
    if (permission == LocationPermission.deniedForever) {
      return '定位權限被永久拒絕,請至設定中開啟';
    }
    return null;
  }

  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationMessage = null;
    });

    try {
      final problem = await _ensureLocationPermission();
      if (problem != null) {
        if (mounted) {
          setState(() {
            _locationMessage = problem;
            _isLocationSuccess = false;
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (position.latitude == 0.0 && position.longitude == 0.0) {
        if (mounted) {
          setState(() {
            _locationMessage = '取得位置失敗: 無效的座標';
            _isLocationSuccess = false;
          });
        }
        return;
      }
      if (!mounted) return;

      _currentPosition = position;
      final here = LatLng(position.latitude, position.longitude);

      if (_isMapReady) _mapController.move(here, 15.0);
      _updateVisibleShelters(here);

      _nearbyShelters = nearestShelters(
        _shelters,
        position.latitude,
        position.longitude,
      );

      setState(() {
        _locationMessage =
            '已定位: ${position.latitude.toStringAsFixed(4)}, '
            '${position.longitude.toStringAsFixed(4)}';
        _isLocationSuccess = true;
      });

      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isLocationSuccess && _locationMessage != null) {
          setState(() => _locationMessage = null);
        }
      });
    } catch (e) {
      debugPrint('取得位置失敗: $e');
      if (mounted) {
        setState(() {
          _locationMessage = '無法取得位置: $e';
          _isLocationSuccess = false;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Map widget
  // ---------------------------------------------------------------------

  Widget _buildMap() => FlutterMap(
    mapController: _mapController,
    options: MapOptions(
      initialCenter: _taipeiCenter,
      initialZoom: 12.0,
      minZoom: 8,
      maxZoom: 19,
      onMapReady: _onMapReady,
      onPositionChanged: _onPositionChanged,
      onTap: (_, __) {
        if (!_isSearching && !_showShelterDetails) return;
        setState(() {
          if (_isSearching) {
            _isSearching = false;
            _searchController.clear();
          }
          if (_showShelterDetails) {
            _showShelterDetails = false;
            _selectedShelter = null;
          }
          _updateMapMarkers();
        });
        FocusScope.of(context).unfocus();
      },
    ),
    children: [
      basemapTileLayer(_basemap),
      CircleLayer(circles: _circles),
      MarkerLayer(markers: _markers),
      // Required by the NLSC terms of use wherever their tiles are shown.
      const RichAttributionWidget(
        alignment: AttributionAlignment.bottomLeft,
        attributions: [
          TextSourceAttribution(Basemap.attribution, prependCopyright: false),
        ],
      ),
    ],
  );

  /// Basemap switcher. The three NLSC layers come free with the tile service.
  Widget _buildBasemapSwitcher() => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(8),
    elevation: 2,
    child: PopupMenuButton<Basemap>(
      tooltip: '切換底圖',
      icon: Icon(_basemap.icon, color: Colors.grey[800]),
      onSelected: (basemap) => setState(() => _basemap = basemap),
      itemBuilder: (context) => [
        for (final basemap in Basemap.values)
          PopupMenuItem(
            value: basemap,
            child: Row(
              children: [
                Icon(
                  basemap.icon,
                  size: 20,
                  color: basemap == _basemap
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[700],
                ),
                const SizedBox(width: 8),
                Text(basemap.label),
              ],
            ),
          ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // 防止鍵盤推擠介面
      body: SafeArea(
        child: Stack(
          children: [
            // 地圖（全螢幕）— 固定高度不受鍵盤影響
            Positioned.fill(child: _buildMap()),
            // 底圖切換
            Positioned(right: 16, bottom: 260, child: _buildBasemapSwitcher()),
            // 浮動工具列與建議列表
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: SizedBox(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 搜尋工具列
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white, // 背景色
                        borderRadius: BorderRadius.circular(12), // 圓角
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            spreadRadius: 1,
                            blurRadius: 6,
                            offset: const Offset(0, 3), // 下方陰影
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _isSearching
                                ? TextField(
                                    controller: _searchController,
                                    autofocus: false,
                                    style: const TextStyle(
                                      color: Color(0xFF5AB4C5),
                                      fontSize: 18,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '搜尋地點、避難所...',
                                      hintStyle: TextStyle(
                                        color: Color(0xFF93D4DF),
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 13,
                                        horizontal: 0,
                                      ),
                                      prefixIcon: Icon(
                                        Icons.search,
                                        color: Color(0xFF5AB4C5),
                                      ),
                                    ),
                                    onSubmitted: _onSearch,
                                    onChanged: _onSearch,
                                  )
                                : const Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      '避難設施資訊整合系統',
                                      style: TextStyle(
                                        color: Color(0xFF5AB4C5),
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isSearching ? Icons.close : Icons.search,
                              color: Color(0xFF5AB4C5),
                            ),
                            onPressed: _toggleSearch,
                          ),
                          if (!_isSearching) ...[
                            IconButton(
                              icon: _isLoadingLocation
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Color(0xFF5AB4C5),
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.my_location,
                                      color: Color(0xFF5AB4C5),
                                    ),
                              onPressed: _isLoadingLocation
                                  ? null
                                  : _getCurrentLocation,
                            ),
                            // IconButton(
                            //   icon: const Icon(
                            //     Icons.info_outline,
                            //     color: Color(0xFF5AB4C5),
                            //   ),
                            //   onPressed: () {
                            //     debugPrint('開啟設定');
                            //   },
                            // ),
                          ],
                        ],
                      ),
                    ),

                    // 超出範圍警告
                    if (_showOutOfRangeWarning)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.orange.shade400,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              spreadRadius: 1,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange.shade700,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '目前位置超出台北市範圍，避難所資料僅限台北市',
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 定位訊息
                    if (_locationMessage != null)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: _isLocationSuccess
                              ? Colors.green.shade100
                              : Colors.red.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isLocationSuccess
                                ? Colors.green.shade400
                                : Colors.red.shade400,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              spreadRadius: 1,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isLocationSuccess
                                  ? Icons.check_circle_rounded
                                  : Icons.error_rounded,
                              color: _isLocationSuccess
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _locationMessage!,
                                style: TextStyle(
                                  color: _isLocationSuccess
                                      ? Colors.green.shade900
                                      : Colors.red.shade900,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 桌面版提醒
                    if (MediaQuery.of(context).size.width > 600)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.shade300,
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              spreadRadius: 1,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.phone_android,
                              color: Colors.blue.shade700,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '建議使用手機比例以獲得最佳體驗',
                                style: TextStyle(
                                  color: Colors.blue.shade900,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 分類篩選按鈕
                    if (_isSearching)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              spreadRadius: 1,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              children: [
                                _buildFilterChip(
                                  '土石流',
                                  'landslide',
                                  Icons.landscape,
                                ),
                                const SizedBox(width: 8),
                                _buildFilterChip('海嘯', 'tsunami', Icons.waves),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                  '地震',
                                  'earthquake',
                                  Icons.warning,
                                ),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                  '水災',
                                  'flood',
                                  Icons.water_drop,
                                ),
                                const SizedBox(width: 8),
                                _buildFilterChip('室內', 'indoor', Icons.home),
                                const SizedBox(width: 8),
                                _buildFilterChip('室外', 'outdoor', Icons.park),
                              ],
                            ),
                            // 左側漸變
                            Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 20,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Colors.white,
                                      Colors.white.withValues(alpha: 0),
                                    ],
                                  ),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(12),
                                    bottomLeft: Radius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                            // 右側漸變
                            Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              child: Container(
                                width: 20,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerRight,
                                    end: Alignment.centerLeft,
                                    colors: [
                                      Colors.white,
                                      Colors.white.withValues(alpha: 0),
                                    ],
                                  ),
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 自動完成建議列表
                    if (_isSearching)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.of(context).size.height *
                              0.6, // 使用螢幕高度的60%,確保可以顯示更多結果
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              spreadRadius: 1,
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Builder(
                          builder: (context) {
                            // 決定要顯示的列表
                            final bool hasFilters =
                                _selectedDisasterTypes.isNotEmpty ||
                                _selectedSpaceTypes.isNotEmpty;
                            final bool hasSearchText =
                                _searchController.text.isNotEmpty;

                            List<Shelter> displayList;

                            if (hasFilters || hasSearchText) {
                              // 有篩選條件或搜尋文字時,顯示 _filteredShelters
                              displayList = _filteredShelters;
                            } else {
                              // 沒有任何條件時,顯示附近的避難所
                              displayList = _nearbyShelters;
                            }

                            // 空狀態檢查
                            if (displayList.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.search_off,
                                        size: 48,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '找不到相似的結果',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        hasFilters ? '請嘗試調整篩選條件' : '請嘗試其他關鍵字',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            // 顯示列表（結果數 + 無座標提示）
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildResultSummary(displayList),
                                Flexible(
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    itemCount: displayList.length,
                                    separatorBuilder: (context, index) =>
                                        const Divider(
                                          height: 1,
                                          indent: 16,
                                          endIndent: 16,
                                        ),
                                    itemBuilder: (context, index) {
                                      final shelter = displayList[index];
                                      // 計算距離
                                      final String distanceText;
                                      if (!shelter.hasCoordinate) {
                                        // 這些設施確實存在,只是門牌不是標準地址,
                                        // 座標表定位不到 — 仍然列出並提供外部地圖。
                                        distanceText = '尚無座標';
                                      } else if (_currentPosition == null) {
                                        distanceText = '距離未知';
                                      } else {
                                        final meters = distanceToShelter(
                                          shelter,
                                          _currentPosition!.latitude,
                                          _currentPosition!.longitude,
                                        );
                                        distanceText =
                                            '距離 ${(meters / 1000).toStringAsFixed(2)} km';
                                      }

                                      // 檢查是否為選中的避難所
                                      final isSelected =
                                          _selectedShelter?.name ==
                                          shelter.name;

                                      return ListTile(
                                        dense: true,
                                        tileColor: isSelected
                                            ? const Color(0xFFE3F2F4)
                                            : null, // 被選中時改變背景色
                                        leading: Icon(
                                          Icons.location_on,
                                          color: isSelected
                                              ? const Color(0xFF3A8A9A)
                                              : const Color(0xFF5AB4C5),
                                          size: 20,
                                        ),
                                        title: Text(
                                          shelter.name,
                                          style: TextStyle(
                                            color: isSelected
                                                ? const Color(0xFF3A8A9A)
                                                : const Color(0xFF5AB4C5),
                                            fontSize: 16,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              shelter.address,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? const Color(0xFF3A8A9A)
                                                    : const Color(0xFF93D4DF),
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              distanceText,
                                              style: TextStyle(
                                                color: isSelected
                                                    ? const Color(0xFF3A8A9A)
                                                    : const Color(0xFF93D4DF),
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                        trailing: Icon(
                                          Icons.arrow_forward_ios,
                                          color: isSelected
                                              ? const Color(0xFF3A8A9A)
                                              : const Color(0xFF93D4DF),
                                          size: 16,
                                        ),
                                        onTap: () {
                                          debugPrint('選擇避難所: ${shelter.name}');
                                          // 調用 _onMarkerTapped 來顯示底部資訊面板
                                          _onMarkerTapped(shelter);
                                          // 關閉搜尋模式
                                          setState(() {
                                            _isSearching = false;
                                            _searchController.clear();
                                          });
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 底部避難所詳細資訊面板
            if (_showShelterDetails && _selectedShelter != null)
              DraggableScrollableSheet(
                initialChildSize: 0.35, // 初始高度 35%
                minChildSize: 0.35, // 最小高度 35%
                maxChildSize: 0.8, // 最大高度 80%
                snap: true, // 啟用吸附效果
                snapSizes: const [0.35, 0.8], // 吸附點
                builder: (BuildContext context, ScrollController scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // 拖動指示器
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),

                        // 避難所詳細資訊
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            children: [
                              // 標題和關閉按鈕
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on,
                                    color: Color(0xFF5AB4C5),
                                    size: 28,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedShelter!.name,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF5AB4C5),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      setState(() {
                                        _showShelterDetails = false;
                                        _selectedShelter = null;
                                        // 重新繪製所有 markers 以恢復顏色
                                        _updateMapMarkers();
                                      });
                                    },
                                  ),
                                ],
                              ),
                              const Divider(height: 24),

                              // 導航按鈕 (移到頂部)
                              if (_currentPosition != null &&
                                  _selectedShelter!.latitude != null &&
                                  _selectedShelter!.longitude != null) ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _openGoogleMapsNavigation,
                                    icon: const Icon(
                                      Icons.navigation,
                                      color: Colors.white,
                                    ),
                                    label: Text(
                                      '開始導航 (${(_calculateDistance() / 1000).toStringAsFixed(2)} 公里)',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF5AB4C5),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              // 座標品質提示
                              _buildCoordinateNotice(_selectedShelter!),

                              // 基本資訊
                              _buildInfoRow('地址', _selectedShelter!.address),
                              _buildInfoRow('行政區', _selectedShelter!.district),
                              _buildInfoRow('里', _selectedShelter!.village),
                              _buildInfoRow(
                                '郵遞區號',
                                _selectedShelter!.postalCode,
                              ),

                              // 只在至少有一種災害類型時顯示
                              if (_selectedShelter!.flood == 'Y' ||
                                  _selectedShelter!.earthquake == 'Y' ||
                                  _selectedShelter!.landslide == 'Y' ||
                                  _selectedShelter!.tsunami == 'Y') ...[
                                const SizedBox(height: 16),
                                const Text(
                                  '災害類型',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF5AB4C5),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (_selectedShelter!.flood == 'Y')
                                      _buildDisasterChip(
                                        '水災',
                                        Icons.water_drop,
                                      ),
                                    if (_selectedShelter!.earthquake == 'Y')
                                      _buildDisasterChip('地震', Icons.warning),
                                    if (_selectedShelter!.landslide == 'Y')
                                      _buildDisasterChip(
                                        '土石流',
                                        Icons.landscape,
                                      ),
                                    if (_selectedShelter!.tsunami == 'Y')
                                      _buildDisasterChip('海嘯', Icons.waves),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                              const Text(
                                '設施資訊',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF5AB4C5),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildInfoRow('類型', _selectedShelter!.type),
                              _buildInfoRow(
                                '收容人數',
                                '${_selectedShelter!.capacity} 人',
                              ),
                              if (_selectedShelter!.area.isNotEmpty)
                                _buildInfoRow(
                                  '面積',
                                  // 上游此欄位偶爾是中文說明("俟搬遷後重新評估"),
                                  // 直接加單位會變成 "俟搬遷後重新評估 ㎡"。
                                  double.tryParse(
                                            _selectedShelter!.area.replaceAll(
                                              ',',
                                              '',
                                            ),
                                          ) !=
                                          null
                                      ? '${_selectedShelter!.area} ㎡'
                                      : _selectedShelter!.area,
                                ),
                              _buildInfoRow(
                                '室內空間',
                                _selectedShelter!.indoor == 'Y' ? '有' : '無',
                              ),
                              _buildInfoRow(
                                '室外空間',
                                _selectedShelter!.outdoor == 'Y' ? '有' : '無',
                              ),
                              _buildInfoRow(
                                '無障礙設施',
                                _selectedShelter!.accessible == 'Y' ? '有' : '無',
                              ),
                              _buildInfoRow(
                                '救濟站',
                                _selectedShelter!.reliefStation == 'Y'
                                    ? '是'
                                    : '否',
                              ),

                              const SizedBox(height: 16),
                              const Text(
                                '聯絡資訊',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF5AB4C5),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                '聯絡人',
                                _selectedShelter!.contactName,
                              ),
                              _buildInfoRow(
                                '聯絡電話',
                                _selectedShelter!.contactPhone,
                              ),
                              _buildInfoRow(
                                '管理人',
                                _selectedShelter!.managerName,
                              ),
                              _buildInfoRow(
                                '管理人電話',
                                _selectedShelter!.managerPhone,
                              ),

                              if (_selectedShelter!.remarks.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                const Text(
                                  '備註',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF5AB4C5),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _selectedShelter!.remarks,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            // 使用手冊按鈕 - 在底部面板上方
            if (_currentPosition != null &&
                _nearbyShelters.isNotEmpty &&
                !_showShelterDetails &&
                !_isSearching)
              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).size.height * 0.6 + 16,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 6,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const UserManualPage(),
                        ),
                      );
                    },
                    customBorder: const CircleBorder(),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      child: const Icon(
                        Icons.menu_book,
                        color: Color(0xFF5AB4C5),
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),

            // 底部常駐面板與底部填色 (顯示最近的設施)
            if (_currentPosition != null &&
                _nearbyShelters.isNotEmpty &&
                !_showShelterDetails &&
                !_isSearching) ...[
              // 底部往上提升後，補一個白色背景避免透明露出地圖
              Positioned(
                bottom: AppPlatform.isWeb ? -16 : 0,
                left: 0,
                right: 0,
                child: Container(
                  height:
                      MediaQuery.of(context).size.height * 0.10 +
                      (AppPlatform.isWeb ? 16 : 0),
                  color: Colors.white,
                ),
              ),
              Positioned(
                bottom:
                    MediaQuery.of(context).size.height * 0.10 +
                    (AppPlatform.isWeb ? -16 : 0),
                left: 0,
                right: 0,
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.25,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 指示器
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // 標題
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Icon(
                              Icons.near_me,
                              color: Color(0xFF5AB4C5),
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '最近的避難設施',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF5AB4C5),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // 最近設施資訊
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 設施名稱
                              Text(
                                _nearbyShelters[0].name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),

                              // 地址
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _nearbyShelters[0].address,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // 距離
                              Row(
                                children: [
                                  const Icon(
                                    Icons.straighten,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    () {
                                      final shelter = _nearbyShelters[0];
                                      if (!shelter.hasCoordinate) {
                                        return '尚無座標';
                                      }
                                      final meters = distanceToShelter(
                                        shelter,
                                        _currentPosition!.latitude,
                                        _currentPosition!.longitude,
                                      );
                                      return '距離 ${(meters / 1000).toStringAsFixed(2)} 公里';
                                    }(),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),

                              // 災害類型和空間類型標籤
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (_nearbyShelters[0].flood == 'Y')
                                    _buildSmallChip('水災', Icons.water_drop),
                                  if (_nearbyShelters[0].earthquake == 'Y')
                                    _buildSmallChip('地震', Icons.warning),
                                  if (_nearbyShelters[0].landslide == 'Y')
                                    _buildSmallChip('土石流', Icons.landscape),
                                  if (_nearbyShelters[0].tsunami == 'Y')
                                    _buildSmallChip('海嘯', Icons.waves),
                                  if (_nearbyShelters[0].indoor == 'Y')
                                    _buildSmallChip('室內', Icons.home),
                                  if (_nearbyShelters[0].outdoor == 'Y')
                                    _buildSmallChip('室外', Icons.park),
                                ],
                              ),

                              const Spacer(),

                              // 導航和詳情按鈕
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        // 設定為選中的避難所並開啟導航
                                        _selectedShelter = _nearbyShelters[0];
                                        _openGoogleMapsNavigation();
                                      },
                                      icon: const Icon(
                                        Icons.navigation,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      label: const Text(
                                        '開始導航',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF5AB4C5,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton(
                                    onPressed: () {
                                      _onMarkerTapped(_nearbyShelters[0]);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                        horizontal: 20,
                                      ),
                                      side: const BorderSide(
                                        color: Color(0xFF5AB4C5),
                                        width: 2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      '詳情',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF5AB4C5),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 構建資訊行
  Widget _buildInfoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // 構建災害類型標籤
  Widget _buildDisasterChip(String label, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 18, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: const Color(0xFF5AB4C5),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  // 構建小型標籤(用於底部常駐面板)
  Widget _buildSmallChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF5AB4C5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // 構建篩選按鈕
  Widget _buildFilterChip(String label, String filterType, IconData icon) {
    final bool isSelected =
        _selectedDisasterTypes.contains(filterType) ||
        _selectedSpaceTypes.contains(filterType);

    return InkWell(
      onTap: () => _toggleFilter(filterType),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF5AB4C5) : Colors.white,
          border: Border.all(color: const Color(0xFF5AB4C5), width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : const Color(0xFF5AB4C5),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF5AB4C5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Result count, plus a note when some results cannot be mapped.
  ///
  /// Without this the list and the map disagree — a search can return 30 hits
  /// while only 28 pins appear — and the user has no way to know why.
  Widget _buildResultSummary(List<Shelter> displayList) {
    final missing = displayList.where((s) => !s.hasCoordinate).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text(
            '共 ${displayList.length} 筆',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          if (missing > 0) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.location_off_outlined,
              size: 14,
              color: Colors.orange[700],
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '其中 $missing 筆尚無座標,不會出現在地圖上',
                style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Tells the user how much to trust the position we are showing.
  ///
  /// The upstream dataset carries no coordinates at all — every point is
  /// joined in from other government datasets. About 5% of shelters cannot be
  /// located and roughly a fifth of the rest sit at an interpolated street
  /// position. Stating that is more honest than a map that looks uniformly
  /// precise, and it is exactly the sort of thing someone needs to know before
  /// walking somewhere during an emergency.
  Widget _buildCoordinateNotice(Shelter shelter) {
    final (String message, IconData icon, Color color) = switch (shelter) {
      _ when !shelter.hasCoordinate => (
        '此設施尚無精確座標,地圖上不會顯示標記。可用上方按鈕以地址開啟外部地圖。',
        Icons.location_off_outlined,
        Colors.orange,
      ),
      _ when !shelter.isCoordinateExact => (
        '此位置為概略值(依鄰近門牌推估),實際入口可能相差數十公尺。',
        Icons.help_outline,
        Colors.amber,
      ),
      _ => ('', Icons.check, Colors.transparent),
    };
    if (message.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  /// Distance to the selected shelter in metres, or 0 when it cannot be
  /// computed (no fix, nothing selected, or the shelter has no coordinate).
  double _calculateDistance() {
    final shelter = _selectedShelter;
    final position = _currentPosition;
    if (position == null || shelter == null || !shelter.hasCoordinate) {
      return 0.0;
    }
    return distanceToShelter(shelter, position.latitude, position.longitude);
  }
}
