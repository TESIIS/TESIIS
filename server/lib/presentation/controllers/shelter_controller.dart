// lib/presentation/controllers/shelter_controller.dart
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:logging/logging.dart';
import '../../domain/services/shelter_service.dart';
import '../../domain/entities/shelter.dart';

class ShelterController {
  final ShelterService service;
  final Logger _logger = Logger('ShelterController');

  ShelterController({required this.service});

  Router get router {
    final r = Router();
    r.get('/shelters', _getShelters);
    r.get('/shelters/stats', _getShelterStats);
    return r;
  }

  Future<Response> _getShelters(Request request) async {
    _logger.info('Handling GET /shelters request with params: ${request.url.queryParameters}');
    try {
      final params = request.url.queryParameters;
      // 分頁輸出參數（作用於過濾後的結果）
      final limit = int.tryParse(params['limit'] ?? '') ?? 1000;
      final offset = int.tryParse(params['offset'] ?? '') ?? 0;

      // 遠端 q（用於縮小抓取範圍，但真正過濾在本地完成）
      final q = params['q'];

      // 支援中英文過濾鍵
      final city = params['city'] ?? params['縣市'];
      final township = params['township'] ?? params['鄉鎮'];
      final village = params['village'] ?? params['村里'];
      // 支援多個 villages 參數或以分隔字元傳入的多值
      List<String>? villagesList;
      final villagesAll = request.url.queryParametersAll['villages'] ?? <String>[];
      if (villagesAll.isNotEmpty) {
        final tmp = <String>[];
        for (final val in villagesAll) {
          tmp.addAll(val.split(RegExp(r'[、，,]')).map((e) => e.trim()).where((e) => e.isNotEmpty));
        }
        if (tmp.isNotEmpty) villagesList = tmp;
      } else if ((params['villages'] ?? '').isNotEmpty) {
        villagesList = (params['villages'] ?? '')
            .split(RegExp(r'[、，,]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }
      final type = params['type'] ?? params['類型'];
      final matchMode = (params['match'] ?? 'and').toLowerCase() == 'or' ? 'or' : 'and';

      // hazards 支援中英文 key
      final hazards = <String, String>{};
      void take(String en, String zh) {
        final v = params[en] ?? params[zh];
        if (v != null && v.isNotEmpty) hazards[zh] = v;
      }
      take('flood', '水災');
      take('quake', '震災');
      take('landslide', '土石流');
      take('tsunami', '海嘯');
      take('relief', '救濟支站');
      take('accessible', '無障礙設施');
      take('indoor', '室內');
      take('outdoor', '室外');

      // 先抓齊資料（分頁到上限），再本地過濾，最後才做分頁輸出
      final List<Shelter> all = await service.fetchAllSheltersPaged(q: q, maxItems: 3000);
      final List<Shelter> filtered = service.filterShelters(
        data: all,
        city: city,
        township: township,
        village: village,
        villages: villagesList,
        type: type,
        keyword: q,
        hazards: hazards.isEmpty ? null : hazards,
        matchMode: matchMode,
      );

      final paged = filtered.skip(offset).take(limit).toList(growable: false);

      final result = paged.map((e) => {
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
            '水災': e.flood,
            '震災': (e.quake == '備用') ? 'Y' : e.quake,
            '土石流': (e.landslide == '老舊聚落') ? 'Y' : e.landslide,
            '海嘯': (e.tsunami == '備用') ? 'Y' : e.tsunami,
            '救濟支站': e.relief,
            '無障礙設施': e.accessible,
            '室內': e.indoor,
            '室外': e.outdoor,
      '服務里別': (e.serviceVillages ?? '')
        .split(RegExp(r'[、，,]'))
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList(),
            '容納人數': e.capacity,
            '收容所面積(平方公尺)': e.area,
            '聯絡人姓名': e.contactName,
            '聯絡人連絡電話': e.contactPhone,
            '管理人姓名': e.managerName,
            '管理人連絡電話': e.managerPhone,
            '備考': e.notes,
            '座標x': e.x,
            '座標y': e.y,
          }).toList();

      final body = jsonEncode({'success': true, 'data': result, 'total': filtered.length});
      _logger.info('GET /shelters returned ${result.length} items (total filtered: ${filtered.length})');
      return Response.ok(body, headers: {'content-type': 'application/json'});
    } catch (e) {
      _logger.severe('Error in GET /shelters: $e');
      final body = jsonEncode({'success': false, 'message': e.toString()});
      return Response.internalServerError(body: body, headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> _getShelterStats(Request request) async {
    _logger.info('Handling GET /shelters/stats request with params: ${request.url.queryParameters}');
    try {
      final params = request.url.queryParameters;
      final q = params['q'];
      final city = params['city'] ?? params['縣市'];
      final township = params['township'] ?? params['鄉鎮'];
      final village = params['village'] ?? params['村里'];
      final type = params['type'] ?? params['類型'];
      final matchMode = (params['match'] ?? 'and').toLowerCase() == 'or' ? 'or' : 'and';

      // hazards 支援中英文 key
      final hazards = <String, String>{};
      void take(String en, String zh) {
        final v = params[en] ?? params[zh];
        if (v != null && v.isNotEmpty) hazards[zh] = v;
      }
      take('flood', '水災');
      take('quake', '震災');
      take('landslide', '土石流');
      take('tsunami', '海嘯');
      take('relief', '救濟支站');
      take('accessible', '無障礙設施');
      take('indoor', '室內');
      take('outdoor', '室外');

      // 取得資料（分頁抓取，最多 2000 筆）
      final list = await service.fetchAllSheltersPaged(q: q, maxItems: 2000);

      // parse villages param for stats as well
      List<String>? villagesListStats;
      final villagesAllStats = request.url.queryParametersAll['villages'] ?? <String>[];
      if (villagesAllStats.isNotEmpty) {
        final tmp = <String>[];
        for (final val in villagesAllStats) {
          tmp.addAll(val.split(RegExp(r'[、，,]')).map((e) => e.trim()).where((e) => e.isNotEmpty));
        }
        if (tmp.isNotEmpty) villagesListStats = tmp;
      } else if ((params['villages'] ?? '').isNotEmpty) {
        villagesListStats = (params['villages'] ?? '')
            .split(RegExp(r'[、，,]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }

      final stats = service.computeStats(
        data: list,
        city: city,
        township: township,
        village: village,
        villages: villagesListStats,
        type: type,
        hazards: hazards.isEmpty ? null : hazards,
        keyword: q,
        matchMode: matchMode,
      );

      final body = jsonEncode({
        'success': true,
        'filters': {
          if (q != null) 'q': q,
          if (city != null) 'city': city,
          if (township != null) 'township': township,
          if (village != null) 'village': village,
          if (type != null) 'type': type,
          if (hazards.isNotEmpty) 'hazards': hazards,
          'match': matchMode,
        },
        ...stats,
      });
      _logger.info('GET /shelters/stats returned stats for ${stats['total']} items');
      return Response.ok(body, headers: {'content-type': 'application/json'});
    } catch (e) {
      _logger.severe('Error in GET /shelters/stats: $e');
      final body = jsonEncode({'success': false, 'message': e.toString()});
      return Response.internalServerError(body: body, headers: {'content-type': 'application/json'});
    }
  }
}
