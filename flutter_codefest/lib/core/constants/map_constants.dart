import 'package:latlong2/latlong.dart';

/// Magic numbers that used to live inline in the map screen.
class MapConstants {
  MapConstants._();

  static const LatLng taipeiCenter = LatLng(25.0375, 121.5651);

  /// Radius of the "what is around here" circle, in metres.
  static const double visibleRadiusMeters = 1500;

  /// How long the map must sit still before recomputing what is in range.
  static const Duration idleDebounce = Duration(milliseconds: 300);

  /// Rough 臺北市 extent, used only to warn that the user has panned away.
  static const double taipeiMinLat = 24.95;
  static const double taipeiMaxLat = 25.21;
  static const double taipeiMinLng = 121.45;
  static const double taipeiMaxLng = 121.65;

  static bool isWithinTaipei(LatLng point) =>
      point.latitude >= taipeiMinLat &&
      point.latitude <= taipeiMaxLat &&
      point.longitude >= taipeiMinLng &&
      point.longitude <= taipeiMaxLng;
}
