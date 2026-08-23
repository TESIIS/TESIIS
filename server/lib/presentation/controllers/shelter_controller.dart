// lib/presentation/controllers/shelter_controller.dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/config/env.dart';
import '../../core/geo/taiwan_bounds.dart' show GeoBox;
import '../../domain/entities/shelter.dart';
import '../../domain/entities/shelter_fields.dart';
import '../../domain/services/shelter_service.dart';

/// The query shared by every endpoint, parsed once.
///
/// Both handlers used to parse the same 16 parameters independently, which is
/// how `/shelters/stats` ended up echoing back a `filters` object that silently
/// omitted `villages`.
class _ShelterQuery {
  _ShelterQuery({
    required this.q,
    required this.city,
    required this.township,
    required this.village,
    required this.villages,
    required this.type,
    required this.hazards,
    required this.disasters,
    required this.spaces,
    required this.matchMode,
    required this.bbox,
    required this.bboxError,
    required this.groupError,
    required this.hazardError,
  });

  final String? q;
  final String? city;
  final String? township;
  final String? village;
  final List<String>? villages;
  final String? type;
  final Map<String, String> hazards;

  /// Chinese hazard keys from `?disasters=flood,landslide` (mapped through
  /// [_hazardAliases]) — ORed within the group by the service.
  final Set<String>? disasters;

  /// Same, for `?spaces=indoor,outdoor`.
  final Set<String>? spaces;

  final String matchMode;

  /// Parsed `?bbox=minLng,minLat,maxLng,maxLat`, or null if not given.
  final GeoBox? bbox;

  /// Set instead of [bbox] when the raw value fails validation, so the
  /// handler can return a 400 with a useful message rather than silently
  /// ignoring a malformed box.
  final String? bboxError;

  /// Set instead of [disasters]/[spaces] when a group carries a key that is
  /// not a known hazard, so the handler can 400 rather than silently
  /// dropping a filter the client thought it applied.
  final String? groupError;

  /// Set instead of [hazards] when a flat hazard parameter carries a value
  /// outside the Y/N vocabulary — see [_parseHazards].
  final String? hazardError;

  /// The first parse error, if any. Every handler rejects on this before
  /// touching the data, so a filter that could not be applied never comes
  /// back as a 200 full of unfiltered records.
  String? get validationError => bboxError ?? groupError ?? hazardError;

  /// A box larger than this is rejected: the whole point of `bbox` is to let
  /// a client ask for "what's on screen", not download the entire country in
  /// one response. ~2° is generous enough for any real map viewport.
  static const _maxBboxDegrees = 2.0;

  /// `/shelters/clusters` caps bbox far more loosely — its response is
  /// centroids, not records, so payload size is not a reason to force the
  /// client to tile a country-wide viewport into 2° requests.
  static const _maxClusterBboxDegrees = 6.0;

  static (GeoBox?, String?) _parseBbox(String? raw, double maxDegrees) {
    if (raw == null || raw.isEmpty) return (null, null);
    final parts = raw.split(',');
    if (parts.length != 4) {
      return (null, 'bbox must be "minLng,minLat,maxLng,maxLat"');
    }
    final values = parts.map((p) => double.tryParse(p.trim())).toList();
    if (values.any((v) => v == null)) {
      return (null, 'bbox must contain 4 numbers');
    }
    final minLng = values[0]!;
    final minLat = values[1]!;
    final maxLng = values[2]!;
    final maxLat = values[3]!;
    if (minLng >= maxLng || minLat >= maxLat) {
      return (null, 'bbox min must be less than max on each axis');
    }
    if (maxLng - minLng > maxDegrees || maxLat - minLat > maxDegrees) {
      return (
        null,
        'bbox must not exceed $maxDegrees° on either axis — '
            'use GET /api/regions for a country-wide view',
      );
    }
    return (GeoBox(minLng, maxLng, minLat, maxLat), null);
  }

  /// Hazard parameters, accepted under both an English and a Chinese name.
  static const _hazardAliases = {
    'flood': '水災',
    'quake': '震災',
    'landslide': '土石流',
    'tsunami': '海嘯',
    'nuclear': '核子事故',
    'relief': '救濟支站',
    'accessible': '無障礙設施',
    'indoor': '室內',
    'outdoor': '室外',
  };

  /// Validates the *values* of the hazard parameters.
  ///
  /// An unrecognised value used to be treated as "condition unset", which
  /// made a typo silently return the whole dataset: `?flood=BOGUS` answered
  /// 200 with all 5,854 records, indistinguishable from an unfiltered query.
  /// For a shelter lookup that is the worst possible failure mode — the
  /// caller believes they are looking at flood-capable shelters only. A
  /// filter that could not be applied is now an error, same as a malformed
  /// bbox or an unknown group key.
  static (Map<String, String>, String?) _parseHazards(
    Map<String, String> params,
  ) {
    final hazards = <String, String>{};
    for (final entry in _hazardAliases.entries) {
      final value = params[entry.key] ?? params[entry.value];
      if (value == null || value.isEmpty) continue;
      if (!HazardFlag.isYes(value) &&
          !HazardFlag.isNo(value) &&
          !HazardFlag.isAliasRequest(value)) {
        return (
          const {},
          '${entry.key} has unknown value "$value" '
              '(valid: Y, N, or one of ${HazardFlag.yesAliases.join(", ")})',
        );
      }
      hazards[entry.value] = value;
    }
    return (hazards, null);
  }

  /// The keys a group parameter accepts, mapped to the Chinese column names
  /// the service filters on. English-only on the wire for groups — the flat
  /// `?flood=Y` params stay bilingual for compatibility.
  static const _groupAliases = {
    'disasters': {
      'flood': '水災',
      'earthquake': '震災',
      'landslide': '土石流',
      'tsunami': '海嘯',
      'nuclear': '核子事故',
    },
    'spaces': {'indoor': '室內', 'outdoor': '室外'},
  };

  static (Set<String>?, String?) _parseGroup(String? raw, String param) {
    if (raw == null || raw.trim().isEmpty) return (null, null);
    final aliases = _groupAliases[param]!;
    final tokens = raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final unknown = tokens.where((t) => !aliases.containsKey(t));
    if (unknown.isNotEmpty) {
      final valid = aliases.keys.join(', ');
      return (
        null,
        '$param contains unknown key "${unknown.first}" (valid: $valid)',
      );
    }
    return ({for (final t in tokens) aliases[t]!}, null);
  }

  factory _ShelterQuery.from(
    Request request, {
    double maxBboxDegrees = _maxBboxDegrees,
  }) {
    final params = request.url.queryParameters;

    final (hazards, hazardError) = _parseHazards(params);

    // `villages` accepts either repeated parameters (?villages=A&villages=B)
    // or one delimited value (?villages=A,B).
    final rawVillages =
        request.url.queryParametersAll['villages'] ?? const <String>[];
    final villages = <String>[
      for (final value in rawVillages) ...ShelterText.splitVillages(value),
    ];

    final (bbox, bboxError) = _parseBbox(params['bbox'], maxBboxDegrees);

    final (disasters, disastersError) = _parseGroup(
      params['disasters'],
      'disasters',
    );
    final (spaces, spacesError) = _parseGroup(params['spaces'], 'spaces');

    return _ShelterQuery(
      q: params['q'],
      city: params['city'] ?? params['縣市'],
      township: params['township'] ?? params['鄉鎮'],
      village: params['village'] ?? params['村里'],
      villages: villages.isEmpty ? null : villages,
      type: params['type'] ?? params['類型'],
      hazards: hazards,
      disasters: disasters,
      spaces: spaces,
      matchMode: (params['match'] ?? 'and').toLowerCase() == 'or'
          ? 'or'
          : 'and',
      bbox: bbox,
      bboxError: bboxError,
      groupError: disastersError ?? spacesError,
      hazardError: hazardError,
    );
  }

  Map<String, dynamic> toJson() => {
    if (q != null) 'q': q,
    if (city != null) 'city': city,
    if (township != null) 'township': township,
    if (village != null) 'village': village,
    if (villages != null) 'villages': villages,
    if (type != null) 'type': type,
    if (hazards.isNotEmpty) 'hazards': hazards,
    if (disasters != null) 'disasters': disasters!.toList(),
    if (spaces != null) 'spaces': spaces!.toList(),
    'match': matchMode,
    if (bbox != null)
      'bbox': [bbox!.minLng, bbox!.minLat, bbox!.maxLng, bbox!.maxLat],
  };
}

class ShelterController {
  ShelterController({required this.service});

  final ShelterService service;
  final Logger _logger = Logger('ShelterController');

  Router get router {
    final r = Router();
    r.get('/shelters', _getShelters);
    r.get('/shelters/clusters', _getShelterClusters);
    r.get('/shelters/stats', _getShelterStats);
    r.get('/shelters/nearby', _getNearbyShelters);
    r.get('/regions', _getRegions);
    return r;
  }

  static const _jsonHeaders = {'content-type': 'application/json'};

  Response _ok(Object body) =>
      Response.ok(jsonEncode(body), headers: _jsonHeaders);

  Response _badRequest(String message) => Response.badRequest(
    body: jsonEncode({'success': false, 'message': message}),
    headers: _jsonHeaders,
  );

  /// Logs the detail, returns a generic message.
  ///
  /// These handlers used to put `e.toString()` straight into the response body,
  /// which leaks upstream URLs, file paths and stack detail to any caller.
  Response _serverError(String route, Object error, StackTrace stackTrace) {
    _logger.severe('Error in $route', error, stackTrace);
    return Response.internalServerError(
      body: jsonEncode({
        'success': false,
        'message': 'Internal server error. See server logs for details.',
      }),
      headers: _jsonHeaders,
    );
  }

  List<Shelter> _applyFilters(List<Shelter> data, _ShelterQuery query) =>
      service.filterShelters(
        data: data,
        city: query.city,
        township: query.township,
        village: query.village,
        villages: query.villages,
        type: query.type,
        keyword: query.q,
        hazards: query.hazards.isEmpty ? null : query.hazards,
        disasters: query.disasters,
        spaces: query.spaces,
        matchMode: query.matchMode,
        bbox: query.bbox,
      );

  /// Metadata every list-shaped endpoint carries additively, so a client can
  /// tell live data from a stale cache or the committed offline snapshot
  /// without a separate `/healthz` round-trip.
  Map<String, dynamic> _dataMeta() => {
    'dataSource': 'nfa_point_file',
    'dataFreshness': service.dataFreshness.name,
    'dataUpdatedAt': service.dataUpdatedAt?.toIso8601String(),
  };

  Map<String, dynamic> _toJson(Shelter e, {double? distanceMeters}) => {
    'id': e.id,
    'importDate': e.importDate?.toIso8601String(),
    '收容所編號': e.shelterCode,
    '名稱': e.name,
    '縣市': e.city,
    '郵遞區號': e.zipcode,
    '鄉鎮': e.township,
    '村里': e.village,
    '門牌地址': e.address,
    '類型': e.type,
    '水災': HazardFlag.normalizeForOutput(e.flood),
    '震災': HazardFlag.normalizeForOutput(e.quake),
    '土石流': HazardFlag.normalizeForOutput(e.landslide),
    '海嘯': HazardFlag.normalizeForOutput(e.tsunami),
    // Only the nationwide NFA dataset carries this; always null for records
    // built before the nationwide expansion.
    '核子事故': HazardFlag.normalizeForOutput(e.nuclear),
    '救濟支站': HazardFlag.normalizeForOutput(e.relief),
    '無障礙設施': HazardFlag.normalizeForOutput(e.accessible),
    '室內': HazardFlag.normalizeForOutput(e.indoor),
    '室外': HazardFlag.normalizeForOutput(e.outdoor),
    '服務里別': ShelterText.splitVillages(e.serviceVillages),
    '容納人數': e.capacity,
    '收容所面積(平方公尺)': e.area,
    '聯絡人姓名': e.contactName,
    '聯絡人連絡電話': e.contactPhone,
    '管理人姓名': e.managerName,
    '管理人連絡電話': e.managerPhone,
    '備考': e.notes,
    '座標x': e.x,
    '座標y': e.y,
    // Null for the shelters the coordinate table could not locate, so a
    // client can tell "no coordinate" from "coordinate we are unsure of".
    '座標來源': e.coordinateSource,
    '座標精度': e.coordinateConfidence,
    if (distanceMeters != null) '距離公尺': distanceMeters.round(),
  };

  Future<Response> _getShelters(Request request) async {
    try {
      final query = _ShelterQuery.from(request);
      if (query.validationError case final message?) {
        return _badRequest(message);
      }

      final params = request.url.queryParameters;
      // limit/offset page the *filtered* result, not the upstream fetch.
      //
      // Default raised from 1000 to Env.maxSnapshotItems: at 401 Taipei-only
      // records the old default never bit, but at ~5,850 nationwide records
      // it silently truncated the response to under a fifth of the dataset
      // with no error and no signal — the client had no way to know it
      // didn't have everything. `truncated` makes that visible either way.
      final limit = int.tryParse(params['limit'] ?? '') ?? Env.maxSnapshotItems;
      final offset = int.tryParse(params['offset'] ?? '') ?? 0;
      if (limit < 0 || offset < 0) {
        return _badRequest('limit and offset must not be negative');
      }

      final filtered = _applyFilters(await service.fetchAllShelters(), query);
      final paged = filtered.skip(offset).take(limit);

      return _ok({
        'success': true,
        ..._dataMeta(),
        'data': [for (final e in paged) _toJson(e)],
        'total': filtered.length,
        'truncated': offset + limit < filtered.length,
      });
    } catch (e, s) {
      return _serverError('GET /shelters', e, s);
    }
  }

  /// `GET /api/shelters/clusters?bbox=&zoom=&disasters=&spaces=`
  ///
  /// Grid-clustered markers for a map viewport. The response is centroids
  /// plus counts, not records — a country-wide view transfers a few hundred
  /// bubbles instead of thousands of shelters — so unlike the other
  /// endpoints the bbox cap is generous and omitting bbox means "everything"
  /// rather than "nothing". Single-member clusters embed the full shelter so
  /// the client can open a detail sheet without a follow-up request.
  Future<Response> _getShelterClusters(Request request) async {
    try {
      final query = _ShelterQuery.from(
        request,
        maxBboxDegrees: _ShelterQuery._maxClusterBboxDegrees,
      );
      if (query.validationError case final message?) {
        return _badRequest(message);
      }

      final zoom = double.tryParse(request.url.queryParameters['zoom'] ?? '');
      if (zoom == null || zoom < 6 || zoom > 19) {
        return _badRequest('zoom is required and must be between 6 and 19');
      }

      final filtered = _applyFilters(await service.fetchAllShelters(), query);
      final clusters = service.clusterShelters(data: filtered, zoom: zoom);

      return _ok({
        'success': true,
        ..._dataMeta(),
        'filters': query.toJson(),
        'zoom': zoom,
        'clusters': [
          for (final c in clusters)
            if (c.shelter case final s?)
              {'count': 1, 'lat': c.lat, 'lng': c.lng, 'shelter': _toJson(s)}
            else
              {'count': c.count, 'lat': c.lat, 'lng': c.lng},
        ],
      });
    } catch (e, s) {
      return _serverError('GET /shelters/clusters', e, s);
    }
  }

  Future<Response> _getShelterStats(Request request) async {
    try {
      final query = _ShelterQuery.from(request);
      if (query.validationError case final message?) {
        return _badRequest(message);
      }

      // Off by default — see ShelterService.computeStats's doc comment.
      // ?include=items,shelters opts back in.
      final include = (request.url.queryParameters['include'] ?? '')
          .split(',')
          .map((s) => s.trim())
          .toSet();

      final stats = service.computeStats(
        data: await service.fetchAllShelters(),
        city: query.city,
        township: query.township,
        village: query.village,
        villages: query.villages,
        type: query.type,
        hazards: query.hazards.isEmpty ? null : query.hazards,
        disasters: query.disasters,
        spaces: query.spaces,
        keyword: query.q,
        matchMode: query.matchMode,
        bbox: query.bbox,
        includeItems: include.contains('items'),
        includeShelters: include.contains('shelters'),
      );

      return _ok({
        'success': true,
        ..._dataMeta(),
        'filters': query.toJson(),
        // How much of the dataset can actually be plotted. Surfaced because the
        // upstream dataset has no coordinates at all, so this number is the
        // honest measure of how complete the map is.
        'coordinateCoverage': service.coordinateCoverage.toJson(),
        ...stats,
      });
    } catch (e, s) {
      return _serverError('GET /shelters/stats', e, s);
    }
  }

  /// `GET /api/regions[?city=]` — the 22 counties, or one county's
  /// townships. Small and cheap on purpose: no `shelters`/`items`, meant to
  /// be fetched on every app launch for a county picker / low-zoom overview.
  Future<Response> _getRegions(Request request) async {
    try {
      final params = request.url.queryParameters;
      final city = params['city'] ?? params['縣市'];
      final regions = service.computeRegions(
        data: await service.fetchAllShelters(),
        city: city,
      );
      return _ok({'success': true, ..._dataMeta(), ...regions});
    } catch (e, s) {
      return _serverError('GET /regions', e, s);
    }
  }

  /// `GET /api/shelters/nearby?lat=&lng=&radius=&limit=`
  ///
  /// Sorting by distance server-side means a client no longer has to download
  /// every shelter just to find the closest one — the thing you actually want
  /// on a phone, on mobile data, during a disaster.
  Future<Response> _getNearbyShelters(Request request) async {
    try {
      final params = request.url.queryParameters;
      final lat = double.tryParse(params['lat'] ?? '');
      final lng = double.tryParse(params['lng'] ?? '');
      if (lat == null || lng == null) {
        return _badRequest('lat and lng are required and must be numbers');
      }
      final radius = double.tryParse(params['radius'] ?? '');
      final limit = int.tryParse(params['limit'] ?? '') ?? 10;
      if (limit < 0) return _badRequest('limit must not be negative');

      final query = _ShelterQuery.from(request);
      if (query.validationError case final message?) {
        return _badRequest(message);
      }
      final filtered = _applyFilters(await service.fetchAllShelters(), query);

      final withDistance = <(Shelter, double)>[];
      for (final shelter in filtered) {
        if (!shelter.hasCoordinate) continue;
        final distance = _haversineMeters(lat, lng, shelter.y!, shelter.x!);
        if (radius != null && distance > radius) continue;
        withDistance.add((shelter, distance));
      }
      withDistance.sort((a, b) => a.$2.compareTo(b.$2));

      return _ok({
        'success': true,
        ..._dataMeta(),
        'origin': {'lat': lat, 'lng': lng},
        if (radius != null) 'radius': radius,
        'data': [
          for (final (shelter, distance) in withDistance.take(limit))
            _toJson(shelter, distanceMeters: distance),
        ],
        'total': withDistance.length,
        // Shelters excluded purely because we have no coordinate for them.
        // Reported so a client can tell the user the list is incomplete rather
        // than implying nothing else exists nearby.
        'excludedWithoutCoordinates': filtered
            .where((s) => !s.hasCoordinate)
            .length,
      });
    } catch (e, s) {
      return _serverError('GET /shelters/nearby', e, s);
    }
  }
}

const _earthRadiusMeters = 6371000.0;

double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  double toRadians(double degrees) => degrees * math.pi / 180.0;

  final dLat = toRadians(lat2 - lat1);
  final dLng = toRadians(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(toRadians(lat1)) *
          math.cos(toRadians(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return _earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
