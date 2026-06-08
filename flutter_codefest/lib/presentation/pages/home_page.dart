import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/utils/get_platform.dart';
import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/data/repositories/shelters_repository.dart';
import 'package:flutter_codefest/presentation/pages/user_manual_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;

  static const LatLng _taipeiCenter = LatLng(25.0375, 121.5651);
  final TextEditingController _searchController = TextEditingController();

  bool _isSearching = false;
  bool _isLoadingLocation = false;
  List<Shelter> _shelters = [];
  List<Shelter> _filteredShelters = []; // 最終顯示的列表(經過搜尋和篩選)
  List<Shelter> _searchResults = []; // 搜尋結果(未經分類篩選)
  List<Shelter> _nearbyShelters = [];
  List<Shelter> _visibleShelters = []; // 地圖可視範圍內的避難所
  Position? _currentPosition;
  final Set<Circle> _circles = {}; // 地圖上的圓圈(1.5km範圍遮罩)
  BitmapDescriptor? _currentLocationIcon; // 快取位置圖標
  Shelter? _selectedShelter; // 當前選中的避難所
  bool _showShelterDetails = false; // 是否顯示避難所詳細資訊
  final String assetName = 'assets/icons/now_location.svg';
  late final Widget svg = SvgPicture.asset(assetName, width: 48, height: 48);

  // 分類篩選狀態
  final Set<String> _selectedDisasterTypes =
      {}; // 災害類型: landslide, tsunami, earthquake, flood
  final Set<String> _selectedSpaceTypes = {}; // 空間類型: indoor, outdoor

  // 防抖控制 - 避免過於頻繁的更新
  bool _isUpdating = false;
  DateTime? _lastUpdateTime;
  bool _showOutOfRangeWarning = false; // 是否顯示超出範圍警告
  String? _locationMessage; // 定位訊息
  bool _isLocationSuccess = true; // 定位是否成功(決定顏色)

  @override
  void initState() {
    super.initState();
    // 應用程式啟動時自動獲取位置
    _getAllShelters();
    _getCurrentLocation();
    _loadLocationIcon(); // 預先載入位置圖標
  }

  // 預先載入位置圖標
  Future<void> _loadLocationIcon() async {
    try {
      _currentLocationIcon = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/icons/now_location.png',
      );
    } catch (e) {
      debugPrint('載入位置圖標失敗: $e');
    }
  }

  _getAllShelters() async {
    _shelters = await fetchAllShelters();
    setState(() {});
  }

  // 更新地圖中心點附近 1.5km 範圍內的避難所
  void _updateVisibleShelters(LatLng center) async {
    // 防抖控制 - 如果距離上次更新不到 500ms,則跳過
    final now = DateTime.now();
    if (_lastUpdateTime != null &&
        now.difference(_lastUpdateTime!).inMilliseconds < 300) {
      return;
    }

    if (_isUpdating || _shelters.isEmpty) return;
    _isUpdating = true;
    _lastUpdateTime = now;

    const double radiusInMeters = 1500; // 1.5 公里

    List<Shelter> sheltersInRange = [];

    for (var shelter in _shelters) {
      if (shelter.latitude == null || shelter.longitude == null) continue;

      try {
        final double lat = shelter.latitude is double
            ? shelter.latitude
            : double.parse(shelter.latitude.toString());
        final double lon = shelter.longitude is double
            ? shelter.longitude
            : double.parse(shelter.longitude.toString());

        if (lat == 0.0 || lon == 0.0) continue;

        // 計算與地圖中心的距離
        double distance = Geolocator.distanceBetween(
          center.latitude,
          center.longitude,
          lat,
          lon,
        );

        // 如果在 1.5km 範圍內,加入列表
        if (distance <= radiusInMeters) {
          sheltersInRange.add(shelter);
        }
      } catch (e) {
        continue;
      }
    }

    // 更新1.5km範圍的圓圈遮罩
    _circles.clear();
    _circles.add(
      Circle(
        circleId: const CircleId('search_radius'),
        center: center,
        radius: radiusInMeters,
        fillColor: const Color(0xFF5AB4C5).withOpacity(0.15), // 半透明藍色
        strokeColor: const Color(0xFF5AB4C5).withOpacity(0.5),
        strokeWidth: 2,
      ),
    );

    if (mounted) {
      setState(() {
        _visibleShelters = sheltersInRange;
        // 更新地圖標記
        _updateMapMarkers();
      });
    }

    _isUpdating = false;

    debugPrint('地圖中心: ${center.latitude}, ${center.longitude}');
    debugPrint('範圍內避難所數量: ${sheltersInRange.length}');
  }

  // 更新地圖上的標記
  void _updateMapMarkers() {
    // 清除所有標記
    _markers.clear();

    // 如果有目前位置,添加目前位置標記
    if (_currentPosition != null) {
      _addCurrentLocationMarker();
    }

    // 如果在搜尋模式,顯示搜尋結果
    if (_isSearching && _filteredShelters.isNotEmpty) {
      for (final shelter in _filteredShelters) {
        _addShelterMarker(shelter);
      }
    } else {
      // 否則顯示可視範圍內的避難所
      for (final shelter in _visibleShelters) {
        _addShelterMarker(shelter);
      }
    }
  }

  // 添加避難所標記
  void _addShelterMarker(Shelter shelter) {
    if (shelter.latitude == null || shelter.longitude == null) return;

    try {
      final double lat = shelter.latitude is double
          ? shelter.latitude
          : double.parse(shelter.latitude.toString());
      final double lon = shelter.longitude is double
          ? shelter.longitude
          : double.parse(shelter.longitude.toString());

      if (lat == 0.0 || lon == 0.0) return;

      // 檢查是否為選中的避難所
      final isSelected = _selectedShelter?.shelterId == shelter.shelterId;

      _markers.add(
        Marker(
          markerId: MarkerId(shelter.shelterId),
          position: LatLng(lat, lon),
          onTap: () => _onMarkerTapped(shelter), // 點擊標記時顯示詳細資訊
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isSelected
                ? BitmapDescriptor
                      .hueOrange // 被選中時使用橘色
                : BitmapDescriptor.hueAzure, // 預設使用藍色標記
          ),
        ),
      );
    } catch (e) {
      debugPrint('添加標記失敗: $e');
    }
  }

  // 處理標記點擊事件
  void _onMarkerTapped(Shelter shelter) {
    setState(() {
      _selectedShelter = shelter;
      _showShelterDetails = true;
      // 重新繪製所有 markers 以更新顏色
      _updateMapMarkers();
    });

    // 將地圖中心移動到選中的避難所
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(
            shelter.latitude is double
                ? shelter.latitude
                : double.parse(shelter.latitude.toString()),
            shelter.longitude is double
                ? shelter.longitude
                : double.parse(shelter.longitude.toString()),
          ),
        ),
      );
    }
  }

  // 打開 Google Maps 導航
  Future<void> _openGoogleMapsNavigation() async {
    if (_selectedShelter == null) return;

    try {
      final lat = _selectedShelter!.latitude is double
          ? _selectedShelter!.latitude
          : double.parse(_selectedShelter!.latitude.toString());
      final lon = _selectedShelter!.longitude is double
          ? _selectedShelter!.longitude
          : double.parse(_selectedShelter!.longitude.toString());

      // 構建 Google Maps 導航 URL
      // 如果有目前位置,使用 dir (directions) 模式,否則只顯示目的地
      String url;
      if (_currentPosition != null) {
        // 從目前位置導航到目的地
        url =
            'https://www.google.com/maps/dir/?api=1&origin=${_currentPosition!.latitude},${_currentPosition!.longitude}&destination=$lat,$lon&travelmode=driving';
      } else {
        // 只顯示目的地
        url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lon';
      }

      final Uri uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: AppPlatform.isWeb
              ? LaunchMode.platformDefault
              : LaunchMode.externalApplication,
        );
      } else {
        _showSnackBar('無法開啟 Google Maps');
      }
    } catch (e) {
      debugPrint('開啟導航失敗: $e');
      _showSnackBar('開啟導航失敗');
    }
  }

  // 添加目前位置標記
  void _addCurrentLocationMarker() {
    if (_currentPosition == null) return;

    try {
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          infoWindow: const InfoWindow(title: '我的位置', snippet: '您目前的位置'),
          icon: _currentLocationIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, 0.5),
        ),
      );
    } catch (e) {
      debugPrint('添加目前位置標記失敗: $e');
    }
  }

  final Set<Marker> _markers = {};

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _filteredShelters = []; // 清空搜尋結果
        _updateMapMarkers(); // 重新顯示範圍內的避難所
      } else {
        // 當搜尋欄被點開時,關閉資訊欄
        if (_showShelterDetails) {
          _showShelterDetails = false;
          _selectedShelter = null;
          _updateMapMarkers();
        }
      }
    });
  }

  // 切換分類篩選
  void _toggleFilter(String filterType) {
    setState(() {
      if (_selectedDisasterTypes.contains(filterType) ||
          _selectedSpaceTypes.contains(filterType)) {
        _selectedDisasterTypes.remove(filterType);
        _selectedSpaceTypes.remove(filterType);
      } else {
        if ([
          'landslide',
          'tsunami',
          'earthquake',
          'flood',
        ].contains(filterType)) {
          _selectedDisasterTypes.add(filterType);
        } else if (['indoor', 'outdoor'].contains(filterType)) {
          _selectedSpaceTypes.add(filterType);
        }
      }
      _applyFilters();
    });
  }

  // 應用篩選條件
  void _applyFilters() async {
    // 確定資料來源
    List<Shelter> sourceList;

    if (_searchController.text.isEmpty) {
      // 沒有搜尋文字,從所有避難所開始篩選
      sourceList = _shelters;
    } else {
      // 有搜尋文字,從搜尋結果開始
      sourceList = _searchResults;
    }

    // 如果沒有篩選條件
    if (_selectedDisasterTypes.isEmpty && _selectedSpaceTypes.isEmpty) {
      // 如果沒有搜尋文字且沒有篩選條件,顯示附近的避難所
      if (_searchController.text.isEmpty) {
        setState(() {
          _filteredShelters = [];
        });
      } else {
        setState(() {
          _filteredShelters = sourceList;
        });
      }
      return;
    }

    // 應用篩選條件
    List<Shelter> filtered = sourceList.where((shelter) {
      bool matchDisaster = _selectedDisasterTypes.isEmpty;
      bool matchSpace = _selectedSpaceTypes.isEmpty;

      // 檢查災害類型 - 只要符合任一選中的災害類型即可
      if (_selectedDisasterTypes.isNotEmpty) {
        matchDisaster = _selectedDisasterTypes.any((type) {
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
      }

      // 檢查空間類型 - 只要符合任一選中的空間類型即可
      if (_selectedSpaceTypes.isNotEmpty) {
        matchSpace = _selectedSpaceTypes.any((type) {
          switch (type) {
            case 'indoor':
              return shelter.indoor == 'Y';
            case 'outdoor':
              return shelter.outdoor == 'Y';
            default:
              return false;
          }
        });
      }

      return matchDisaster && matchSpace;
    }).toList();

    // 如果有當前位置,按距離排序
    if (_currentPosition != null) {
      filtered = await getNearestShelters(filtered, _currentPosition!);
    }

    setState(() {
      _filteredShelters = filtered;
    });
  }

  void _onSearch(String query) async {
    // 搜尋框清空
    if (query.isEmpty) {
      _searchResults = [];
      // 重新應用篩選(會根據篩選條件決定顯示什麼)
      _applyFilters();
      setState(() {
        _updateMapMarkers();
      });
      return;
    }

    // 執行搜尋
    List<Shelter> searchResults = await fetchFilteredShelters(q: query);

    if (_currentPosition != null) {
      searchResults = await getNearestShelters(
        searchResults,
        _currentPosition!,
      );
    }

    // 儲存搜尋結果
    _searchResults = searchResults;

    // 應用分類篩選
    _applyFilters();

    setState(() {
      _updateMapMarkers(); // 更新為搜尋結果的標記
    });

    debugPrint('搜尋: $query');
    debugPrint('找到 ${_filteredShelters.length} 個避難所');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    // 初始化時,如果有預設中心點,更新可視範圍
    if (_currentPosition != null) {
      _updateVisibleShelters(
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      );
    } else {
      _updateVisibleShelters(_taipeiCenter);
    }
  }

  // 當地圖停止移動時觸發
  void _onCameraIdle() async {
    if (_mapController == null || _isSearching) return;

    try {
      // 取得當前地圖中心點
      LatLngBounds visibleRegion = await _mapController!.getVisibleRegion();
      LatLng center = LatLng(
        (visibleRegion.northeast.latitude + visibleRegion.southwest.latitude) /
            2,
        (visibleRegion.northeast.longitude +
                visibleRegion.southwest.longitude) /
            2,
      );

      // 檢查是否超出台北市範圍
      _checkTaipeiRange(center);

      // 只在非搜尋模式下更新範圍內的避難所
      _updateVisibleShelters(center);
    } catch (e) {
      debugPrint('更新可視範圍失敗: $e');
    }
  }

  // 檢查是否在台北市範圍內
  void _checkTaipeiRange(LatLng center) {
    // 台北市大致邊界
    const double minLat = 24.95; // 最南
    const double maxLat = 25.21; // 最北
    const double minLng = 121.45; // 最西
    const double maxLng = 121.65; // 最東

    bool isOutOfRange =
        center.latitude < minLat ||
        center.latitude > maxLat ||
        center.longitude < minLng ||
        center.longitude > maxLng;

    // 更新警告狀態
    if (_showOutOfRangeWarning != isOutOfRange) {
      setState(() {
        _showOutOfRangeWarning = isOutOfRange;
      });
    }
  }

  // 檢查定位權限
  Future<void> _checkLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 檢查定位服務是否開啟
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('請開啟定位服務');
      return;
    }

    // 檢查權限
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('定位權限被拒絕');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar('定位權限被永久拒絕,請至設定中開啟');
      return;
    }
  }

  // 取得目前位置
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationMessage = null; // 清除舊訊息
    });

    try {
      // 檢查權限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _checkLocationPermission();
        permission = await Geolocator.checkPermission();

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          setState(() {
            _locationMessage = '無法取得定位權限';
            _isLocationSuccess = false;
          });
          return;
        }
      }

      // 取得目前位置
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _currentPosition = position;

      if (position.latitude == 0.0 ||
          position.longitude == 0.0 ||
          position.latitude as dynamic == null ||
          position.longitude as dynamic == null) {
        setState(() {
          _locationMessage = '取得位置失敗: 無效的座標';
          _isLocationSuccess = false;
        });
        return;
      }

      setState(() {
        _updateMapMarkers(); // 更新標記
      });

      // 移動地圖到目前位置
      if (_mapController != null) {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(position.latitude, position.longitude),
              zoom: 15.0,
            ),
          ),
        );

        // 更新以目前位置為中心的 1.5km 範圍避難所
        _updateVisibleShelters(LatLng(position.latitude, position.longitude));
      }

      // 取得所有附近的避難所(不限制數量,由近到遠排序)
      _nearbyShelters = await getNearestShelters(_shelters, position);

      setState(() {
        _locationMessage =
            '已定位: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        _isLocationSuccess = true;
      });

      debugPrint('目前位置: ${position.latitude}, ${position.longitude}');

      // 3秒後自動隱藏成功訊息
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isLocationSuccess && _locationMessage != null) {
          setState(() {
            _locationMessage = null;
          });
        }
      });
    } catch (e) {
      debugPrint('取得位置失敗: $e');
      setState(() {
        _locationMessage = '無法取得位置: $e';
        _isLocationSuccess = false;
      });
    } finally {
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  // 顯示提示訊息
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // 防止鍵盤推擠介面
      body: SafeArea(
        child: Stack(
          children: [
            // Google Map (全螢幕) - 固定高度不受鍵盤影響
            Positioned.fill(
              child: GoogleMap(
                onMapCreated: _onMapCreated,
                onCameraIdle: _onCameraIdle,
                onTap: (LatLng position) {
                  // 點擊地圖空白處收起搜尋欄和資訊頁
                  if (_isSearching || _showShelterDetails) {
                    setState(() {
                      if (_isSearching) {
                        _isSearching = false;
                        _searchController.clear();
                      }
                      if (_showShelterDetails) {
                        _showShelterDetails = false;
                        _selectedShelter = null;
                        _updateMapMarkers();
                      }
                    });
                    // 收起鍵盤
                    FocusScope.of(context).unfocus();
                  }
                },
                initialCameraPosition: CameraPosition(
                  target: _taipeiCenter,
                  zoom: 12.0,
                ),
                markers: _markers,
                circles: _circles, // 添加圓圈遮罩
                mapType: MapType.normal,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
                compassEnabled: true,
                mapToolbarEnabled: true,
              ),
            ), // Positioned.fill
            // 浮動工具列與建議列表（Web 平台視圖上方需要攔截指標）
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: PointerInterceptor(
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

                            // 顯示列表
                            return ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 8),
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
                                String distanceText = '距離未知';
                                if (_currentPosition != null &&
                                    shelter.latitude != null &&
                                    shelter.longitude != null) {
                                  double distanceInMeters =
                                      Geolocator.distanceBetween(
                                        _currentPosition!.latitude,
                                        _currentPosition!.longitude,
                                        shelter.latitude is double
                                            ? shelter.latitude
                                            : double.tryParse(
                                                    shelter.latitude.toString(),
                                                  ) ??
                                                  0.0,
                                        shelter.longitude is double
                                            ? shelter.longitude
                                            : double.tryParse(
                                                    shelter.longitude
                                                        .toString(),
                                                  ) ??
                                                  0.0,
                                      );
                                  double distanceInKm = distanceInMeters / 1000;
                                  distanceText =
                                      '距離 ${distanceInKm.toStringAsFixed(2)} km';
                                }

                                // 檢查是否為選中的避難所
                                final isSelected =
                                    _selectedShelter?.name == shelter.name;

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
                          color: Colors.black.withOpacity(0.2),
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
                              if (_selectedShelter!.area != null)
                                _buildInfoRow(
                                  '面積',
                                  '${_selectedShelter!.area} ㎡',
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
                        color: Colors.black.withOpacity(0.2),
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
                                      if (shelter.latitude != null &&
                                          shelter.longitude != null) {
                                        double
                                        distance = Geolocator.distanceBetween(
                                          _currentPosition!.latitude,
                                          _currentPosition!.longitude,
                                          shelter.latitude is double
                                              ? shelter.latitude
                                              : double.parse(
                                                  shelter.latitude.toString(),
                                                ),
                                          shelter.longitude is double
                                              ? shelter.longitude
                                              : double.parse(
                                                  shelter.longitude.toString(),
                                                ),
                                        );
                                        return '距離 ${(distance / 1000).toStringAsFixed(2)} 公里';
                                      }
                                      return '距離未知';
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

  // 計算到選中避難所的距離
  double _calculateDistance() {
    if (_currentPosition == null || _selectedShelter == null) return 0.0;

    final lat = _selectedShelter!.latitude is double
        ? _selectedShelter!.latitude
        : double.parse(_selectedShelter!.latitude.toString());
    final lon = _selectedShelter!.longitude is double
        ? _selectedShelter!.longitude
        : double.parse(_selectedShelter!.longitude.toString());

    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      lat,
      lon,
    );
  }
}
