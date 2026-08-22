import 'package:flutter/material.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
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

const double _markerBaseSize = 34.0;
const double _markerSelectedSize = 46.0;

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

/// Builds the marker layer for the shelters currently on screen, plus the
/// current-location marker when a fix is available.
List<Marker> buildShelterMarkers({
  required List<Shelter> shelters,
  required Shelter? selectedShelter,
  required LatLng? currentLatLng,
  required void Function(Shelter shelter) onTap,
}) => [
  for (final shelter in shelters)
    if (shelter.hasCoordinate)
      _shelterMarker(
        shelter,
        isSelected: selectedShelter?.shelterId == shelter.shelterId,
        onTap: onTap,
      ),
  if (currentLatLng != null) _currentLocationMarker(currentLatLng),
];
