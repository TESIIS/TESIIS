import '../../core/geo/distance.dart';
import '../../domain/entities/transit_stop.dart';

/// Converts raw TDX JSON rows (`Bus/Stop/City/{City}`, `Rail/TRA/Station`,
/// `Rail/THSR/Station`) into [TransitStop]s.
///
/// Bus rows use `Stop*` keys, rail rows use `Station*` keys, but both share
/// the same shape otherwise — `{Uid}`, `{...}Name.Zh_tw`, and
/// `{...}Position.PositionLon`/`PositionLat` — verified against a live TDX
/// response before this was written (not guessed from docs).
class TdxTransitMapper {
  const TdxTransitMapper._();

  static List<TransitStop> fromBusStops(
    List<dynamic> rows, {
    required double originLat,
    required double originLng,
  }) => _map(
    rows,
    mode: TransitMode.bus,
    uidKey: 'StopUID',
    nameKey: 'StopName',
    positionKey: 'StopPosition',
    originLat: originLat,
    originLng: originLng,
  );

  static List<TransitStop> fromRailStations(
    List<dynamic> rows, {
    required TransitMode mode,
    required double originLat,
    required double originLng,
  }) => _map(
    rows,
    mode: mode,
    uidKey: 'StationUID',
    nameKey: 'StationName',
    positionKey: 'StationPosition',
    originLat: originLat,
    originLng: originLng,
  );

  static List<TransitStop> _map(
    List<dynamic> rows, {
    required TransitMode mode,
    required String uidKey,
    required String nameKey,
    required String positionKey,
    required double originLat,
    required double originLng,
  }) {
    final out = <TransitStop>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final id = raw[uidKey] as String?;
      final name = (raw[nameKey] as Map?)?['Zh_tw'] as String?;
      final position = raw[positionKey] as Map?;
      final lng = (position?['PositionLon'] as num?)?.toDouble();
      final lat = (position?['PositionLat'] as num?)?.toDouble();
      if (id == null || name == null || lat == null || lng == null) continue;

      out.add(
        TransitStop(
          id: id,
          name: name,
          mode: mode,
          lat: lat,
          lng: lng,
          distanceMeters: haversineMeters(originLat, originLng, lat, lng),
        ),
      );
    }
    return out;
  }
}
