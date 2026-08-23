import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/constants/map_constants.dart';
import 'package:flutter_codefest/core/theme/app_status_colors.dart';
import 'package:flutter_codefest/core/utils/get_platform.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/domain/marker_clustering.dart';
import 'package:flutter_codefest/domain/navigation_service.dart';
import 'package:flutter_codefest/presentation/pages/data_quality_page.dart';
import 'package:flutter_codefest/presentation/pages/user_manual_page.dart';
import 'package:flutter_codefest/presentation/viewmodels/shelter_map_view_model.dart';
import 'package:flutter_codefest/presentation/widgets/map/basemap_switcher.dart';
import 'package:flutter_codefest/presentation/widgets/map/shelter_map_view.dart';
import 'package:flutter_codefest/presentation/widgets/map/shelter_marker_layer.dart';
import 'package:flutter_codefest/presentation/widgets/search/filter_chip_bar.dart';
import 'package:flutter_codefest/presentation/widgets/search/search_results_list.dart';
import 'package:flutter_codefest/presentation/widgets/search/search_toolbar.dart';
import 'package:flutter_codefest/presentation/widgets/shelter/nearby_shelter_panel.dart';
import 'package:flutter_codefest/presentation/widgets/shelter/shelter_detail_sheet.dart';
import 'package:flutter_codefest/presentation/widgets/common/status_banner.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// The map screen: search, filter, shelter detail, and the persistent
/// nearby panel, all wired to a [ShelterMapViewModel].
///
/// This State owns the framework/lifecycle objects the view model doesn't:
/// the `MapController`, the idle-debounce `Timer`, and the search field's
/// `TextEditingController`.
class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  late final ShelterMapViewModel _viewModel;

  /// MapController throws if it is driven before the map has laid out.
  bool _isMapReady = false;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _viewModel = ShelterMapViewModel();
    _viewModel.loadShelters();
    _handleLocate();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Map callbacks
  // ---------------------------------------------------------------------

  void _onMapReady() {
    _isMapReady = true;
    _viewModel.updateVisibleShelters(
      _viewModel.currentLatLng ?? MapConstants.taiwanCenter,
    );
  }

  /// Fires continuously while the map moves, so the real work is debounced
  /// until it stops.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _idleTimer?.cancel();
    _idleTimer = Timer(MapConstants.idleDebounce, () {
      if (!mounted || _viewModel.isSearching) return;
      _viewModel.updateVisibleShelters(camera.center);
    });
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (!_viewModel.isSearching && !_viewModel.showShelterDetails) return;
    if (_viewModel.isSearching) _searchController.clear();
    _viewModel.dismissOverlays();
    FocusScope.of(context).unfocus();
  }

  void _onMarkerTapped(Shelter shelter) {
    _viewModel.selectShelter(shelter);
    if (_isMapReady && shelter.hasCoordinate) {
      _mapController.move(
        LatLng(shelter.latitude!, shelter.longitude!),
        _mapController.camera.zoom,
      );
    }
  }

  /// Zooms in on a cluster rather than trying to select one of its members —
  /// at nationwide scale a broad search or a dense district can group dozens
  /// of shelters into one bubble, and there is no single "the" shelter to
  /// open a detail sheet for.
  void _onClusterTapped(ShelterCluster cluster) {
    if (!_isMapReady) return;
    _mapController.move(cluster.center, _mapController.camera.zoom + 2);
  }

  // ---------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------

  void _toggleSearch() {
    final wasSearching = _viewModel.isSearching;
    _viewModel.toggleSearching();
    if (wasSearching) _searchController.clear();
  }

  Future<void> _onSearch(String query) async {
    try {
      await _viewModel.search(query);
    } catch (e) {
      debugPrint('搜尋失敗: $e');
      _showSnackBar('搜尋失敗,請確認網路連線');
    }
  }

  // ---------------------------------------------------------------------
  // Location and navigation
  // ---------------------------------------------------------------------

  Future<void> _handleLocate() async {
    await _viewModel.getCurrentLocation();
    final here = _viewModel.currentLatLng;
    if (here != null && _isMapReady) _mapController.move(here, 15.0);
  }

  /// Hands [shelter] to whatever map app the device has.
  Future<void> _openNavigation(Shelter shelter) async {
    final uri = buildNavigationUri(shelter, from: _viewModel.currentPosition);
    try {
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
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // 防止鍵盤推擠介面
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) => _buildContent(context),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final vm = _viewModel;

    final circles = vm.visibleCenter == null
        ? const <CircleMarker>[]
        : [
            CircleMarker(
              point: vm.visibleCenter!,
              radius: MapConstants.visibleRadiusMeters,
              useRadiusInMeter: true,
              color: colorScheme.primary.withValues(alpha: 0.15),
              borderColor: colorScheme.primary.withValues(alpha: 0.5),
              borderStrokeWidth: 2,
            ),
          ];

    final clusters = clusterShelters([
      for (final s in vm.markerShelters)
        if (s.hasCoordinate) s,
    ], zoom: _isMapReady ? _mapController.camera.zoom : 12.0);
    final markers = buildShelterMarkers(
      clusters: clusters,
      selectedShelter: vm.selectedShelter,
      currentLatLng: vm.currentLatLng,
      onTap: _onMarkerTapped,
      onClusterTap: _onClusterTapped,
    );

    final showNearbyPanel =
        vm.currentPosition != null &&
        vm.nearbyShelters.isNotEmpty &&
        !vm.showShelterDetails &&
        !vm.isSearching;

    final hasFilters =
        vm.selectedDisasterTypes.isNotEmpty || vm.selectedSpaceTypes.isNotEmpty;
    final hasSearchText = _searchController.text.isNotEmpty;
    final resultList = (hasFilters || hasSearchText)
        ? vm.filteredShelters
        : vm.nearbyShelters;

    final isWide =
        MediaQuery.of(context).size.width >= MapConstants.desktopBreakpoint;

    return Stack(
      children: [
        Positioned.fill(
          child: ShelterMapView(
            mapController: _mapController,
            basemap: vm.basemap,
            markers: markers,
            circles: circles,
            onMapReady: _onMapReady,
            onPositionChanged: _onPositionChanged,
            onTap: _onMapTap,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 260,
          child: BasemapSwitcher(
            selected: vm.basemap,
            onSelected: vm.switchBasemap,
          ),
        ),
        Positioned(
          right: 16,
          bottom: 316,
          child: Material(
            color: colorScheme.surface,
            shape: const CircleBorder(),
            elevation: 2,
            child: IconButton(
              tooltip: '座標資料品質',
              icon: Icon(
                Icons.assessment_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DataQualityPage(),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          right: isWide ? null : 16,
          width: isWide ? MapConstants.desktopPanelWidth : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SearchToolbar(
                controller: _searchController,
                isSearching: vm.isSearching,
                isLoadingLocation: vm.isLoadingLocation,
                onToggleSearch: _toggleSearch,
                onLocate: _handleLocate,
                onSearchChanged: _onSearch,
              ),

              _animatedSlot(
                vm.isShowingCachedData
                    ? StatusBanner(
                        tone: StatusTone.info,
                        icon: Icons.cloud_off,
                        message:
                            '顯示上次快取資料'
                            '${vm.cachedAt != null ? '（更新於 ${_formatCachedAt(vm.cachedAt!)}）' : ''}',
                      )
                    : null,
              ),

              _animatedSlot(
                vm.locationMessage != null
                    ? StatusBanner(
                        tone: vm.isLocationSuccess
                            ? StatusTone.success
                            : StatusTone.danger,
                        icon: vm.isLocationSuccess
                            ? Icons.check_circle_rounded
                            : Icons.error_rounded,
                        message: vm.locationMessage!,
                      )
                    : null,
              ),

              _animatedSlot(
                vm.isSearching
                    ? FilterChipBar(
                        isSelected: vm.isFilterSelected,
                        onToggle: vm.toggleFilter,
                      )
                    : null,
              ),

              _animatedSlot(
                vm.isSearching
                    ? Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.6,
                        ),
                        // Material, not a plain Container+BoxDecoration: the
                        // list inside is made of ListTiles, which paint their
                        // background/ink splashes on the nearest Material
                        // ancestor. An opaque BoxDecoration sitting between
                        // them and the root Material hid that ink entirely —
                        // Flutter's own framework assertion catches this and
                        // was firing on every result row. clipBehavior also
                        // makes the scrolling list respect the rounded
                        // corners, which the old plain Container never did.
                        child: Material(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          elevation: 6,
                          clipBehavior: Clip.antiAlias,
                          child: SearchResultsList(
                            shelters: resultList,
                            hasFilters: hasFilters,
                            currentPosition: vm.currentPosition,
                            selectedShelter: vm.selectedShelter,
                            onSelect: (shelter) {
                              _onMarkerTapped(shelter);
                              _toggleSearch();
                            },
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),

        // Not wrapped in the AnimatedSwitcher below: both layouts of
        // ShelterDetailSheet root themselves directly in a Positioned /
        // DraggableScrollableSheet that needs to sit directly in the Stack
        // to self-position. AnimatedSwitcher's transitionBuilder interposes
        // a FadeTransition RenderObject that breaks that — confirmed by a
        // throwaway widget test before this comment was written.
        if (vm.showShelterDetails && vm.selectedShelter != null)
          ShelterDetailSheet(
            shelter: vm.selectedShelter!,
            currentPosition: vm.currentPosition,
            onClose: vm.clearSelection,
            onNavigate: () => _openNavigation(vm.selectedShelter!),
            wide: isWide,
          ),

        if (showNearbyPanel)
          NearbyShelterPanel(
            nearest: vm.nearbyShelters.first,
            currentPosition: vm.currentPosition!,
            onNavigate: () => _openNavigation(vm.nearbyShelters.first),
            onViewDetail: () => _onMarkerTapped(vm.nearbyShelters.first),
            onOpenManual: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UserManualPage()),
            ),
            wide: isWide,
          ),
      ],
    );
  }

  /// Wraps a nullable child in a fade + grow/shrink transition so
  /// conditionally-shown pieces of the top toolbar column — banners, the
  /// filter bar, the results list — animate in and out instead of popping.
  ///
  /// Only used for plain block-flow children inside the `Column` above; see
  /// the comment further down for why the detail sheet and nearby panel
  /// can't use this.
  static String _formatCachedAt(DateTime cachedAt) {
    final local = cachedAt.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${local.hour}:$minute';
  }

  static Widget _animatedSlot(Widget? child) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
      child: child ?? const SizedBox.shrink(key: ValueKey('empty-slot')),
    );
  }
}
