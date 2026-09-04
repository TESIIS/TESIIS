import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/constants/map_constants.dart';
import 'package:flutter_codefest/core/theme/app_status_colors.dart';
import 'package:flutter_codefest/core/utils/get_platform.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/domain/marker_clustering.dart';
import 'package:flutter_codefest/domain/navigation_service.dart';
import 'package:flutter_codefest/presentation/pages/about_page.dart';
import 'package:flutter_codefest/presentation/pages/data_quality_page.dart';
import 'package:flutter_codefest/presentation/pages/user_manual_page.dart';
import 'package:flutter_codefest/presentation/viewmodels/shelter_map_view_model.dart';
import 'package:flutter_codefest/presentation/widgets/map/basemap_switcher.dart';
import 'package:flutter_codefest/presentation/widgets/map/cluster_members_sheet.dart';
import 'package:flutter_codefest/presentation/widgets/map/nationwide_stats_card.dart';
import 'package:flutter_codefest/presentation/widgets/map/shelter_map_view.dart';
import 'package:flutter_codefest/presentation/widgets/map/shelter_marker_layer.dart';
import 'package:flutter_codefest/presentation/widgets/search/filter_chip_bar.dart';
import 'package:flutter_codefest/presentation/widgets/search/search_results_list.dart';
import 'package:flutter_codefest/presentation/widgets/search/search_toolbar.dart';
import 'package:flutter_codefest/presentation/widgets/shelter/nearby_shelter_panel.dart';
import 'package:flutter_codefest/presentation/widgets/shelter/shelter_detail_sheet.dart';
import 'package:flutter_codefest/presentation/widgets/common/status_banner.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
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

class _MapPageState extends State<MapPage> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  late final ShelterMapViewModel _viewModel;

  /// MapController throws if it is driven before the map has laid out.
  bool _isMapReady = false;

  /// The zoom `_handleLocate` wanted, when the fix arrived before the map had
  /// laid out and the camera could not be driven yet.
  double? _pendingLocateZoom;
  Timer? _idleTimer;

  /// Drives [_animatedMapMove]. Tracked so a move started while a previous
  /// one is still running can cancel it instead of the two fighting over
  /// `_mapController`, and so it can be disposed with the rest of the state.
  AnimationController? _moveAnimController;

  /// Which nearest shelter the nearby panel was last closed for, so closing
  /// it doesn't hide it forever — it comes back once a *different* shelter
  /// becomes the nearest one (the user moved somewhere the old dismissal no
  /// longer applies to), or the user taps the reopen button.
  String? _nearbyPanelDismissedFor;

  /// Last-known detail/nearby-panel data, kept around after the view model
  /// clears its own copy so [ShelterDetailSheet] and [NearbyShelterPanel]
  /// still have something to render while their close animation plays —
  /// otherwise the content would disappear instantly and only the empty
  /// panel shell would animate out.
  Shelter? _lastSelectedShelter;
  Shelter? _lastNearestShelter;
  Position? _lastNearbyPosition;

  @override
  void initState() {
    super.initState();
    _viewModel = ShelterMapViewModel();
    // 一載入就自動定位：_pendingLocateZoom 會在 map 尚未 ready 時
    // 保留想要的縮放，等 _onMapReady 再移動鏡頭。
    unawaited(_handleLocate());
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _moveAnimController?.dispose();
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
    final here = _viewModel.currentLatLng;
    if (here != null) {
      _mapController.move(
        here,
        _pendingLocateZoom ?? _mapController.camera.zoom,
      );
      _pendingLocateZoom = null;
    }
    // After the move, not before: loading clusters for the pre-move camera
    // fetched markers for a viewport that was about to be replaced.
    _viewModel.loadClusters(
      _mapController.camera.visibleBounds,
      _mapController.camera.zoom,
    );
  }

  /// Fires continuously while the map moves, so the real work is debounced
  /// until it stops.
  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _idleTimer?.cancel();
    _idleTimer = Timer(MapConstants.idleDebounce, () {
      if (!mounted) return;
      if (_viewModel.isSearching) {
        // Search results are clustered client-side in `_buildContent` at the
        // current zoom, but nothing else rebuilds this screen while the map
        // moves — the view model is not fetching. Without this the pins keep
        // the grouping from whatever zoom the search started at.
        setState(() {});
        return;
      }
      _viewModel.loadClusters(camera.visibleBounds, camera.zoom);
      unawaited(
        _viewModel.refreshNearbyShelters(
          radiusMeters: MapConstants.nearbyRadiusForZoom(camera.zoom),
        ),
      );
    });
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (!_viewModel.isSearching && !_viewModel.showShelterDetails) return;
    if (_viewModel.isSearching) _searchController.clear();
    _viewModel.dismissOverlays();
    FocusScope.of(context).unfocus();
  }

  /// Jumps the camera to [shelter]'s location. Tapping a marker or a search
  /// result can both happen from a nationwide-zoomed-out view, where just
  /// panning would land the destination somewhere off-screen or too small
  /// to register as "here it is" — so this also zooms in when the current
  /// zoom is looser than [MapConstants.visibleRadiusZoom], on top of the
  /// pan.
  ///
  /// Selecting a shelter always opens [ShelterDetailSheet], which covers
  /// part of the map — the right edge on desktop, the bottom on mobile.
  /// Centering on the shelter's raw lat/lng would land it half-hidden behind
  /// that panel, so the destination is offset by half the panel's footprint
  /// first, landing the shelter centered in whatever's left visible instead.
  void _onMarkerTapped(Shelter shelter) {
    _viewModel.selectShelter(shelter);
    if (_isMapReady && shelter.hasCoordinate) {
      final shelterLatLng = LatLng(shelter.latitude!, shelter.longitude!);
      final camera = _mapController.camera;
      final currentZoom = camera.zoom;
      final targetZoom = currentZoom < MapConstants.visibleRadiusZoom
          ? MapConstants.visibleRadiusZoom
          : currentZoom;

      // Best-effort: land the shelter centered in whatever the detail panel
      // (right edge on desktop, bottom sheet on mobile) leaves visible,
      // instead of half-hidden behind it. Falls back to a plain centered
      // pan if the projection math ever misbehaves, so a bug here degrades
      // the polish rather than breaking the jump entirely.
      var target = shelterLatLng;
      try {
        final screenSize = MediaQuery.of(context).size;
        final isWide = screenSize.width >= MapConstants.desktopBreakpoint;
        final panelObstruction = isWide
            ? Offset(16 + MapConstants.desktopPanelWidth, 0)
            : Offset(
                0,
                screenSize.height *
                    MapConstants.mobileDetailSheetInitialFraction,
              );
        final shelterPoint = camera.projectAtZoom(shelterLatLng, targetZoom);
        final centeredPoint = shelterPoint + panelObstruction / 2;
        target = camera.unprojectAtZoom(centeredPoint, targetZoom);
      } catch (e) {
        debugPrint('避難點置中偏移計算失敗，改用一般置中: $e');
      }

      _animatedMapMove(target, targetZoom);
    }
  }

  /// Same jump as tapping a marker, plus closing the search box — picking a
  /// result from the list should feel like "go there", not just select it.
  void _onSearchResultSelected(Shelter shelter) {
    _onMarkerTapped(shelter);
    _toggleSearch();
  }

  /// Eases the camera to [destLocation]/[destZoom] instead of jumping there,
  /// so picking a different shelter reads as travel across the map rather
  /// than a jump-cut.
  ///
  /// flutter_map has no built-in animated `move` — this is the standard
  /// hand-rolled recipe (tween lat/lng/zoom, drive `_mapController.move` off
  /// an `AnimationController`) rather than a package pull for one call site,
  /// matching this project's minimal-dependency stance.
  void _animatedMapMove(LatLng destLocation, double destZoom) {
    _moveAnimController?.dispose();
    final camera = _mapController.camera;
    final latTween = Tween<double>(
      begin: camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom);

    final controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _moveAnimController = controller;
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        if (identical(_moveAnimController, controller)) {
          _moveAnimController = null;
        }
        controller.dispose();
      }
    });

    controller.forward();
  }

  /// Zooms in on a cluster rather than trying to select one of its members —
  /// at nationwide scale a broad search or a dense district can group dozens
  /// of shelters into one bubble, and there is no single "the" shelter to
  /// open a detail sheet for.
  ///
  /// Zooming stops helping once the camera is already at
  /// [MapConstants.maxZoom]: a cluster that's still grouped there is made of
  /// shelters close enough together (tens of metres) that no further zoom
  /// will separate their markers. That case falls back to
  /// [_showClusterMembers] instead of moving the map nowhere.
  Future<void> _onClusterTapped(ShelterCluster cluster) async {
    if (!_isMapReady) return;
    final zoom = _mapController.camera.zoom;
    if (zoom >= MapConstants.maxZoom - 0.01) {
      await _showClusterMembers(cluster);
      return;
    }
    _animatedMapMove(cluster.center, zoom + 2);
  }

  Future<void> _showClusterMembers(ShelterCluster cluster) async {
    final members = await _viewModel.fetchClusterMembers(
      cluster.center,
      cluster.count,
    );
    if (!mounted) return;
    if (members.isEmpty) {
      _showSnackBar('無法載入這個群集的避難所');
      return;
    }
    final selected = await showModalBottomSheet<Shelter>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ClusterMembersSheet(members: members),
    );
    if (selected != null) _onMarkerTapped(selected);
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
      _showSnackBar('搜尋失敗，請確認網路連線');
    }
  }

  // ---------------------------------------------------------------------
  // Location and navigation
  // ---------------------------------------------------------------------

  Future<void> _handleLocate() async {
    const targetZoom = 15.0;
    await _viewModel.getCurrentLocation(
      radiusMeters: MapConstants.nearbyRadiusForZoom(targetZoom),
    );
    final here = _viewModel.currentLatLng;
    if (here == null) return;
    if (_isMapReady) {
      _mapController.move(here, targetZoom);
    } else {
      _pendingLocateZoom = targetZoom;
    }
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

    if (vm.selectedShelter != null) _lastSelectedShelter = vm.selectedShelter;
    if (vm.currentPosition != null && vm.nearbyShelters.isNotEmpty) {
      _lastNearestShelter = vm.nearbyShelters.first;
      _lastNearbyPosition = vm.currentPosition;
    }

    // Markers come from the server's per-viewport cluster endpoint while
    // browsing; during a search the current result page is clustered
    // client-side so the pins track exactly what the list shows. Before a
    // query is typed, the search box shows the nearest-first preview list
    // instead of results — the map mirrors that with the same shelters.
    final zoom = _isMapReady ? _mapController.camera.zoom : 12.0;
    final searchShelters = vm.searchQuery.isEmpty
        ? vm.searchPreview
        : vm.searchResults;
    final clusters = vm.isSearching
        ? clusterShelters([
            for (final s in searchShelters)
              if (s.hasCoordinate) s,
          ], zoom: zoom)
        : vm.clusters;
    final markers = buildShelterMarkers(
      clusters: clusters,
      selectedShelter: vm.selectedShelter,
      currentLatLng: vm.currentLatLng,
      onTap: _onMarkerTapped,
      onClusterTap: _onClusterTapped,
    );

    final isWide =
        MediaQuery.of(context).size.width >= MapConstants.desktopBreakpoint;

    final nearestShelter =
        vm.currentPosition != null && vm.nearbyShelters.isNotEmpty
        ? vm.nearbyShelters.first
        : _lastNearestShelter;
    final nearestPosition = vm.currentPosition ?? _lastNearbyPosition;

    final nearbyPanelWanted =
        vm.currentPosition != null &&
        vm.nearbyShelters.isNotEmpty &&
        (isWide || !vm.showShelterDetails) &&
        !vm.isSearching;
    final nearbyPanelDismissed =
        nearbyPanelWanted &&
        vm.nearbyShelters.first.shelterId == _nearbyPanelDismissedFor;
    final nearbyPanelVisible = nearbyPanelWanted && !nearbyPanelDismissed;

    final hasFilters =
        vm.selectedDisasterTypes.isNotEmpty || vm.selectedSpaceTypes.isNotEmpty;

    final cornerButtonsBottom = isWide ? 16.0 : 380.0;

    return Stack(
      children: [
        Positioned.fill(
          child: ShelterMapView(
            mapController: _mapController,
            basemap: vm.basemap,
            markers: markers,
            onMapReady: _onMapReady,
            onPositionChanged: _onPositionChanged,
            onTap: _onMapTap,
          ),
        ),
        // Desktop only: mobile has no room for this beside the map, and the
        // sidebar's dock (below) claims the same corner once a shelter is
        // selected.
        if (isWide && !vm.showShelterDetails)
          const Positioned(
            top: 16,
            right: 16,
            width: 280,
            child: NationwideStatsCard(),
          ),
        Positioned(
          right: 16,
          bottom: cornerButtonsBottom,
          child: BasemapSwitcher(
            selected: vm.basemap,
            onSelected: vm.switchBasemap,
          ),
        ),
        Positioned(
          right: 16,
          bottom: cornerButtonsBottom + 56,
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
          right: 16,
          bottom: cornerButtonsBottom + 112,
          child: Material(
            color: colorScheme.surface,
            shape: const CircleBorder(),
            elevation: 2,
            child: IconButton(
              tooltip: '使用手冊',
              icon: Icon(Icons.menu_book, color: colorScheme.onSurfaceVariant),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const UserManualPage()),
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: cornerButtonsBottom + 168,
          child: Material(
            color: colorScheme.surface,
            shape: const CircleBorder(),
            elevation: 2,
            child: IconButton(
              tooltip: '關於我們',
              icon: Icon(
                Icons.groups_2_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutPage()),
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
                vm.isServingStaleData
                    ? StatusBanner(
                        tone: StatusTone.info,
                        icon: Icons.history,
                        message: vm.dataFreshness == 'snapshot'
                            ? '離線備援資料：無法連上內政部消防署，顯示的是隨程式封存的快照'
                            : '伺服器暫存資料：內政部消防署目前無回應，顯示的是上次成功取得的資料',
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
                vm.isSearching &&
                        (vm.searchQuery.isNotEmpty ||
                            vm.searchPreview.isNotEmpty)
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
                          child: vm.searchQuery.isEmpty
                              ? SearchResultsList(
                                  shelters: vm.searchPreview,
                                  total: vm.searchPreview.length,
                                  hasMore: false,
                                  isLoadingMore: false,
                                  hasFilters: hasFilters,
                                  currentPosition: vm.currentPosition,
                                  selectedShelter: vm.selectedShelter,
                                  previewLabel: '距離最近的避難所',
                                  onSelect: _onSearchResultSelected,
                                  onLoadMore: () {},
                                )
                              : SearchResultsList(
                                  shelters: vm.searchResults,
                                  total: vm.searchTotal,
                                  hasMore: vm.searchHasMore,
                                  isLoadingMore: vm.isLoadingMore,
                                  hasFilters: hasFilters,
                                  currentPosition: vm.currentPosition,
                                  selectedShelter: vm.selectedShelter,
                                  onSelect: _onSearchResultSelected,
                                  onLoadMore: vm.loadMoreSearch,
                                ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),

        // Not wrapped in AnimatedSwitcher: both layouts of ShelterDetailSheet
        // and NearbyShelterPanel root themselves directly in a Positioned /
        // DraggableScrollableSheet that needs to sit directly in the Stack
        // to self-position — AnimatedSwitcher's transitionBuilder interposes
        // a FadeTransition RenderObject that breaks that (confirmed by a
        // throwaway widget test before this comment was written). Instead,
        // both stay mounted permanently once first shown and animate their
        // own open/close internally, driven by `visible`.
        if (_lastSelectedShelter != null)
          ShelterDetailSheet(
            shelter: _lastSelectedShelter!,
            currentPosition: vm.currentPosition,
            onClose: vm.clearSelection,
            onNavigate: () => _openNavigation(_lastSelectedShelter!),
            wide: isWide,
            visible: vm.showShelterDetails && vm.selectedShelter != null,
          ),

        if (nearestShelter != null && nearestPosition != null)
          NearbyShelterPanel(
            nearest: nearestShelter,
            currentPosition: nearestPosition,
            onNavigate: () => _openNavigation(nearestShelter),
            onViewDetail: () => _onMarkerTapped(nearestShelter),
            onClose: () => setState(() {
              _nearbyPanelDismissedFor = nearestShelter.shelterId;
            }),
            wide: isWide,
            visible: nearbyPanelVisible,
          ),

        if (nearbyPanelDismissed)
          NearbyPanelReopenButton(
            onTap: () => setState(() => _nearbyPanelDismissedFor = null),
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
