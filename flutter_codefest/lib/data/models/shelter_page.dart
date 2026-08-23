import 'package:flutter_codefest/data/models/shelter.dart';

/// One page of shelters from a viewport (bbox) query, plus enough metadata
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

  /// True when `shelters.length < total` — the viewport holds more than was
  /// returned, so markers alone would undercount what's actually there.
  final bool truncated;

  /// 'live' / 'cached' / 'snapshot' — see the server's `dataFreshness`.
  final String? dataFreshness;
}
