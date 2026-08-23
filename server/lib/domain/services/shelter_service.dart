// lib/domain/services/shelter_service.dart

import 'dart:math' as math;

import '../../core/geo/city_codes.dart';
import '../../core/geo/taiwan_bounds.dart';
import '../../data/datasources/local/coordinate_source.dart';
import '../entities/shelter.dart';
import '../entities/shelter_cluster.dart';
import '../entities/shelter_fields.dart';
import '../repositories/shelter_repository.dart';

/// Longitude -> Web Mercator world X, 0..1 across the whole world.
double mercatorX(double lng) => (lng + 180) / 360;

/// Latitude -> Web Mercator world Y, 0..1 top to bottom.
///
/// Clamped to the projection's own latitude limit, past which the transform
/// diverges — Taiwan is nowhere near it, but a corrupt coordinate would
/// otherwise produce an infinite bucket index.
double mercatorY(double lat) {
  final latRad = lat.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  return (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2;
}

class ShelterService {
  ShelterService({required this.repository});

  final ShelterRepository repository;

  /// Every shelter, coordinates joined in, served from the repository cache.
  ///
  /// Both endpoints share this one call, so they can never disagree about how
  /// much of the dataset they looked at — previously `/shelters` asked for 3000
  /// records and `/shelters/stats` for 2000.
  Future<List<Shelter>> fetchAllShelters() => repository.getAllShelters();

  CoordinateCoverage get coordinateCoverage => repository.coordinateCoverage;

  ShelterDataFreshness get dataFreshness => repository.dataFreshness;

  DateTime? get dataUpdatedAt => repository.dataUpdatedAt;

  // ---------------------------------------------------------------------
  // Predicates
  // ---------------------------------------------------------------------

  List<String> _normalizeKeywords(String? raw) {
    if (raw == null) return const [];
    return raw
        .split(RegExp(r'[\s,、，]+'))
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  bool _matchesKeywords(Shelter shelter, List<String> keywords) {
    if (keywords.isEmpty) return true;
    final buffer = StringBuffer();

    void push(String? value) {
      final trimmed = (value ?? '').trim();
      if (trimmed.isEmpty) return;
      buffer
        ..write(trimmed.toLowerCase())
        ..write(' ');
    }

    push(shelter.shelterCode);
    push(shelter.name);
    push(shelter.city);
    push(shelter.township);
    push(shelter.village);
    push(shelter.address);
    push(shelter.type);
    push(shelter.serviceVillages);
    push(shelter.notes);
    push(shelter.contactName);
    push(shelter.managerName);

    final haystack = buffer.toString();
    return keywords.every(haystack.contains);
  }

  static String? _hazardValue(Shelter s, String zhKey) {
    switch (zhKey) {
      case '水災':
        return s.flood;
      case '震災':
        return s.quake;
      case '土石流':
        return s.landslide;
      case '海嘯':
        return s.tsunami;
      case '核子事故':
        return s.nuclear;
      case '救濟支站':
        return s.relief;
      case '無障礙設施':
        return s.accessible;
      case '室內':
        return s.indoor;
      case '室外':
        return s.outdoor;
      default:
        return null;
    }
  }

  /// Evaluates the hazard conditions.
  ///
  /// [matchMode] applies **only** here — region, type and keyword are always
  /// ANDed. And only the hazards the caller actually asked about are
  /// evaluated: folding in the other keys made `match=or` true for every
  /// record, since almost every shelter is 'N' for something.
  static bool _hazardsSatisfied(
    Shelter s,
    Map<String, String> hazards,
    String matchMode,
  ) {
    if (hazards.isEmpty) return true;

    var anyMatched = false;
    for (final entry in hazards.entries) {
      final want = entry.value.trim();
      final actual = _hazardValue(s, entry.key);

      final bool ok;
      if (HazardFlag.isAliasRequest(want)) {
        // `?quake=備用` asks for that variant specifically, not for any
        // usable shelter, so a literal 'Y' must not match.
        ok = HazardFlag.matchesAlias(actual, want);
      } else if (HazardFlag.isYes(want)) {
        ok = HazardFlag.isYes(actual);
      } else if (HazardFlag.isNo(want)) {
        ok = HazardFlag.isNo(actual);
      } else {
        // Unrecognised request value: treat the condition as unset.
        ok = true;
      }

      if (matchMode == 'or') {
        if (ok) anyMatched = true;
      } else if (!ok) {
        return false;
      }
    }
    return matchMode == 'or' ? anyMatched : true;
  }

  static List<String>? _mergeVillages(String? single, List<String>? multi) {
    final out = <String>[
      if (single != null && single.trim().isNotEmpty) single.trim(),
      ...?multi?.map((e) => e.trim()).where((e) => e.isNotEmpty),
    ];
    return out.isEmpty ? null : out;
  }

  /// True when [s] has a usable value ('Y') for **any** of the Chinese hazard
  /// keys in [zhKeys] — the "OR within a group" half of the
  /// `disasters`/`spaces` filter semantics. Groups are ANDed against each
  /// other and against everything else by [filterShelters].
  static bool _groupSatisfied(Shelter s, Set<String> zhKeys) =>
      zhKeys.any((zh) => HazardFlag.isYes(_hazardValue(s, zh)));

  /// A shelter matches a village query either by its own 村里 or by appearing
  /// in its 服務里別 list.
  static bool _matchesVillages(Shelter s, List<String> wanted) {
    if (wanted.any((v) => ShelterText.namesEqual(s.village, v))) return true;
    final services = ShelterText.splitVillages(s.serviceVillages);
    return services.any(
      (sv) => wanted.any((v) => ShelterText.namesEqual(sv, v)),
    );
  }

  // ---------------------------------------------------------------------
  // Filtering
  // ---------------------------------------------------------------------

  /// Local filtering by region / type / keyword / hazards / bbox.
  ///
  /// [matchMode] (`and` | `or`) applies to the hazard conditions only.
  ///
  /// [disasters] and [spaces] are the grouped hazard semantics the map app
  /// sends (`disasters=flood,landslide&spaces=indoor`): OR within a group,
  /// AND across the two groups. Keys are Chinese column names (水災/震災/…),
  /// matching [hazards].
  ///
  /// [bbox], when given, is one more AND-ed predicate evaluated right here —
  /// which is the whole point of putting it in `filterShelters` rather than
  /// bolting it onto each endpoint separately: `/shelters`, `/shelters/stats`
  /// and `/shelters/nearby` all call this, so they automatically agree on
  /// what's "in view" instead of three separate implementations drifting
  /// apart.
  List<Shelter> filterShelters({
    required List<Shelter> data,
    String? city,
    String? township,
    String? village,
    List<String>? villages,
    String? type,
    String? keyword,
    Map<String, String>? hazards, // keyed in Chinese: 水災/震災/…
    Set<String>? disasters, // Chinese hazard keys, ORed within the group
    Set<String>? spaces, // Chinese hazard keys, ORed within the group
    String matchMode = 'and',
    GeoBox? bbox,
  }) {
    final hz = hazards ?? const <String, String>{};
    final mm = matchMode.toLowerCase() == 'or' ? 'or' : 'and';
    final disasterKeys = disasters ?? const <String>{};
    final spaceKeys = spaces ?? const <String>{};
    final keywords = _normalizeKeywords(keyword);
    final villagesList = _mergeVillages(village, villages);

    return data
        .where((s) {
          if (city != null &&
              city.isNotEmpty &&
              !ShelterText.namesEqual(s.city, city)) {
            return false;
          }
          if (township != null &&
              township.isNotEmpty &&
              !ShelterText.namesEqual(s.township, township)) {
            return false;
          }
          if (villagesList != null && !_matchesVillages(s, villagesList)) {
            return false;
          }
          if (type != null &&
              type.isNotEmpty &&
              !ShelterText.namesEqual(s.type, type)) {
            return false;
          }
          if (bbox != null) {
            if (!s.hasCoordinate) return false;
            if (!bbox.contains(s.x!, s.y!)) return false;
          }
          if (!_hazardsSatisfied(s, hz, mm)) return false;
          if (disasterKeys.isNotEmpty && !_groupSatisfied(s, disasterKeys)) {
            return false;
          }
          if (spaceKeys.isNotEmpty && !_groupSatisfied(s, spaceKeys)) {
            return false;
          }
          return _matchesKeywords(s, keywords);
        })
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------
  // Clustering
  // ---------------------------------------------------------------------

  /// Grid-buckets [data] (already filtered by the caller) into clusters
  /// whose on-screen footprint is roughly [cellPixels] wide at [zoom].
  ///
  /// Mirrors the app's own `marker_clustering.dart`, kept algorithmically
  /// identical so a marker set rendered client-side (search pages) and one
  /// rendered server-side (viewport queries) break apart at the same zooms.
  /// Cell size comes from the standard Web Mercator degrees-per-pixel
  /// formula, so there is no per-zoom tuning table to maintain.
  ///
  /// Shelters without coordinates are dropped — a cluster is a map marker,
  /// and there is nowhere to put one without a coordinate.
  List<ShelterCluster> clusterShelters({
    required List<Shelter> data,
    required double zoom,
    double cellPixels = 80,
    int minPointsToCluster = 2,
  }) {
    final located = [
      for (final s in data)
        if (s.hasCoordinate) s,
    ];
    if (located.isEmpty) return const [];

    // Cell size in Web Mercator world units (0..1 on both axes), where one
    // unit is the same number of pixels horizontally and vertically at a
    // given zoom. Bucketing here is what makes a cell actually square on
    // screen; bucketing in degrees cannot, because a degree of latitude and
    // a degree of longitude are different distances on screen.
    final cell = cellPixels / (256 * math.pow(2, zoom));

    final buckets = <(int, int), List<Shelter>>{};
    for (final shelter in located) {
      final cellX = (mercatorX(shelter.x!) / cell).floor();
      final cellY = (mercatorY(shelter.y!) / cell).floor();
      buckets.putIfAbsent((cellX, cellY), () => <Shelter>[]).add(shelter);
    }

    final clusters = <ShelterCluster>[];
    for (final members in buckets.values) {
      if (members.length < minPointsToCluster) {
        for (final s in members) {
          clusters.add(
            ShelterCluster(count: 1, lat: s.y!, lng: s.x!, shelter: s),
          );
        }
        continue;
      }
      final centerLat =
          members.map((s) => s.y!).reduce((a, b) => a + b) / members.length;
      final centerLng =
          members.map((s) => s.x!).reduce((a, b) => a + b) / members.length;
      clusters.add(
        ShelterCluster(count: members.length, lat: centerLat, lng: centerLng),
      );
    }
    return clusters;
  }

  // ---------------------------------------------------------------------
  // Statistics
  // ---------------------------------------------------------------------

  static Map<String, dynamic> _shelterSummary(Shelter s) => {
    '名稱': s.name,
    '門牌地址': s.address,
    '類型': s.type,
    '村里': s.village,
    '服務里別': ShelterText.splitVillages(s.serviceVillages),
    '座標x': s.x,
    '座標y': s.y,
  };

  /// Coordinate coverage for one region-scoped slice of shelters, mirroring
  /// the shape of the dataset-wide [CoordinateCoverage.toJson] but computed
  /// per city/township/village so a data-quality view can find where the
  /// gaps actually are, not just how many there are overall.
  static Map<String, dynamic> _coordinateQuality(List<Shelter> shelters) {
    var withCoordinates = 0;
    final bySource = <String, int>{};
    final byConfidence = <String, int>{};
    for (final s in shelters) {
      if (!s.hasCoordinate) continue;
      withCoordinates++;
      final source = s.coordinateSource ?? 'none';
      bySource[source] = (bySource[source] ?? 0) + 1;
      final confidence = s.coordinateConfidence ?? 'none';
      byConfidence[confidence] = (byConfidence[confidence] ?? 0) + 1;
    }
    return {
      'total': shelters.length,
      'withCoordinates': withCoordinates,
      'missing': shelters.length - withCoordinates,
      'bySource': bySource,
      'byConfidence': byConfidence,
    };
  }

  Map<String, dynamic> computeStats({
    required List<Shelter> data,
    String? city,
    String? township,
    String? village,
    List<String>? villages,
    String? type,
    Map<String, String>? hazards,
    Set<String>? disasters,
    Set<String>? spaces,
    String? keyword,
    String matchMode = 'and',
    GeoBox? bbox,
    // Off by default. At Taipei's 401 records, an unfiltered response
    // embedding every shelter's full detail at every city/township/village
    // level was small enough not to matter. At ~5,850 nationwide records the
    // same shape is multi-megabyte JSON with each shelter repeated 2-3
    // times — the first endpoint the nationwide expansion would break.
    // ?include=items,shelters opts back in for callers that want them (the
    // data-quality page does not; it only reads coordinateQuality).
    bool includeItems = false,
    bool includeShelters = false,
    // Same reasoning as the two above, one level deeper — and measurably the
    // level that mattered. An unfiltered nationwide response is 1,609,270
    // bytes, of which 1,534,027 (95.3%) is the per-village breakdown across
    // 8,787 village entries. The only consumer, the app's data-quality page,
    // reads township-level coordinateQuality and never descends into
    // `villages`, so that 1.5 MB was transferred and parsed to be discarded.
    // ?include=villages opts back in.
    bool includeVillages = false,
  }) {
    // Reuse the exact predicate /shelters uses, so the two endpoints cannot
    // drift apart in what they consider a match.
    final filtered = filterShelters(
      data: data,
      city: city,
      township: township,
      village: village,
      villages: villages,
      type: type,
      keyword: keyword,
      hazards: hazards,
      disasters: disasters,
      spaces: spaces,
      matchMode: matchMode,
      bbox: bbox,
    );

    final typeCounts = <String, int>{};
    // city -> township -> village -> shelter ids.
    //
    // Village counts are keyed by shelter id throughout, because a shelter is
    // reachable from a village both through its own 村里 and through its
    // 服務里別 and must not be counted twice.
    final cityShelters = <String, List<Shelter>>{};
    final townshipShelters = <String, Map<String, List<Shelter>>>{};

    for (final s in filtered) {
      typeCounts[s.type] = (typeCounts[s.type] ?? 0) + 1;
      cityShelters.putIfAbsent(s.city, () => <Shelter>[]).add(s);
      townshipShelters
          .putIfAbsent(s.city, () => <String, List<Shelter>>{})
          .putIfAbsent(s.township, () => <Shelter>[])
          .add(s);
    }

    List<Map<String, dynamic>> villagesOf(List<Shelter> shelters) {
      final seen = <String, Set<int>>{};
      final objects = <String, List<Shelter>>{};

      void add(String name, Shelter s) {
        if (name.isEmpty) return;
        if (seen.putIfAbsent(name, () => <int>{}).add(s.id)) {
          objects.putIfAbsent(name, () => <Shelter>[]).add(s);
        }
      }

      for (final s in shelters) {
        add(s.village, s);
        for (final sv in ShelterText.splitVillages(s.serviceVillages)) {
          add(sv, s);
        }
      }

      final entries = seen.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length));
      return [
        for (final e in entries)
          {
            'village': e.key,
            'count': e.value.length,
            'coordinateQuality': _coordinateQuality(
              objects[e.key] ?? const <Shelter>[],
            ),
            if (includeShelters)
              'shelters': [
                for (final s in objects[e.key] ?? const <Shelter>[])
                  _shelterSummary(s),
              ],
          },
      ];
    }

    final byRegion = <Map<String, dynamic>>[];
    for (final cityEntry in cityShelters.entries) {
      final towns = <Map<String, dynamic>>[];
      for (final t in (townshipShelters[cityEntry.key] ?? const {}).entries) {
        towns.add({
          'township': t.key,
          'total': t.value.length,
          'coordinateQuality': _coordinateQuality(t.value),
          if (includeVillages) 'villages': villagesOf(t.value),
          if (includeShelters)
            'shelters': [for (final s in t.value) _shelterSummary(s)],
        });
      }
      towns.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
      byRegion.add({
        'city': cityEntry.key,
        'total': cityEntry.value.length,
        'coordinateQuality': _coordinateQuality(cityEntry.value),
        'townships': towns,
      });
    }
    byRegion.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));

    final byType = [
      for (final e in typeCounts.entries) {'type': e.key, 'count': e.value},
    ]..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    return {
      'total': filtered.length,
      'byType': byType,
      'byRegion': byRegion,
      if (includeItems)
        'items': [
          for (final s in filtered)
            {
              '名稱': s.name,
              '門牌地址': s.address,
              '縣市': s.city,
              '鄉鎮': s.township,
              '村里': s.village,
              '服務里別': ShelterText.splitVillages(s.serviceVillages),
              '類型': s.type,
              '震災': HazardFlag.normalizeForOutput(s.quake),
              '土石流': HazardFlag.normalizeForOutput(s.landslide),
              '海嘯': HazardFlag.normalizeForOutput(s.tsunami),
              '座標x': s.x,
              '座標y': s.y,
            },
        ],
    };
  }

  // ---------------------------------------------------------------------
  // Regions
  // ---------------------------------------------------------------------

  /// `GET /api/regions` — the 22 counties (or one county's townships, when
  /// [city] is given), each with a shelter count and coordinate-quality
  /// breakdown. Deliberately excludes `shelters`/`items`, same reasoning as
  /// [computeStats]'s `includeShelters`/`includeItems`: this is meant to be
  /// small enough to fetch on every app launch, not another multi-megabyte
  /// endpoint.
  Map<String, dynamic> computeRegions({
    required List<Shelter> data,
    String? city,
  }) {
    if (city != null && city.isNotEmpty) {
      final filtered = filterShelters(data: data, city: city);
      final byTownship = <String, List<Shelter>>{};
      for (final s in filtered) {
        byTownship.putIfAbsent(s.township, () => <Shelter>[]).add(s);
      }
      final townships = [
        for (final entry in byTownship.entries)
          {
            'township': entry.key,
            'count': entry.value.length,
            'coordinateQuality': _coordinateQuality(entry.value),
          },
      ]..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
      return {'total': filtered.length, 'city': city, 'townships': townships};
    }

    // Keyed by normalised county name (臺→台 folded) so it lines up with
    // TaiwanBounds.counties regardless of which spelling the data uses.
    final byCounty = <String, List<Shelter>>{};
    for (final s in data) {
      byCounty
          .putIfAbsent(ShelterText.normalizeName(s.city), () => <Shelter>[])
          .add(s);
    }

    final regions = [
      for (final county in TaiwanBounds.counties)
        if (CityCodes.byNormalizedName(county) case final code?)
          {
            'cityCode': code.isoCode,
            'city': code.displayName,
            'count': (byCounty[county] ?? const []).length,
            'coordinateQuality': _coordinateQuality(
              byCounty[county] ?? const [],
            ),
          },
    ]..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    return {'total': data.length, 'regions': regions};
  }
}
