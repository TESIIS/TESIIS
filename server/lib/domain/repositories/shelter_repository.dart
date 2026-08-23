import '../../data/datasources/local/coordinate_source.dart';
import '../entities/shelter.dart';

/// Where the shelter list currently being served came from.
enum ShelterDataFreshness {
  /// A live NFA fetch within the last TTL window.
  live,

  /// The live fetch is failing; serving a previously-fresh in-memory copy
  /// during the retry backoff window.
  cached,

  /// The live fetch has never succeeded (or failed with nothing cached yet);
  /// serving the committed nationwide snapshot instead.
  snapshot,
}

abstract class ShelterRepository {
  /// Returns every shelter, with coordinates joined in where available.
  ///
  /// There is deliberately no `q` parameter. Upstream's `?q=` is a no-op —
  /// `q=南港`, `q=圖書館` and `q=zzzz` all return the same records — so
  /// passing keywords through would only defeat caching while filtering
  /// nothing. Keyword matching happens locally in ShelterService.
  Future<List<Shelter>> getAllShelters();

  /// Coordinate coverage of the currently-served list, for
  /// `/api/shelters/stats`.
  CoordinateCoverage get coordinateCoverage;

  /// Where the currently-served list came from.
  ShelterDataFreshness get dataFreshness;

  /// When the currently-served list was produced — the live fetch time, or
  /// the snapshot's build time if serving the committed floor. Null before
  /// the first call to [getAllShelters].
  DateTime? get dataUpdatedAt;
}
