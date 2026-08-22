import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_codefest/data/models/shelter.dart';

/// The disaster-type filter keys the UI exposes.
const disasterFilterTypes = ['landslide', 'tsunami', 'earthquake', 'flood'];

/// The space-type filter keys the UI exposes.
const spaceFilterTypes = ['indoor', 'outdoor'];

/// True if [shelter] matches the selected filter chips.
///
/// Within a category the selections are ORed; the two categories are ANDed.
bool matchesSelectedFilters(
  Shelter shelter, {
  required Set<String> disasterTypes,
  required Set<String> spaceTypes,
}) {
  final matchesDisaster =
      disasterTypes.isEmpty ||
      disasterTypes.any((type) {
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
      spaceTypes.isEmpty ||
      spaceTypes.any((type) {
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

/// Filters [source] by the selected chips, then sorts by distance from
/// [lat]/[lon] when a position is available — without truncating.
///
/// Shelters without a coordinate sort after the located ones instead of being
/// dropped: they exist, people can walk to them, and the UI offers to open
/// the address in an external map instead of silently pretending they are
/// not there.
List<Shelter> applyShelterFilters(
  List<Shelter> source, {
  required Set<String> disasterTypes,
  required Set<String> spaceTypes,
  double? lat,
  double? lon,
}) {
  final hasFilters = disasterTypes.isNotEmpty || spaceTypes.isNotEmpty;
  if (!hasFilters) return source;

  final result = source
      .where(
        (s) => matchesSelectedFilters(
          s,
          disasterTypes: disasterTypes,
          spaceTypes: spaceTypes,
        ),
      )
      .toList();

  if (lat == null || lon == null || result.isEmpty) return result;

  final located = sortedByDistance(result, lat, lon);
  final unlocated = result.where((s) => !s.hasCoordinate);
  return [...located, ...unlocated];
}
