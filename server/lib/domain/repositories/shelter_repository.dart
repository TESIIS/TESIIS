import '../../data/datasources/local/coordinate_source.dart';
import '../entities/shelter.dart';

abstract class ShelterRepository {
  /// Returns every shelter, with coordinates joined in where available.
  ///
  /// There is deliberately no `q` parameter. Upstream's `?q=` is a no-op —
  /// `q=南港`, `q=圖書館` and `q=zzzz` all return the same 401 records — so
  /// passing keywords through would only defeat caching while filtering
  /// nothing. Keyword matching happens locally in ShelterService.
  Future<List<Shelter>> getAllShelters();

  /// Coverage of the committed coordinate table, for `/api/shelters/stats`.
  CoordinateCoverage get coordinateCoverage;
}
