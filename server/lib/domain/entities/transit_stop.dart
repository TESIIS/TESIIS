/// Which TDX subsystem a [TransitStop] came from.
enum TransitMode { bus, tra, thsr }

/// One upcoming departure at a [TransitStop].
class TransitArrival {
  const TransitArrival({
    required this.label,
    required this.minutesUntil,
    this.delayMinutes,
  });

  /// Bus route number ("299") or rail description ("區間 開往新竹").
  final String label;

  final int minutesUntil;

  /// Minutes late. Null (not zero) when on time — the caller shouldn't have
  /// to distinguish "known on-time" from "delay not reported".
  final int? delayMinutes;
}

/// A bus stop or rail station near a shelter, as reported by TDX.
class TransitStop {
  const TransitStop({
    required this.id,
    required this.name,
    required this.mode,
    required this.lat,
    required this.lng,
    required this.distanceMeters,
    this.stationId,
    this.arrivals = const [],
    this.busStopUids,
  });

  /// `StopUID` / `StationUID` — stable across TDX's own updates.
  final String id;

  final String name;
  final TransitMode mode;
  final double lat;
  final double lng;
  final double distanceMeters;

  /// The bare numeric `StationID` TDX rail endpoints use as a path segment
  /// (e.g. `Rail/TRA/LiveBoard/Station/{stationId}`) — distinct from [id]
  /// (`StationUID`, e.g. `TRA-1000`). Null for bus stops, which don't need
  /// it: the bus arrivals endpoint filters by `StopUID` in a query, not a
  /// path segment.
  final String? stationId;

  /// Upcoming departures, soonest first. Empty (never null) when real-time
  /// data isn't available for this stop — thsr always, or bus/tra when the
  /// live query failed.
  final List<TransitArrival> arrivals;

  /// For bus stops only: every raw `StopUID` merged into this one display
  /// entry (TDX gives each route its own `StopUID` at the same physical
  /// pole, so one real-world stop often arrives as many identical-looking
  /// rows — see [TdxTransitMapper.fromBusStops]). Null for rail, and for bus
  /// stops that weren't part of a merge (a list of just [id] either way, so
  /// callers can treat "null" and "just this stop" the same).
  final List<String>? busStopUids;
}
