import 'package:shelf/shelf.dart';
import '../../core/errors/app_exception.dart';

/// Data Transfer Object representing query parameters for listing shelters.
/// Provides normalized access to filters and pagination.
class ListSheltersQueryDTO {
  final String? q;
  final String? city;
  final String? township;
  final String? village;
  final List<String>? villages; // multiple villages filter
  final String? type;
  final Map<String, String>? hazards; // Chinese key -> Y/N
  final String matchMode; // 'and' or 'or'
  final int limit; // pagination limit (applied after filtering)
  final int offset; // pagination offset (applied after filtering)

  const ListSheltersQueryDTO({
    this.q,
    this.city,
    this.township,
    this.village,
    this.villages,
    this.type,
    this.hazards,
    required this.matchMode,
    required this.limit,
    required this.offset,
  });

  /// Factory to parse from Shelf [Request]. Performs validation and normalization.
  /// @throws [BadRequestException] 當參數格式不正確時
  factory ListSheltersQueryDTO.fromRequest(Request request) {
    final params = request.url.queryParameters;
    String? _takeMultiLang(String en, String zh) => params[en] ?? params[zh];

    // pagination
    final rawLimit = params['limit'];
    final rawOffset = params['offset'];
    int limit;
    int offset;
    try {
      limit = int.tryParse(rawLimit ?? '') ?? 1000;
      offset = int.tryParse(rawOffset ?? '') ?? 0;
      if (limit <= 0) {
        throw BadRequestException('limit 必須大於 0', code: 'INVALID_LIMIT');
      }
      if (limit > 3000) {
        throw BadRequestException('limit 不可超過 3000', code: 'LIMIT_TOO_LARGE');
      }
      if (offset < 0) {
        throw BadRequestException('offset 不可為負數', code: 'INVALID_OFFSET');
      }
    } on FormatException {
      throw BadRequestException('分頁參數格式錯誤', code: 'INVALID_PAGINATION');
    }

    // villages multi-value logic
    List<String>? villagesList;
    final villagesAll = request.url.queryParametersAll['villages'] ?? <String>[];
    if (villagesAll.isNotEmpty) {
      final tmp = <String>[];
      for (final val in villagesAll) {
        tmp.addAll(val
            .split(RegExp(r'[、，,]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty));
      }
      if (tmp.isNotEmpty) villagesList = tmp;
    } else if ((params['villages'] ?? '').isNotEmpty) {
      villagesList = (params['villages']!)
          .split(RegExp(r'[、，,]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }

    // hazards (Chinese key retained for internal service compatibility)
    final hazards = <String, String>{};
    void take(String en, String zh) {
      final v = _takeMultiLang(en, zh);
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

    final match = (params['match'] ?? 'and').toLowerCase() == 'or' ? 'or' : 'and';

    return ListSheltersQueryDTO(
      q: params['q'],
      city: _takeMultiLang('city', '縣市'),
      township: _takeMultiLang('township', '鄉鎮'),
      village: _takeMultiLang('village', '村里'),
      villages: villagesList,
      type: _takeMultiLang('type', '類型'),
      hazards: hazards.isEmpty ? null : hazards,
      matchMode: match,
      limit: limit,
      offset: offset,
    );
  }

  Map<String, dynamic> toFilterMap() {
    return {
      if (q != null) 'q': q,
      if (city != null) 'city': city,
      if (township != null) 'township': township,
      if (village != null) 'village': village,
      if (type != null) 'type': type,
      if (hazards != null) 'hazards': hazards,
      'match': matchMode,
      'limit': limit,
      'offset': offset,
      if (villages != null) 'villages': villages,
    };
  }
}
