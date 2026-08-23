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

    final stops = [for (final r in results) if (r != null) ...r]
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    return TransitResult(
      stops: stops.take(limit).toList(),
      partial: failures > 0,
    );
  }
}
