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
  }) => _dedupeBusStops(
    _map(
      rows,
      mode: TransitMode.bus,
      uidKey: 'StopUID',
      nameKey: 'StopName',
      positionKey: 'StopPosition',
      originLat: originLat,
      originLng: originLng,
    ),
  );

  /// How close two same-named bus stop rows have to be to count as "the
  /// same physical pole". Not zero: a live check against real data showed
  /// TDX doesn't always give byte-identical coordinates for what is
  /// obviously the same stop across different route records (sub-meter
  /// jitter) — exact-match grouping missed those, which is exactly why they
  /// showed up as separate rows with the same *rounded* on-screen distance.
  static const _sameStopToleranceMeters = 50.0;

  /// TDX gives each route serving a physical bus stop its own `StopUID` —
  /// a pole served by 10 routes comes back as 10 near-identical rows, same
  /// name, essentially the same position, different `StopUID`. Greedily
  /// clusters rows sharing a name into groups within
  /// [_sameStopToleranceMeters] of each other, keeping every underlying
  /// `StopUID` in [TransitStop.busStopUids] so arrivals can still be looked
  /// up for all of them.
  static List<TransitStop> _dedupeBusStops(List<TransitStop> stops) {
    final groups = <List<TransitStop>>[];
    for (final s in stops) {
      List<TransitStop>? match;
      for (final g in groups) {
        final rep = g.first;
        if (rep.name == s.name &&
            haversineMeters(rep.lat, rep.lng, s.lat, s.lng) <=
                _sameStopToleranceMeters) {
          match = g;
          break;
        }
      }
      if (match != null) {
        match.add(s);
      } else {
        groups.add([s]);
      }
    }
    return [
      for (final group in groups)
        TransitStop(
          id: group.first.id,
          name: group.first.name,
          mode: TransitMode.bus,
          lat: group.first.lat,
          lng: group.first.lng,
          distanceMeters: group.first.distanceMeters,
          busStopUids: [for (final s in group) s.id],
        ),
    ];
  }

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
          // Only rail rows carry this (bus arrivals are looked up by StopUID
          // in a query, not a path segment, so bus stops never need it).
          stationId: raw['StationID'] as String?,
        ),
      );
    }
    return out;
  }

  static const _maxArrivalsPerStop = 3;

  /// Groups `Bus/EstimatedTimeOfArrival` rows by `StopUID`, soonest first.
  ///
  /// Rows with no usable `EstimateTime` (still no vehicle assigned, service
  /// ended for the day, etc.) are skipped rather than guessed at — TDX
  /// doesn't document `StopStatus` clearly enough to trust a specific code
  /// means "safe to show", so this only trusts rows with an actual, sane
  /// (non-negative) estimate.
  static Map<String, List<TransitArrival>> busArrivalsByStop(
    List<dynamic> rows,
  ) {
    final byStop = <String, List<TransitArrival>>{};
    for (final raw in rows) {
      if (raw is! Map) continue;
      final stopUid = raw['StopUID'] as String?;
      final routeName = (raw['RouteName'] as Map?)?['Zh_tw'] as String?;
      final estimateSeconds = (raw['EstimateTime'] as num?)?.toInt();
      if (stopUid == null || routeName == null || estimateSeconds == null) {
        continue;
      }
      final minutes = (estimateSeconds / 60).round();
      if (minutes < 0) continue;

      (byStop[stopUid] ??= []).add(
        TransitArrival(label: routeName, minutesUntil: minutes),
      );
    }
    for (final arrivals in byStop.values) {
      arrivals.sort((a, b) => a.minutesUntil.compareTo(b.minutesUntil));
      if (arrivals.length > _maxArrivalsPerStop) {
        arrivals.removeRange(_maxArrivalsPerStop, arrivals.length);
      }
    }
    return byStop;
  }

  /// Parses `Rail/TRA/LiveBoard` rows into upcoming departures.
  ///
  /// `ScheduledDepartureTime` is a bare "HH:mm:ss" with no date or timezone,
  /// so "now" has to be computed in Taipei local time explicitly — the
  /// server process itself may run in UTC (a VPS commonly does). Results
  /// outside a [-2, 180] minute window are dropped: a live board only ever
  /// lists near-term departures, so anything further out is almost
  /// certainly a same-clock-time entry that actually belongs to the next
  /// calendar day, not a legitimate multi-hour-out arrival — handling the
  /// midnight rollover properly isn't worth it for a display that only
  /// shows the next few minutes anyway.
  static List<TransitArrival> traArrivals(List<dynamic> rows) {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today = DateTime.utc(now.year, now.month, now.day);

    final out = <TransitArrival>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final trainType = (raw['TrainTypeName'] as Map?)?['Zh_tw'] as String?;
      final destination =
          (raw['EndingStationName'] as Map?)?['Zh_tw'] as String?;
      final scheduled = raw['ScheduledDepartureTime'] as String?;
      if (trainType == null || destination == null || scheduled == null) {
        continue;
      }
      final parts = scheduled.split(':');
      if (parts.length != 3) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      final second = int.tryParse(parts[2]);
      if (hour == null || minute == null || second == null) continue;

      final departure = today.add(
        Duration(hours: hour, minutes: minute, seconds: second),
      );
      final minutesUntil = departure.difference(now).inMinutes;
      if (minutesUntil < -2 || minutesUntil > 180) continue;

      final delay = (raw['DelayTime'] as num?)?.toInt();
      out.add(
        TransitArrival(
          label: '$trainType 開往$destination',
          minutesUntil: minutesUntil < 0 ? 0 : minutesUntil,
          delayMinutes: (delay != null && delay > 0) ? delay : null,
        ),
      );
    }
    out.sort((a, b) => a.minutesUntil.compareTo(b.minutesUntil));
    if (out.length > _maxArrivalsPerStop) {
      out.removeRange(_maxArrivalsPerStop, out.length);
    }
    return out;
  }
}
