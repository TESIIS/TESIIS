import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import '../../../core/errors/app_exception.dart';
import '../../models/shelter_model.dart';

/// Reads 臺北市可供避難收容處所一覽表 from data.taipei.
///
/// Notes on the upstream API, verified 2026-08-09 against all 401 records:
///   - The datasetId goes in the path, not `?id=`.
///   - `?offset=` works (offset=200 starts at _id 201).
///   - `?q=` does **not** work. `q=南港`, `q=圖書館` and even `q=zzzz` all
///     return the full 401 records, which is why this class does not expose it.
///   - The response carries no coordinate columns whatsoever. Coordinates are
///     joined in by ShelterRepositoryImpl from the committed coordinate table.
class ShelterApi {
  ShelterApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<Map<String, dynamic>>> fetchSheltersRaw({
    int limit = 1000,
    int offset = 0,
  }) async {
    final uri = Uri.parse('${Env.baseUrl}/${Env.shelterDatasetId}').replace(
      queryParameters: {
        'scope': 'resourceAquire',
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final resp = await _client.get(uri);

    if (resp.statusCode != 200) {
      throw ServerException('Failed to load shelters: ${resp.statusCode}');
    }

    // data.taipei serves UTF-8 without always saying so, which would make the
    // http package decode as latin-1 and mangle every Chinese field.
    final jsonMap =
        json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final result = jsonMap['result'] as Map<String, dynamic>?;
    if (result == null) return const [];
    final results = result['results'] as List<dynamic>? ?? const [];
    return results.cast<Map<String, dynamic>>();
  }

  /// Pages through the dataset. [maxItems] is only a runaway guard — the
  /// dataset holds 401 records.
  Future<List<ShelterModel>> fetchAllShelters({
    int pageSize = 1000,
    int maxItems = 3000,
  }) async {
    final result = <ShelterModel>[];
    var offset = 0;
    while (result.length < maxItems) {
      final batch = await fetchSheltersRaw(limit: pageSize, offset: offset);
      if (batch.isEmpty) break;
      result.addAll(batch.map(ShelterModel.fromJson));
      if (batch.length < pageSize) break;
      offset += pageSize;
    }
    return result.length > maxItems ? result.sublist(0, maxItems) : result;
  }
}
