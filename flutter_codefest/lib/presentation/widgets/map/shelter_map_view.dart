import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/constants/map_constants.dart';
import 'package:flutter_codefest/core/map/basemap.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// The full-screen `FlutterMap`: tiles, shelter markers, and the required
/// NLSC attribution.
class ShelterMapView extends StatelessWidget {
  const ShelterMapView({
    super.key,
    required this.mapController,
    required this.basemap,
    required this.markers,
    required this.onMapReady,
    required this.onPositionChanged,
    required this.onTap,
    this.onChooseOrigin,
    this.tilesEnabled = true,
  });

  final MapController mapController;
  final Basemap basemap;
  final List<Marker> markers;
  final VoidCallback onMapReady;
  final void Function(MapCamera camera, bool hasGesture) onPositionChanged;
  final void Function(TapPosition tapPosition, LatLng point) onTap;
  final void Function(TapPosition tapPosition, LatLng point)? onChooseOrigin;
  final bool tilesEnabled;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: MapConstants.taiwanCenter,
        initialZoom: MapConstants.nationwideZoom,
        minZoom: MapConstants.minZoom,
        maxZoom: MapConstants.maxZoom,
        onMapReady: onMapReady,
        onPositionChanged: onPositionChanged,
        onTap: onTap,
        onLongPress: onChooseOrigin,
        onSecondaryTap: onChooseOrigin,
      ),
      children: [
        if (tilesEnabled) basemapTileLayer(basemap),
        MarkerLayer(markers: markers),
        // Required by the NLSC terms of use wherever their tiles are shown.
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [
            TextSourceAttribution(Basemap.attribution, prependCopyright: false),
          ],
        ),
      ],
    );
  }
}
