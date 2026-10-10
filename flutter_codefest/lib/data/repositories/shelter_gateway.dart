import 'package:flutter_codefest/core/platform/preparedness_platform.dart'
    as platform;
import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_codefest/data/datasources/api.dart';
import 'package:flutter_codefest/data/models/cluster_page.dart';
import 'package:flutter_codefest/data/models/preparedness.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/data/models/shelter_page.dart';
import 'package:flutter_codefest/data/repositories/preparedness_store.dart';
import 'package:flutter_codefest/domain/marker_clustering.dart';
import 'package:flutter_codefest/domain/offline_query.dart';

typedef GetShelterJson =
    Future<dynamic> Function(String path, {Map<String, String>? queryParams});

/// Online API and offline packages expose the same query semantics. A package
/// miss is an explicitly scoped empty result, never a claim of national absence.
class ShelterGateway {
  ShelterGateway(this.store, {GetShelterJson? get, bool Function()? online})
    : _get = get ?? ApiService.get,
      _online = online ?? (() => platform.networkAvailable);
  final PreparednessStore store;
  final GetShelterJson _get;
  final bool Function() _online;
  bool usedOffline = false;
  bool get localOnly => store.offlineMode || !_online();

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, String> params,
  ) async {
    if (!localOnly) {
      try {
        final response =
            await _get(path, queryParams: params) as Map<String, dynamic>;
        usedOffline = false;
        return response;
      } on ApiException catch (e) {
        if (e.statusCode < 500) rethrow;
      } catch (_) {
        // Network failure: try a complete downloaded region.
      }
    }
    if (store.packages.isEmpty) throw StateError('尚未下載離線資料，請連線後下載生活圈資料包');
    usedOffline = true;
    final rows = queryOffline(store.offlineShelters, params);
    if (path.endsWith('/clusters')) {
      return {
        'dataFreshness': 'offline',
        'clusters': clusterShelters(
          rows.where((s) => s.hasCoordinate).toList(),
          zoom: double.parse(params['zoom']!),
        ).map((c) => c.toJson()).toList(),
      };
    }
    final offset = int.tryParse(params['offset'] ?? '') ?? 0;
    final limit = int.tryParse(params['limit'] ?? '') ?? 50;
    final lat = double.tryParse(params['lat'] ?? '');
    final lng = double.tryParse(params['lng'] ?? '');
    return {
      'dataFreshness': 'offline',
      'total': rows.length,
      'truncated': offset + limit < rows.length,
      'data': [
        for (final s in rows.skip(offset).take(limit))
          {
            ...s.toJson(),
            if (lat != null && lng != null)
              '距離公尺': distanceToShelter(s, lat, lng).round(),
          },
      ],
    };
  }

  Future<ClusterPage> clusters(Map<String, String> params) async =>
      ClusterPage.fromJson(await _request('/shelters/clusters', params));
  Future<ShelterPage> page(Map<String, String> params) async =>
      ShelterPage.fromJson(await _request('/shelters', params));
  Future<List<Shelter>> nearby({
    required double lat,
    required double lng,
    double? radiusMeters,
    int limit = 10,
    Set<String>? disasters,
    Set<String>? spaces,
    Map<String, String>? scope,
  }) async => ShelterPage.fromJson(
    await _request('/shelters/nearby', {
      ...?scope,
      'lat': '$lat',
      'lng': '$lng',
      'limit': '$limit',
      if (radiusMeters != null) 'radius': '$radiusMeters',
      if (disasters != null && disasters.isNotEmpty)
        'disasters': disasters.join(','),
      if (spaces != null && spaces.isNotEmpty) 'spaces': spaces.join(','),
    }),
  ).shelters;

  Future<Shelter> detail(String code) async {
    if (!localOnly) {
      try {
        final body =
            await _get('/shelters/${Uri.encodeComponent(code)}')
                as Map<String, dynamic>;
        usedOffline = false;
        return Shelter.fromJson(body['data'] as Map<String, dynamic>);
      } on ApiException catch (e) {
        if (e.statusCode < 500) rethrow;
      } catch (_) {}
    }
    final saved = store.savedShelter(code);
    if (saved == null) throw StateError('這個避難所尚未保存到裝置');
    usedOffline = true;
    return saved;
  }

  Future<OfflinePackage> download(String city, String? township) async {
    final body =
        await _get(
              '/shelters/package',
              queryParams: {
                'city': city,
                if (township != null && township.isNotEmpty)
                  'township': township,
              },
            )
            as Map<String, dynamic>;
    return OfflinePackage.fromJson(body, downloadedAt: DateTime.now());
  }

  Future<List<String>> regions({String? city}) async {
    if (!localOnly) {
      try {
        final body =
            await _get(
                  '/regions',
                  queryParams: {if (city != null) 'city': city},
                )
                as Map<String, dynamic>;
        final key = city == null ? 'regions' : 'townships';
        final name = city == null ? 'city' : 'township';
        return (body[key] as List)
            .map((e) => e[name] as String)
            .where((e) => e.isNotEmpty)
            .toList();
      } catch (_) {}
    }
    return (city == null
            ? store.packages.map((p) => p.city)
            : store.offlineShelters
                  .where(
                    (s) => normalizeSearch(s.city) == normalizeSearch(city),
                  )
                  .map((s) => s.district))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }
}
