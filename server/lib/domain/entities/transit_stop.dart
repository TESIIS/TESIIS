/// Which TDX subsystem a [TransitStop] came from.
enum TransitMode { bus, tra, thsr }

/// A bus stop or rail station near a shelter, as reported by TDX.
class TransitStop {
  const TransitStop({
    required this.id,
    required this.name,
    required this.mode,
    required this.lat,
    required this.lng,
    required this.distanceMeters,
  });

  /// `StopUID` / `StationUID` — stable across TDX's own updates.
  final String id;

  final String name;
  final TransitMode mode;
  final double lat;
  final double lng;
  final double distanceMeters;
}
