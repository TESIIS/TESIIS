import 'package:flutter_codefest/data/datasources/api.dart';
import 'package:flutter_codefest/data/models/transit_stop.dart';

/// Bus stops and rail stations near a point, or "unavailable" if TDX isn't
/// configured on the server or the request otherwise failed.
///
/// [available] is false in exactly the cases the server reports 503 for
/// (`GET /api/transit/nearby`'s documented degrade), or when the request
/// itself fails — either way, the shelter detail page must keep working
/// with this section simply absent, never an error banner.
class TransitNearbyResult {
  const TransitNearbyResult({required this.available, this.stops = const []});

  final bool available;
  final List<TransitStop> stops;
}

/// Nearby transit for [lat]/[lng]. [city] (e.g. `臺北市`) enables bus stop
/// results — the server has no nationwide "nearby" bus resource, only a
/// per-city one.
Future<TransitNearbyResult> fetchNearbyTransit({
  required double lat,
  required double lng,
  String? city,
  double radiusMeters = 800,
  int limit = 8,
}) async {
  try {
    final body =
        await ApiService.get(
              '/transit/nearby',
              queryParams: {
                'lat': '$lat',
                'lng': '$lng',
                if (city != null && city.isNotEmpty) 'city': city,
                'radius': '$radiusMeters',
                'limit': '$limit',
              },
            )
            as Map<String, dynamic>;
    return TransitNearbyResult(
      available: true,
      stops: [
        for (final entry in body['data'] as List<dynamic>? ?? const [])
          TransitStop.fromJson(entry as Map<String, dynamic>),
      ],
    );
  } catch (_) {
    // Covers the server's 503 (TDX unconfigured/down) as well as any
    // network failure — this feature degrades silently either way.
    return const TransitNearbyResult(available: false);
  }
}
