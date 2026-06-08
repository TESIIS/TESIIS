import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:server/core/config/env.dart';
import '../../models/shelter_model.dart';
import '../../../core/errors/app_exception.dart';

class ShelterApi {
  /// 擷取 Taipei OpenData 的 result.results 陣列
  /// 注意：新的端點需要將 datasetId 放在 path，而非用 `?id=` 查詢
  Future<List<Map<String, dynamic>>> fetchSheltersRaw({String? q, int limit = 1000, int offset = 0}) async {
    final query = <String, String>{
      'scope': 'resourceAquire',
      'limit': '$limit',
      'offset': '$offset',
      if (q != null && q.isNotEmpty) 'q': q,
    };
    final uri = Uri.parse('${Env.baseUrl}/${Env.shelterDatasetId}').replace(queryParameters: query);
    final resp = await http.get(uri);

    if (resp.statusCode != 200) {
      throw ServerException('Failed to load shelters: ${resp.statusCode}');
    }

  final Map<String, dynamic> jsonMap = json.decode(resp.body) as Map<String, dynamic>;
    final result = jsonMap['result'] as Map<String, dynamic>?;
    if (result == null) return <Map<String, dynamic>>[];
    final List<dynamic> results = result['results'] as List<dynamic>? ?? <dynamic>[];
    return results.cast<Map<String, dynamic>>();
  }

  /// 轉換成資料模型（僅取用我們需要的欄位）
  Future<List<ShelterModel>> fetchShelters({String? q, int limit = 1000, int offset = 0}) async {
    final raw = await fetchSheltersRaw(q: q, limit: limit, offset: offset);
    return raw.map((item) => ShelterModel.fromJson(item)).toList();
  }

  /// 以分頁方式抓取所有資料（上限 maxItems 以避免無限抓取）
  Future<List<ShelterModel>> fetchAllShelters({String? q, int pageSize = 1000, int maxItems = 2000}) async {
    final result = <ShelterModel>[];
    var offset = 0;
    while (result.length < maxItems) {
      final batch = await fetchShelters(q: q, limit: pageSize, offset: offset);
      if (batch.isEmpty) break;
      result.addAll(batch);
      if (batch.length < pageSize) break;
      offset += pageSize;
    }
    if (result.length > maxItems) {
      return result.sublist(0, maxItems);
    }
    return result;
  }
}
