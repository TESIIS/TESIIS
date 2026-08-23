import 'shelter.dart';

/// One marker's worth of shelters, as returned by `GET /shelters/clusters` —
/// either a single shelter ([shelter] non-null, [count] == 1) or a group
/// close enough together at the requested zoom to draw as one bubble.
///
/// A multi-member cluster deliberately carries **no** member list: the whole
/// point of the endpoint is that a country-wide view transfers a few hundred
/// centroids instead of thousands of full records. Clients that want member
/// detail zoom in and re-request.
class ShelterCluster {
  const ShelterCluster({
    required this.count,
    required this.lat,
    required this.lng,
    this.shelter,
  });

  final int count;
  final double lat;
  final double lng;

  /// The member for single-shelter clusters, embedded in full so a client
  /// can open its detail view without a follow-up request. Null iff
  /// [count] > 1.
  final Shelter? shelter;
}
