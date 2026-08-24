import 'dart:async';

import '../../core/errors/app_exception.dart';
import '../../core/geo/city_codes.dart';
import '../../data/datasources/external/tdx_client.dart';
import '../../data/mappers/tdx_transit_mapper.dart';
import '../entities/shelter_fields.dart' show ShelterText;
import '../entities/transit_stop.dart';

/// Result of one `nearby` call.
///
/// [partial] is true when at least one of the sources that was actually
/// queried failed — the caller still has *something* useful, just not
/// everything asked for. It says nothing about sources that were never
/// queried because [TransitService.nearby] wasn't given a `city`.
class TransitResult {
  const TransitResult({required this.stops, required this.partial});

  final List<TransitStop> stops;
  final bool partial;
}

/// Fans out to TDX's bus/TRA/THSR resources in parallel and merges the
/// results by distance.
///
/// Bus stops need a city (TDX has no nationwide bus "nearby" resource); rail
/// stations don't. A caller with no city just gets rail results — that's a
/// deliberate omission, not a failure, so it doesn't set [TransitResult.partial].
class TransitService {
  TransitService({required TdxClient client}) : _client = client;

  final TdxClient _client;

  Future<TransitResult> nearby({
    required double lat,
    required double lng,
    String? city,
    required double radiusMeters,
    required int limit,
  }) async {
    final tdxCity = city == null
        ? null
        : CityCodes.byNormalizedName(ShelterText.normalizeName(city))?.tdxName;

    final tasks = <Future<List<TransitStop>>>[
      _client
          .nearbyTraStations(lat: lat, lng: lng, radiusMeters: radiusMeters)
          .then(
            (rows) => TdxTransitMapper.fromRailStations(
              rows,
              mode: TransitMode.tra,
              originLat: lat,
              originLng: lng,
            ),
          ),
      _client
          .nearbyThsrStations(lat: lat, lng: lng, radiusMeters: radiusMeters)
          .then(
            (rows) => TdxTransitMapper.fromRailStations(
              rows,
              mode: TransitMode.thsr,
              originLat: lat,
              originLng: lng,
            ),
          ),
      if (tdxCity != null)
        _client
            .nearbyBusStops(
              tdxCity: tdxCity,
              lat: lat,
              lng: lng,
              radiusMeters: radiusMeters,
            )
            .then(
              (rows) => TdxTransitMapper.fromBusStops(
                rows,
                originLat: lat,
                originLng: lng,
              ),
            ),
    ];

    final results = await Future.wait(
      tasks.map(
        (t) => t.then<List<TransitStop>?>((v) => v).catchError((_) => null),
      ),
    );

    final failures = results.where((r) => r == null).length;
    if (failures == results.length) {
      throw ServiceUnavailableException('All TDX sources failed');
    }

    final stops = [
      for (final r in results)
        if (r != null) ...r,
    ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    final truncated = stops.take(limit).toList();
    final withArrivals = await _attachArrivals(truncated, tdxCity: tdxCity);

    return TransitResult(stops: withArrivals, partial: failures > 0);
  }

  /// Fetches real-time arrivals only for the stops that made the final,
  /// truncated list — not every candidate before truncation, which would
  /// waste calls on stops the caller will never see.
  ///
  /// Deliberately not part of the failure/[TransitResult.partial] accounting
  /// above: real-time arrivals are an enrichment on top of a stop that
  /// already resolved successfully, not a source the caller asked for and
  /// didn't get. A stop simply keeps its default empty [TransitStop.arrivals]
  /// when this fails.
  static const _maxArrivalsPerStop = 3;

  Future<List<TransitStop>> _attachArrivals(
    List<TransitStop> stops, {
    required String? tdxCity,
  }) async {
    // A merged bus stop (see TdxTransitMapper._dedupeBusStops) covers
    // several raw StopUIDs — one different route each — so every one of
    // them has to go into the query, not just the display id.
    final busStopIds = [
      for (final s in stops)
        if (s.mode == TransitMode.bus) ...(s.busStopUids ?? [s.id]),
    ];
    final traStationIds = [
      for (final s in stops)
        if (s.mode == TransitMode.tra && s.stationId != null) s.stationId!,
    ];

    final busArrivalsFuture = busStopIds.isEmpty || tdxCity == null
        ? Future.value(const <String, List<TransitArrival>>{})
        : _client
              .busEstimatedArrivals(tdxCity: tdxCity, stopUids: busStopIds)
              .then(TdxTransitMapper.busArrivalsByStop)
              .catchError((_) => const <String, List<TransitArrival>>{});

    final traArrivalsFutures = {
      for (final stationId in traStationIds)
        stationId: _client
            .traLiveBoard(stationId: stationId)
            .then(TdxTransitMapper.traArrivals)
            .catchError((_) => const <TransitArrival>[]),
    };

    final busArrivalsByUid = await busArrivalsFuture;
    final traArrivals = <String, List<TransitArrival>>{
      for (final entry in traArrivalsFutures.entries)
        entry.key: await entry.value,
    };

    return [
      for (final s in stops)
        switch (s.mode) {
          TransitMode.bus => TransitStop(
            id: s.id,
            name: s.name,
            mode: s.mode,
            lat: s.lat,
            lng: s.lng,
            distanceMeters: s.distanceMeters,
            stationId: s.stationId,
            busStopUids: s.busStopUids,
            arrivals: _mergeBusArrivals(
              s.busStopUids ?? [s.id],
              busArrivalsByUid,
            ),
          ),
          TransitMode.tra when traArrivals[s.stationId] != null => TransitStop(
            id: s.id,
            name: s.name,
            mode: s.mode,
            lat: s.lat,
            lng: s.lng,
            distanceMeters: s.distanceMeters,
            stationId: s.stationId,
            arrivals: traArrivals[s.stationId]!,
          ),
          _ => s,
        },
    ];
  }

  /// A merged bus stop's underlying `StopUID`s each cover a different
  /// route, so their arrivals need combining rather than picking one. Kept
  /// unique per route label — the same route can legitimately appear under
  /// more than one underlying `StopUID` (a loop route serving the same pole
  /// twice, say), and the soonest instance is the useful one to show.
  static List<TransitArrival> _mergeBusArrivals(
    List<String> stopUids,
    Map<String, List<TransitArrival>> byUid,
  ) {
    final byLabel = <String, TransitArrival>{};
    for (final uid in stopUids) {
      for (final arrival in byUid[uid] ?? const []) {
        final existing = byLabel[arrival.label];
        if (existing == null || arrival.minutesUntil < existing.minutesUntil) {
          byLabel[arrival.label] = arrival;
        }
      }
    }
    final merged = byLabel.values.toList()
      ..sort((a, b) => a.minutesUntil.compareTo(b.minutesUntil));
    return merged.length > _maxArrivalsPerStop
        ? merged.sublist(0, _maxArrivalsPerStop)
        : merged;
  }
}
