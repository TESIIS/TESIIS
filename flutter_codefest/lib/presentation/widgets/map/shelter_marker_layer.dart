import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/domain/marker_clustering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';

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

const double _markerBaseSize = 44.0;
const double _markerSelectedSize = 60.0;

Marker _shelterMarker(
  Shelter shelter, {
  required bool isSelected,
  required void Function(Shelter shelter) onTap,
}) {
  // Keyed by shelter only (not selection): the element must persist across
  // selection changes for AnimatedScale to interpolate rather than jump.
  // The Marker's own width/height stay fixed at the larger size so
  // flutter_map's layout doesn't move the marker as it scales — the visual
  // shrink/grow happens inside, anchored to the same top-centre pin tip.
  return Marker(
    key: ValueKey('shelter-${shelter.shelterId}'),
    point: LatLng(shelter.latitude!, shelter.longitude!),
    width: _markerSelectedSize,
    height: _markerSelectedSize,
    // Bottom-centre: the pin tip is the location, not the middle of the icon.
    alignment: Alignment.topCenter,
    child: Semantics(
      button: true,
      label:
          '${shelter.name}，${shelter.address}'
          '${shelter.isCoordinateExact ? '' : '，位置為概略值'}',
      child: GestureDetector(
        onTap: () => onTap(shelter),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          alignment: Alignment.topCenter,
          scale: isSelected ? 1.0 : _markerBaseSize / _markerSelectedSize,
          child: SvgPicture.asset(
            _markerAsset(shelter, isSelected: isSelected),
            width: _markerSelectedSize,
            height: _markerSelectedSize,
          ),
        ),
      ),
    ),
  );
}

/// Cluster fill, deepened from the app's `#5AB4C5` brand seed
/// (`app_theme.dart`) for contrast with white text — the seed itself is too
/// light. Fixed rather than theme-driven, matching why the shelter pins
/// (red/green/yellow) don't shift with light/dark mode either: a map marker
/// needs to read clearly against whatever the basemap tile underneath it
/// happens to be, not the app chrome.
const _clusterColor = Color(0xFF2E8B99);
const _clusterColorDark = Color(0xFF1F6672);

/// A cluster of 2+ shelters too close together to draw individually at the
/// current zoom — a circle with a count, tapped to zoom in on the group.
Marker _clusterMarker(
  ShelterCluster cluster, {
  required void Function(ShelterCluster cluster) onTap,
}) {
  final size = 34.0 + math.min(cluster.count, 40) * 0.5;
  return Marker(
    key: ValueKey(
      'cluster-${cluster.center.latitude}-${cluster.center.longitude}-${cluster.count}',
    ),
    point: cluster.center,
    width: size,
    height: size,
    child: Semantics(
      button: true,
      label: '${cluster.count} 個避難設施，點擊放大查看',
      child: GestureDetector(
        onTap: () => onTap(cluster),
        // A one-shot pop-in, not a persistent state toggle like the shelter
        // pins' AnimatedScale — clusters have no selected/unselected state,
        // just "just appeared" vs "already there". The key above already
        // stays stable across incidental rebuilds (same members -> same
        // deterministic centroid), so this only replays when a cluster
        // genuinely changes, not on every frame while panning.
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1.0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.3),
                colors: [_clusterColor, _clusterColorDark],
              ),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  '${cluster.count}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Marker _currentLocationMarker(LatLng point) => Marker(
  key: const ValueKey('current-location'),
  point: point,
  width: 56,
  height: 56,
  child: Semantics(
    label: '我的位置',
    child: SvgPicture.asset(
      'assets/icons/now_location.svg',
      width: 56,
      height: 56,
    ),
  ),
);

/// Builds the marker layer for the shelters currently on screen, plus the
/// current-location marker when a fix is available.
///
/// [clusters] groups nearby shelters together (see `marker_clustering.dart`)
/// so a broad nationwide search or a dense district doesn't render thousands
/// of individual widgets. A single-member cluster renders as a normal pin;
/// anything larger renders as a count bubble that zooms in on tap.
List<Marker> buildShelterMarkers({
  required List<ShelterCluster> clusters,
  required Shelter? selectedShelter,
  required LatLng? currentLatLng,
  required void Function(Shelter shelter) onTap,
  required void Function(ShelterCluster cluster) onClusterTap,
}) => [
  for (final cluster in clusters)
    if (cluster.isSingle)
      _shelterMarker(
        cluster.single,
        isSelected: selectedShelter?.shelterId == cluster.single.shelterId,
        onTap: onTap,
      )
    else
      _clusterMarker(cluster, onTap: onClusterTap),
  if (currentLatLng != null) _currentLocationMarker(currentLatLng),
];
