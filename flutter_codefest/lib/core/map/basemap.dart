import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Basemaps published by 內政部國土測繪中心 (NLSC).
///
/// Free, no API key, no account, official Taiwanese cartography with complete
/// Chinese place names. This is what makes the app work out of the box.
///
/// Tile URL note — verified against
/// <https://wmts.nlsc.gov.tw/wmts/1.0.0/WMTSCapabilities.xml>, whose
/// ResourceURL template is
/// `.../{Style}/{TileMatrixSet}/{TileMatrix}/{TileRow}/{TileCol}`.
///
/// TileRow is y and TileCol is x, so the path order is `{z}/{y}/{x}` — the
/// **reverse** of the `{z}/{x}/{y}` used by OSM-style services. Getting this
/// wrong does not fail loudly: the server still answers HTTP 200, just with a
/// blank ocean tile (2 KB instead of ~32 KB), so the map renders as an empty
/// grey grid. See basemap_test.dart.
///
/// The template carries no file extension and every layer is served as JPEG
/// regardless of what you ask for.
enum Basemap {
  emap(label: '通用電子地圖', icon: Icons.map_outlined, layer: 'EMAP'),
  emapDark(label: '暗色地圖', icon: Icons.dark_mode_outlined, layer: 'EMAP6'),
  photo(label: '正射影像', icon: Icons.satellite_alt_outlined, layer: 'PHOTO2');

  const Basemap({required this.label, required this.icon, required this.layer});

  final String label;
  final IconData icon;
  final String layer;

  String get urlTemplate =>
      'https://wmts.nlsc.gov.tw/wmts/$layer/default/GoogleMapsCompatible/'
      '{z}/{y}/{x}';

  /// NLSC's terms require the source to be credited wherever the tiles appear.
  static const attribution = '© 內政部國土測繪中心';
}

/// The tile layer for [basemap].
TileLayer basemapTileLayer(Basemap basemap) => TileLayer(
  urlTemplate: basemap.urlTemplate,
  userAgentPackageName: 'tw.gov.taipei.codefest.team30.shelter',
  maxNativeZoom: 20,
  // Keyed so switching basemaps swaps tiles instead of leaving the old
  // ones on screen until each is individually replaced.
  key: ValueKey(basemap),
);
