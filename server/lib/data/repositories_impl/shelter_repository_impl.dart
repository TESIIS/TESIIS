import '../../core/config/env.dart';
import '../../domain/entities/shelter.dart';
import '../../domain/repositories/shelter_repository.dart';
import '../datasources/external/shelter_api.dart';
import '../datasources/local/coordinate_source.dart';
import '../models/shelter_model.dart';

/// Fetches shelters from Taipei OpenData and joins in coordinates.
///
/// Two things happen here that the layers above rely on:
///
///  1. **Coordinates are attached.** The upstream dataset has none, so without
///     this step every shelter would be unmappable.
///  2. **Upstream responses are cached.** Before, every single request
///     re-downloaded all 401 records from data.taipei. The dataset is
///     republished a few times a year, so a short TTL costs nothing in
///     freshness and removes an external round-trip from the hot path.
class ShelterRepositoryImpl implements ShelterRepository {
  ShelterRepositoryImpl({
    required this.api,
    required this.coordinates,
    Duration? cacheTtl,
  }) : _cacheTtl = cacheTtl ?? Env.cacheTtl;

  final ShelterApi api;
  final CoordinateSource coordinates;
  final Duration _cacheTtl;

  List<Shelter>? _cached;
  DateTime? _cachedAt;

  /// De-duplicates concurrent misses so a burst of requests triggers one fetch.
  Future<List<Shelter>>? _inFlight;

  @override
  CoordinateCoverage get coordinateCoverage => coordinates.coverage;

  Shelter _buildEntityFromModel(ShelterModel m) {
    var x = m.x;
    var y = m.y;
    String? source;
    String? confidence;

    // The dataset has never carried 座標x/座標y, but keep honouring them if
    // upstream ever starts: a first-party coordinate beats a joined one.
    if (x != null && y != null) {
      source = 'upstream';
      confidence = 'exact';
    } else {
      final hit = coordinates.lookup(
        shelterCode: m.shelterCode,
        address: m.address,
        township: m.township,
      );
      if (hit != null) {
        x = hit.lng;
        y = hit.lat;
        source = hit.source.wireName;
        confidence = hit.confidence.wireName;
      }
    }

    return Shelter(
      id: m.id,
      importDate: m.importDate,
      shelterCode: m.shelterCode,
      name: m.name,
      city: m.city,
      zipcode: m.zipcode,
      township: m.township,
      village: m.village,
      address: m.address,
      type: m.type,
      flood: m.flood,
      quake: m.quake,
      landslide: m.landslide,
      tsunami: m.tsunami,
      relief: m.relief,
      accessible: m.accessible,
      indoor: m.indoor,
      outdoor: m.outdoor,
      serviceVillages: m.serviceVillages,
      capacity: m.capacity,
      area: m.area,
      contactName: m.contactName,
      contactPhone: m.contactPhone,
      managerName: m.managerName,
      managerPhone: m.managerPhone,
      notes: m.notes,
      x: x,
      y: y,
      coordinateSource: source,
      coordinateConfidence: confidence,
    );
  }

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

  Future<List<Shelter>> _fetchAll() async {
    try {
      final models = await api.fetchAllShelters(maxItems: Env.maxUpstreamItems);
      final shelters = models
          .map(_buildEntityFromModel)
          .toList(growable: false);
      _cached = shelters;
      _cachedAt = DateTime.now();
      _retryNotBefore = null;
      return shelters;
    } catch (_) {
      // Serve stale data rather than nothing: during a disaster a slightly old
      // shelter list is far more useful than an error page.
      final stale = _cached;
      if (stale != null) {
        _retryNotBefore = DateTime.now().add(staleRetryBackoff);
        return stale;
      }
      rethrow;
    }
  }
}
