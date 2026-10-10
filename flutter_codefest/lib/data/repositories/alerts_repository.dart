import 'package:flutter_codefest/core/platform/preparedness_platform.dart'
    as platform;
import 'package:flutter_codefest/data/datasources/api.dart';
import 'package:flutter_codefest/data/datasources/request_cache.dart';
import 'package:flutter_codefest/data/models/disaster_alert.dart';

class AlertsRepository {
  AlertsRepository({
    Future<dynamic> Function(String, {Map<String, String>? queryParams})? get,
    Future<CachedResponse?> Function(String)? cacheGet,
    Future<void> Function(String, Map<String, dynamic>)? cachePut,
    bool Function()? online,
  }) : _get = get ?? ApiService.get,
       _cacheGet = cacheGet ?? RequestCache.get,
       _cachePut = cachePut ?? RequestCache.put,
       _online = online ?? (() => platform.networkAvailable);
  final Future<dynamic> Function(String, {Map<String, String>? queryParams})
  _get;
  final Future<CachedResponse?> Function(String) _cacheGet;
  final Future<void> Function(String, Map<String, dynamic>) _cachePut;
  final bool Function() _online;

  Future<AlertFeed> fetch({
    AlertRegion? region,
    bool history = false,
    bool offline = false,
  }) async {
    final params = {
      'history': '$history',
      if (region != null) 'city': region.city,
      if (region?.township != null) 'township': region!.township!,
    };
    final key = RequestCache.keyFor('/alerts', params);
    if (!offline && _online()) {
      try {
        final body =
            await _get('/alerts', queryParams: params) as Map<String, dynamic>;
        if (body['available'] != true) throw StateError('Alerts unavailable');
        final feed = AlertFeed.fromJson(body);
        // Storage errors must not discard a successfully downloaded bulletin.
        try {
          await _cachePut(key, body);
        } catch (_) {}
        return feed;
      } on ApiException catch (e) {
        if (e.statusCode < 500) rethrow;
      } catch (_) {}
    }
    final cached = await _cacheGet(key);
    if (cached == null) throw StateError('目前無法取得警報資料，這個查詢也沒有裝置快取');
    return AlertFeed.fromJson(cached.body, deviceCache: true);
  }
}
