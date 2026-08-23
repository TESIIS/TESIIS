import '../../core/config/env.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/entities/shelter.dart';
import '../../domain/repositories/shelter_repository.dart';
import '../datasources/external/nfa_shelter_api.dart';
import '../datasources/local/coordinate_source.dart' show CoordinateCoverage;
import '../datasources/local/shelter_snapshot_source.dart';
import '../mappers/nfa_shelter_mapper.dart';

/// Fetches shelters from the nationwide NFA point file.
///
/// Three things happen here that the layers above rely on:
///
///  1. **Upstream responses are cached** (TTL from `Env.cacheTtl`), so a burst
///     of requests doesn't re-download ~6,000 records on every single one.
///  2. **A failing upstream serves stale data instead of erroring**, with a
///     backoff so an outage doesn't turn every request into a fresh retry
///     storm — same reasoning as before the nationwide expansion.
///  3. **A live fetch that looks implausible (too few rows, missing
///     counties) is treated as a failure**, not adopted. This is new: it
///     stops a truncated or restructured upstream response from silently
///     blanking most of the map.
///
/// When there is no cache to fall back on at all (first request, upstream
/// down), this now serves the committed [ShelterSnapshotSource] rather than
/// throwing — a strictly stronger "stale beats nothing" guarantee than the
/// Taipei-only version had, since there is always a floor to fall back to.
class ShelterRepositoryImpl implements ShelterRepository {
  ShelterRepositoryImpl({
    required this.api,
    required this.snapshot,
    Duration? cacheTtl,
  }) : _cacheTtl = cacheTtl ?? Env.cacheTtl;

  final NfaShelterApi api;
  final ShelterSnapshotSource snapshot;
  final Duration _cacheTtl;

  List<Shelter>? _cached;
  DateTime? _cachedAt;
  ShelterDataFreshness _freshness = ShelterDataFreshness.snapshot;

  /// De-duplicates concurrent misses so a burst of requests triggers one fetch.
  Future<List<Shelter>>? _inFlight;

  @override
  CoordinateCoverage get coordinateCoverage {
    final cached = _cached;
    final data = cached ?? snapshot.shelters;
    if (data.isEmpty) return snapshot.coverage;
    final withCoordinates = data.where((s) => s.hasCoordinate).length;
    final bySource = <String, int>{};
    for (final s in data) {
      final key = s.coordinateSource ?? 'none';
      bySource[key] = (bySource[key] ?? 0) + 1;
    }
    return CoordinateCoverage(
      total: data.length,
      withCoordinates: withCoordinates,
      bySource: bySource,
    );
  }

  @override
  ShelterDataFreshness get dataFreshness => _freshness;

  @override
  DateTime? get dataUpdatedAt => _cachedAt ?? snapshot.snapshotUpdatedAt;

  bool get _isFresh {
    final at = _cachedAt;
    return _cached != null &&
        at != null &&
        DateTime.now().difference(at) < _cacheTtl;
  }

  /// How long to keep serving stale data before trying a failing upstream
  /// again.
  ///
  /// Without this, an upstream outage turns every single request into a fresh
  /// attempt: latency for the caller, and a retry storm aimed at a dependency
  /// that is already unwell.
  static const staleRetryBackoff = Duration(seconds: 30);

  DateTime? _retryNotBefore;

  bool get _inBackoff {
    final until = _retryNotBefore;
    return until != null && DateTime.now().isBefore(until);
  }

  @override
  Future<List<Shelter>> getAllShelters() async {
    if (_isFresh) return _cached!;

    // Upstream is known to be failing and we still have something to serve.
    final stale = _cached;
    if (stale != null && _inBackoff) return stale;

    final pending = _inFlight;
    if (pending != null) return pending;

    final future = _fetchAll();
    _inFlight = future;
    try {
      return await future;
    } finally {
      _inFlight = null;
    }
  }

  /// Rejects a live fetch that is technically well-formed JSON/CSV but
  /// obviously not the whole dataset: e.g. upstream started returning a
  /// truncated or restructured file. Falling back to the snapshot in that
  /// case beats silently serving a half-empty map.
  ///
  /// Compares against the committed snapshot's own row/county counts rather
  /// than a hardcoded "22 counties" — that makes this testable with a small
  /// fixture snapshot, and it's the more honest comparison anyway: what
  /// matters is whether a live fetch looks worse than the floor already on
  /// disk, not an assumption baked into this class about what the dataset
  /// currently contains.
  bool _looksImplausible(List<Shelter> liveShelters) {
    final floorCount = snapshot.shelters.length;
    if (floorCount > 0 && liveShelters.length < floorCount * 0.8) return true;

    final snapshotCounties = snapshot.shelters
        .map((s) => s.city.replaceAll('臺', '台'))
        .toSet();
    if (snapshotCounties.isEmpty) return false;
    final liveCounties = liveShelters
        .map((s) => s.city.replaceAll('臺', '台'))
        .toSet();
    return liveCounties.length < snapshotCounties.length * 0.8;
  }

  Future<List<Shelter>> _fetchAll() async {
    try {
      final rawRows = await api.fetchRawRows();
      final ordinals = NfaShelterMapper.assignOrdinals(rawRows);
      final fetchedAt = DateTime.now().toUtc();

      final shelters = <Shelter>[];
      for (var i = 0; i < rawRows.length; i++) {
        final result = NfaShelterMapper.toShelter(
          rawRows[i],
          rowIndex: i,
          ordinal: ordinals[i],
          sourceUpdatedAt: fetchedAt,
        );
        if (result.shelter != null) shelters.add(result.shelter!);
      }

      if (_looksImplausible(shelters)) {
        throw ServerException(
          'Live NFA fetch failed the sanity check '
          '(${shelters.length} shelters, expected roughly ${snapshot.shelters.length})',
        );
      }

      _cached = shelters;
      _cachedAt = fetchedAt;
      _retryNotBefore = null;
      _freshness = ShelterDataFreshness.live;
      return shelters;
    } catch (_) {
      // Serve stale data rather than nothing: during a disaster a slightly old
      // shelter list is far more useful than an error page.
      final stale = _cached;
      _retryNotBefore = DateTime.now().add(staleRetryBackoff);
      if (stale != null) {
        _freshness = ShelterDataFreshness.cached;
        return stale;
      }
      // No stale in-memory copy at all — fall back to the committed
      // snapshot rather than rethrowing.
      _freshness = ShelterDataFreshness.snapshot;
      return snapshot.shelters;
    }
  }
}
