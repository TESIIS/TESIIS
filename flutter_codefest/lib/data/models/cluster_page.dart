import 'package:flutter_codefest/domain/marker_clustering.dart';

/// One `GET /shelters/clusters` response: the markers for a viewport, plus
/// the metadata that says how current they are.
///
/// Mirrors [ShelterPage]. The clusters call used to return a bare
/// `List<ShelterCluster>` and drop everything else in the body, so the
/// `dataFreshness` the server computes on every response had no way of
/// reaching the screen — the map could be drawn entirely from the committed
/// offline snapshot with nothing telling the user so.
class ClusterPage {
  const ClusterPage({required this.clusters, this.dataFreshness});

  final List<ShelterCluster> clusters;

  /// 'live' / 'cached' / 'snapshot' — see the server's `dataFreshness`.
  final String? dataFreshness;

  factory ClusterPage.fromJson(Map<String, dynamic> json) => ClusterPage(
    clusters: [
      for (final cluster in json['clusters'] as List<dynamic>? ?? const [])
        ShelterCluster.fromServerJson(cluster as Map<String, dynamic>),
    ],
    dataFreshness: json['dataFreshness'] as String?,
  );

  /// Serialises into the shape [fromJson] reads back, for the cache.
  Map<String, dynamic> toJson() => {
    'clusters': [for (final c in clusters) c.toJson()],
    if (dataFreshness != null) 'dataFreshness': dataFreshness,
  };
}
