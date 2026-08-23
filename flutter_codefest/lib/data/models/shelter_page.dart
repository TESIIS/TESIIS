import 'package:flutter_codefest/data/models/shelter.dart';

/// One page of shelters from a `GET /shelters` query, plus enough metadata
/// to tell an incomplete view from a complete one.
class ShelterPage {
  const ShelterPage({
    required this.shelters,
    required this.total,
    required this.truncated,
    this.dataFreshness,
  });

  final List<Shelter> shelters;

  /// How many shelters matched the query before `limit` was applied.
  final int total;

  /// True when `shelters.length < total` — the query holds more than was
  /// returned, so the client should offer to load the next page.
  final bool truncated;

  /// 'live' / 'cached' / 'snapshot' — see the server's `dataFreshness`.
  final String? dataFreshness;

  /// Parses the server response body (and, deliberately, the exact same
  /// shape `RequestCache` stores — so cached pages need no second parser).
  factory ShelterPage.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as List<dynamic>? ?? const [];
    return ShelterPage(
      shelters: [
        for (final entry in data)
          Shelter.fromJson(entry as Map<String, dynamic>),
      ],
      total: (json['total'] as num?)?.toInt() ?? data.length,
      truncated: json['truncated'] == true,
      dataFreshness: json['dataFreshness'] as String?,
    );
  }

  /// Serialises into the shape [fromJson] reads back, for the cache.
  Map<String, dynamic> toJson() => {
    'data': [for (final s in shelters) s.toJson()],
    'total': total,
    'truncated': truncated,
  };
}
