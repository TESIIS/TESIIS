import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_codefest/data/models/shelter.dart';

/// 計算兩個經緯度之間距離（單位：公尺）
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadius = 6371000; // 地球半徑（公尺）
  final double dLat = _deg2rad(lat2 - lat1);
  final double dLon = _deg2rad(lon2 - lon1);

  final double a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);

  final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadius * c;
}

double _deg2rad(double deg) => deg * pi / 180;

/// 取得目前位置最近的 N 個收容所
Future<List<Shelter>> getNearestShelters(
  List<Shelter> shelters,
  Position userPosition, {
  int limit = 5,
}) async {
  final double userLat = userPosition.latitude;
  final double userLon = userPosition.longitude;

  // 過濾掉座標為 null 的避難所
  final validShelters = shelters.where((shelter) {
    if (shelter.latitude == null || shelter.longitude == null) {
      return false;
    }
    // 確保座標可以轉換為 double
    try {
      final lat = shelter.latitude is double
          ? shelter.latitude
          : double.parse(shelter.latitude.toString());
      final lon = shelter.longitude is double
          ? shelter.longitude
          : double.parse(shelter.longitude.toString());
      return lat != 0.0 && lon != 0.0;
    } catch (e) {
      return false;
    }
  }).toList();

  if (validShelters.isEmpty) {
    return [];
  }

  // 計算每個收容所距離並排序
  validShelters.sort((a, b) {
    final double latA = a.latitude is double
        ? a.latitude
        : double.parse(a.latitude.toString());
    final double lonA = a.longitude is double
        ? a.longitude
        : double.parse(a.longitude.toString());
    final double latB = b.latitude is double
        ? b.latitude
        : double.parse(b.latitude.toString());
    final double lonB = b.longitude is double
        ? b.longitude
        : double.parse(b.longitude.toString());

    final double distA = calculateDistance(userLat, userLon, latA, lonA);
    final double distB = calculateDistance(userLat, userLon, latB, lonB);
    return distA.compareTo(distB);
  });

  // 取前 limit 個
  return validShelters.take(limit).toList();
}
