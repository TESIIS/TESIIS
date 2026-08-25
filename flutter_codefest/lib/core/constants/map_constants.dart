import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Magic numbers that used to live inline in the map screen.
class MapConstants {
  MapConstants._();

  /// Fallback map centre before a location fix is available. Roughly the
  /// geographic centre of Taiwan (Puli, Nantou) at a zoom that shows most of
  /// the main island — used only until `getCurrentLocation()` succeeds or the
  /// user picks a shelter.
  static const LatLng taiwanCenter = LatLng(23.7, 121.0);

  /// Baseline radius of the "what is around here" circle, in metres.
  static const double visibleRadiusMeters = 1500;

  /// The zoom level where [visibleRadiusMeters] is used as-is.
  static const double visibleRadiusZoom = 15;

  /// Smallest nearby search radius, in metres, for close street-level views.
  static const double minVisibleRadiusMeters = 300;

  /// Largest nearby search radius, in metres, for zoomed-out browsing.
  static const double maxVisibleRadiusMeters = 20000;

  /// Nearby search radius that tracks the map zoom.
  ///
  /// Every zoom level out doubles the covered map area; every zoom level in
  /// halves it. The clamp keeps the server query useful at both extremes.
  static double nearbyRadiusForZoom(double zoom) {
    final radius = visibleRadiusMeters * math.pow(2, visibleRadiusZoom - zoom);
    return radius
        .clamp(minVisibleRadiusMeters, maxVisibleRadiusMeters)
        .toDouble();
  }

  /// How long the map must sit still before recomputing what is in range.
  static const Duration idleDebounce = Duration(milliseconds: 300);

  /// Camera zoom bounds, shared with `map_page.dart`'s cluster-tap handling:
  /// tapping a cluster that is still grouped at [maxZoom] can't be resolved
  /// by zooming in further, so it needs a different way to open (see
  /// `ClusterMembersSheet`) instead of silently doing nothing.
  static const double minZoom = 6;
  static const double maxZoom = 19;

  /// Search radius for fetching the individual members of a cluster that's
  /// still grouped at [maxZoom].
  ///
  /// Derived from the grid rather than guessed. At zoom 19 a cell is
  /// 360 / (256·2^19) × 80 degrees of longitude — about 21.6 m at Taiwan's
  /// latitudes, and square once the latitude conversion is right — so no
  /// member can sit more than one diagonal (~30.5 m) from the centroid. 60 m
  /// clears that with room to spare.
  ///
  /// The previous 250 m was an order of magnitude wider than the cell it was
  /// meant to cover, so `/shelters/nearby` reached well into the neighbouring
  /// cells — which are separate clusters — and, because the request asks for
  /// exactly `cluster.count` results, a closer non-member could displace a
  /// real member from the sheet.
  static const double clusterExpandRadiusMeters = 60;

  /// Zoom level for the fallback nationwide view (`taiwanCenter`).
  static const double nationwideZoom = 7.5;

  /// Below this width the UI stays edge-to-edge, mobile-style. At or above
  /// it, the floating panels cap their width instead of stretching across
  /// the whole window.
  static const double desktopBreakpoint = 700;

  /// Fixed width for the search/detail/nearby panels once desktop layout
  /// kicks in.
  static const double desktopPanelWidth = 420;

  /// Initial height fraction of [ShelterDetailSheet]'s mobile bottom sheet.
  /// Shared with `map_page.dart`'s marker-centering math, which needs to
  /// know how much of the screen the sheet covers before the
  /// `DraggableScrollableSheet` itself has laid out.
  static const double mobileDetailSheetInitialFraction = 0.35;
}
