import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_codefest/data/models/shelter.dart';

/// Matches the server's search normalization and OR-within/AND-across groups.
String normalizeSearch(String value) => String.fromCharCodes(
  value.runes.map(
    (r) => r >= 0xff01 && r <= 0xff5e
        ? r - 0xfee0
        : r == 0x3000
        ? 32
        : r,
  ),
).replaceAll('臺', '台').toLowerCase().trim();

List<Shelter> queryOffline(List<Shelter> data, Map<String, String> params) {
  final words = normalizeSearch(
    params['q'] ?? '',
  ).split(RegExp(r'[\s,、，]+')).where((s) => s.isNotEmpty);
  final disasters = (params['disasters'] ?? '')
      .split(',')
      .where((s) => s.isNotEmpty)
      .toSet();
  final spaces = (params['spaces'] ?? '')
      .split(',')
      .where((s) => s.isNotEmpty)
      .toSet();
  final box = params['bbox']?.split(',').map(double.parse).toList();
  final lat = double.tryParse(params['lat'] ?? '');
  final lng = double.tryParse(params['lng'] ?? '');
  final radius = double.tryParse(params['radius'] ?? '');
  final result = data.where((s) {
    if (params['city'] case final city? when city.isNotEmpty) {
      if (normalizeSearch(s.city) != normalizeSearch(city)) return false;
    }
    if (params['township'] case final township? when township.isNotEmpty) {
      if (normalizeSearch(s.district) != normalizeSearch(township)) {
        return false;
      }
    }
    if (params['vulnerable'] == 'Y' && s.accessible != 'Y') return false;
    final flags = {
      'flood': s.flood,
      'earthquake': s.earthquake,
      'landslide': s.landslide,
      'tsunami': s.tsunami,
      'nuclear': s.nuclear,
      'indoor': s.indoor,
      'outdoor': s.outdoor,
    };
    if (disasters.isNotEmpty && !disasters.any((d) => flags[d] == 'Y')) {
      return false;
    }
    if (spaces.isNotEmpty && !spaces.any((d) => flags[d] == 'Y')) return false;
    final text = normalizeSearch(
      [
        s.shelterId,
        s.name,
        s.city,
        s.district,
        s.village,
        s.address,
        s.type,
        ...s.serviceVillages,
        s.remarks,
        s.contactName,
        s.managerName,
      ].join(' '),
    );
    if (!words.every(text.contains)) return false;
    if (box != null &&
        (!s.hasCoordinate ||
            s.longitude! < box[0] ||
            s.latitude! < box[1] ||
            s.longitude! > box[2] ||
            s.latitude! > box[3])) {
      return false;
    }
    if (lat != null &&
        lng != null &&
        (!s.hasCoordinate ||
            (radius != null && distanceToShelter(s, lat, lng) > radius))) {
      return false;
    }
    return true;
  }).toList();
  if (lat != null && lng != null) {
    result.sort(
      (a, b) => distanceToShelter(
        a,
        lat,
        lng,
      ).compareTo(distanceToShelter(b, lat, lng)),
    );
  }
  return result;
}
