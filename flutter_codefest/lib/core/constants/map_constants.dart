import 'package:latlong2/latlong.dart';

/// Magic numbers that used to live inline in the map screen.
class MapConstants {
  MapConstants._();

  /// Fallback map centre before a location fix is available. Roughly the
  /// geographic centre of Taiwan (Puli, Nantou) at a zoom that shows most of
  /// the main island — used only until `getCurrentLocation()` succeeds or the
  /// user picks a shelter.
  static const LatLng taiwanCenter = LatLng(23.7, 121.0);

  /// Radius of the "what is around here" circle, in metres.
  static const double visibleRadiusMeters = 1500;

  /// How long the map must sit still before recomputing what is in range.
  static const Duration idleDebounce = Duration(milliseconds: 300);

  /// Zoom level for the fallback nationwide view (`taiwanCenter`).
  static const double nationwideZoom = 7.5;

  /// Below this width the UI stays edge-to-edge, mobile-style. At or above
  /// it, the floating panels cap their width instead of stretching across
  /// the whole window.
  static const double desktopBreakpoint = 700;

  /// Fixed width for the search/detail/nearby panels once desktop layout
  /// kicks in.
  static const double desktopPanelWidth = 420;
}
