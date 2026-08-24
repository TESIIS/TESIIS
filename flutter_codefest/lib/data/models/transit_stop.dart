enum TransitMode { bus, tra, thsr }

TransitMode _modeFromJson(String raw) => switch (raw) {
  'bus' => TransitMode.bus,
  'tra' => TransitMode.tra,
  'thsr' => TransitMode.thsr,
  _ => TransitMode.bus,
};

/// One upcoming departure at a [TransitStop].
class TransitArrival {
  const TransitArrival({
    required this.label,
    required this.minutesUntil,
    this.delayMinutes,
  });

  factory TransitArrival.fromJson(Map<String, dynamic> json) => TransitArrival(
    label: json['label'] as String,
    minutesUntil: json['minutes'] as int,
    delayMinutes: json['delayMinutes'] as int?,
  );

  /// Bus route number ("299") or rail description ("區間 開往新竹").
  final String label;

  final int minutesUntil;

  /// Minutes late. Null (not zero) when on time.
  final int? delayMinutes;
}

/// A bus stop or rail station near a shelter, as served by
/// `GET /api/transit/nearby`.
class TransitStop {
  const TransitStop({
    required this.id,
    required this.name,
    required this.mode,
    required this.lat,
    required this.lng,
    required this.distanceMeters,
    this.arrivals = const [],
  });

  factory TransitStop.fromJson(Map<String, dynamic> json) => TransitStop(
    id: json['id'] as String,
    name: json['name'] as String,
    mode: _modeFromJson(json['mode'] as String),
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    distanceMeters: (json['distanceMeters'] as num).toDouble(),
    arrivals: [
      for (final a in json['arrivals'] as List<dynamic>? ?? const [])
        TransitArrival.fromJson(a as Map<String, dynamic>),
    ],
  );

  final String id;
  final String name;
  final TransitMode mode;
  final double lat;
  final double lng;
  final double distanceMeters;

  /// Upcoming departures, soonest first. Empty (never null) when real-time
  /// data isn't available for this stop.
  final List<TransitArrival> arrivals;
}
