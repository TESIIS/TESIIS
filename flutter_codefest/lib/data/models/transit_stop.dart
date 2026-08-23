enum TransitMode { bus, tra, thsr }

TransitMode _modeFromJson(String raw) => switch (raw) {
  'bus' => TransitMode.bus,
  'tra' => TransitMode.tra,
  'thsr' => TransitMode.thsr,
  _ => TransitMode.bus,
};

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
  });

  factory TransitStop.fromJson(Map<String, dynamic> json) => TransitStop(
    id: json['id'] as String,
    name: json['name'] as String,
    mode: _modeFromJson(json['mode'] as String),
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    distanceMeters: (json['distanceMeters'] as num).toDouble(),
  );

  final String id;
  final String name;
  final TransitMode mode;
  final double lat;
  final double lng;
  final double distanceMeters;
}
