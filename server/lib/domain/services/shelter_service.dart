// lib/domain/services/shelter_service.dart

import '../entities/shelter.dart';
import '../repositories/shelter_repository.dart';

class ShelterService {
  final ShelterRepository repository;

  ShelterService({required this.repository});

  List<String> _normalizeKeywords(String? raw) {
    if (raw == null) return const [];
    final tokens = raw
        .split(RegExp(r'[\s,、，]+'))
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    return tokens;
  }

  bool _matchesKeywords(Shelter shelter, List<String> keywords) {
    if (keywords.isEmpty) return true;
    final buffer = StringBuffer();

    void push(String? value) {
      if (value == null) return;
      final trimmed = value.trim();
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
    return keywords.every((kw) => haystack.contains(kw));
  }

  Future<List<Shelter>> fetchAllShelters({String? q, int limit = 1000, int offset = 0}) {
    return repository.getShelters(q: q, limit: limit, offset: offset);
  }

  Future<List<Shelter>> fetchAllSheltersPaged({String? q, int maxItems = 2000}) {
    return repository.getAllShelters(q: q, maxItems: maxItems);
  }

  // 本地過濾：區域 / 類型 / 災害條件（AND/OR）
  List<Shelter> filterShelters({
    required List<Shelter> data,
    String? city,
    String? township,
    String? village, // 單一村里（向後相容）
    List<String>? villages, // 可傳多個村里（query: villages=村A,村B 或 多個 villages 參數）
    String? type,
    String? keyword,
    Map<String, String>? hazards, // 以中文鍵名：水災/震災/土石流/海嘯/救濟支站/無障礙設施/室內/室外
    String matchMode = 'and', // 'and' | 'or'，僅應用在 hazards 上
  }) {
    final hz = hazards ?? const <String, String>{};
    final mm = (matchMode.toLowerCase() == 'or') ? 'or' : 'and';
    final keywords = _normalizeKeywords(keyword);

    bool _eq(String? a, String? b) => (a ?? '').trim() == (b ?? '').trim();

    bool _isTruthy(String? v) {
      final s = (v ?? '').trim();
      final upper = s.toUpperCase();
      if (s.contains('備用')) return true;
      return upper == 'Y' || upper == 'YES' || upper == 'TRUE';
    }

    bool _isFalsy(String? v) {
      final s = (v ?? '').trim().toUpperCase();
      return s == 'N' || s == 'NO' || s == 'FALSE';
    }

    String? _getHazardValue(Shelter s, String zhKey) {
      switch (zhKey) {
        case '水災':
          return s.flood;
        case '震災':
          return s.quake;
        case '土石流':
          return s.landslide;
        case '海嘯':
          return s.tsunami;
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

    List<String> _splitServiceVillages(String? s) {
      if (s == null) return const [];
      return s
          .split(RegExp(r'[、,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }

    List<String>? _normalizeVillagesInput(String? single, List<String>? multi) {
      final out = <String>[];
      if (single != null && single.trim().isNotEmpty) out.add(single.trim());
      if (multi != null) {
        out.addAll(multi.map((e) => e.trim()).where((e) => e.isNotEmpty));
      }
      return out.isEmpty ? null : out;
    }

    bool _hazardsSatisfied(Shelter s) {
      if (hz.isEmpty) return true;
      final results = <bool>[];

      for (final entry in hz.entries) {
        final key = entry.key; // 中文鍵名
        final rawWant = (entry.value).trim();
        final want = rawWant.toUpperCase(); // 支援 Y / N / 備用 / 是 / 否
        final val = _getHazardValue(s, key);

        bool ok;
        final truthySet = {'Y','YES','TRUE','是'};
        final falsySet = {'N','NO','FALSE','否'};
        if (truthySet.contains(want)) {
          ok = _isTruthy(val); // 'Y' 群組：Y/是/yes/true/含備用
        } else if (falsySet.contains(want)) {
          ok = _isFalsy(val);
        } else if (rawWant.contains('備用')) {
          ok = (val ?? '').contains('備用'); // 僅限「備用」
        } else {
          // 未知要求值，跳過此條件
          ok = true;
        }
        results.add(ok);
      }

      return mm == 'or' ? results.any((b) => b) : results.every((b) => b);
    }

    bool _keywordsSatisfied(Shelter s) => _matchesKeywords(s, keywords);

    return data.where((s) {
      if (city != null && city.isNotEmpty && !_eq(s.city, city)) return false;
      if (township != null && township.isNotEmpty && !_eq(s.township, township)) return false;

      final villagesList = _normalizeVillagesInput(village, villages);
      if (villagesList != null) {
        final inVillage = villagesList.any((v) => _eq(s.village, v));
        final serviceHit = _splitServiceVillages(s.serviceVillages).any((sv) => villagesList.any((v) => _eq(sv, v)));
        if (!inVillage && !serviceHit) return false;
      }

      if (type != null && type.isNotEmpty && !_eq(s.type, type)) return false;

      if (!_hazardsSatisfied(s)) return false;

      if (!_keywordsSatisfied(s)) return false;

      return true;
    }).toList(growable: false);
  }

  // 統計與過濾
  Map<String, dynamic> computeStats({
    required List<Shelter> data,
    String? city,
    String? township,
    String? village,
    List<String>? villages,
    String? type,
    Map<String, String>? hazards,
    String? keyword,
    String matchMode = 'and', // 'and' | 'or'
  }) {
    bool normalizeYes(String? v) => v == null
        ? false
        : ['Y', 'y', '是', 'yes', '備用'].contains(v.toString().trim());

    final keywords = _normalizeKeywords(keyword);

    bool checkHazards(Shelter s) {
      if (hazards == null || hazards.isEmpty) return true;
      final checks = <bool>[];
      bool h(String key, String? v) {
        final desired = hazards[key];
        if (desired == null) return true;
        final rawWant = desired.trim();
        final wantUpper = rawWant.toUpperCase();
        final truthySet = {'Y','YES','TRUE','是'};
        final falsySet = {'N','NO','FALSE','否'};
        if (truthySet.contains(wantUpper)) {
          // Y 群組：Y/是/yes/true/含備用
          return normalizeYes(v);
        } else if (falsySet.contains(wantUpper)) {
          return !normalizeYes(v);
        } else if (rawWant.contains('備用')) {
          return (v ?? '').toString().contains('備用'); // 僅限「備用」
        } else {
          // 未知值，忽略此條件
          return true;
        }
      }
      checks.add(h('水災', s.flood));
      checks.add(h('震災', s.quake));
      checks.add(h('土石流', s.landslide));
      checks.add(h('海嘯', s.tsunami));
      checks.add(h('救濟支站', s.relief));
      checks.add(h('無障礙設施', s.accessible));
      checks.add(h('室內', s.indoor));
      checks.add(h('室外', s.outdoor));
      return matchMode == 'or' ? checks.any((e) => e) : checks.every((e) => e);
    }

  bool _eq(String? a, String? b) => (a ?? '').trim() == (b ?? '').trim();

  bool regionOk(Shelter s) {
      if (city != null && city.isNotEmpty && s.city != city) return false;
      if (township != null && township.isNotEmpty && s.township != township) return false;

      List<String>? villagesList;
      if (villages != null && villages.isNotEmpty) {
        villagesList = villages.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      } else if (village != null && village.isNotEmpty) {
        villagesList = [village.trim()];
      }

      if (villagesList != null && villagesList.isNotEmpty) {
        final inVillage = villagesList.any((v) => _eq(s.village, v));
        final services = (s.serviceVillages ?? '')
            .split(RegExp(r'[、，,]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final serviceHit = services.any((sv) => villagesList!.any((v) => _eq(sv, v)));
        if (!inVillage && !serviceHit) return false;
      }

      return true;
    }

    bool typeOk(Shelter s) => type == null || type.isEmpty || s.type == type;
    bool keywordOk(Shelter s) => _matchesKeywords(s, keywords);

    final filtered = data.where((s) => regionOk(s) && typeOk(s) && checkHazards(s) && keywordOk(s)).toList();

    // 統計 byType
    final typeCounts = <String, int>{};
    for (final s in filtered) {
      typeCounts[s.type] = (typeCounts[s.type] ?? 0) + 1;
    }

    // 統計 byRegion (city -> township -> village)，村里含服務里別
    final byRegion = <String, Map<String, dynamic>>{};
    for (final s in filtered) {
      byRegion.putIfAbsent(s.city, () => {'total': 0, 'townships': <String, Map<String, dynamic>>{}});
      final c = byRegion[s.city]!;
      c['total'] = (c['total'] as int) + 1;
      final townships = c['townships'] as Map<String, Map<String, dynamic>>;
      townships.putIfAbsent(s.township, () => {'total': 0, 'villages': <String, int>{}});
      final t = townships[s.township]!;
      t['total'] = (t['total'] as int) + 1;

      // 實際村里
      final villages = t['villages'] as Map<String, int>;
      villages[s.village] = (villages[s.village] ?? 0) + 1;
      // 服務里別擴散計數
      final services = (s.serviceVillages ?? '')
          .split(RegExp(r'[、，,]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      for (final v in services) {
        villages[v] = (villages[v] ?? 0) + 1;
      }
    }

    // 格式化輸出 (含每個縣市 -> 鄉鎮 -> shelter 清單與服務里別陣列)
    List<Map<String, dynamic>> formatRegion(List<Shelter> filtered) {
      // 依 city / township 分組
      final out = <Map<String, dynamic>>[];
      final grouped = <String, Map<String, Map<String, List<Shelter>>>>{}; // city -> township -> key('__list__')-> shelters
      for (final s in filtered) {
        grouped.putIfAbsent(s.city, () => <String, Map<String, List<Shelter>>>{});
        grouped[s.city]!.putIfAbsent(s.township, () => <String, List<Shelter>>{});
        grouped[s.city]![s.township]!.putIfAbsent('__list__', () => <Shelter>[]);
        grouped[s.city]![s.township]!['__list__']!.add(s);
      }

      for (final cityEntry in byRegion.entries) {
        final cityName = cityEntry.key;
        final cityData = cityEntry.value;
        final townsMap = cityData['townships'] as Map<String, Map<String, dynamic>>;
        final townsOut = <Map<String, dynamic>>[];
        for (final t in townsMap.entries) {
          // 取得該鄉鎮所有避難點
          final townshipShelters = (grouped[cityName]?[t.key]?['__list__'] ?? <Shelter>[]);

            // 建立村里 -> shelters 對應（包含服務里別展開）
          final villageShelterMap = <String, Set<int>>{}; // villageName -> set of shelter ids
          final villageShelterObjects = <String, List<Shelter>>{};
          for (final s in townshipShelters) {
            void addVillage(String vName, Shelter sh) {
              villageShelterMap.putIfAbsent(vName, () => <int>{});
              villageShelterObjects.putIfAbsent(vName, () => <Shelter>[]);
              if (villageShelterMap[vName]!.add(sh.id)) {
                villageShelterObjects[vName]!.add(sh);
              }
            }
            // 原始村里
            if (s.village.isNotEmpty) {
              addVillage(s.village, s);
            }
            // 服務里別展開
            final services = (s.serviceVillages ?? '')
                .split(RegExp(r'[、，,]'))
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            for (final sv in services) {
              addVillage(sv, s);
            }
          }

          // 以 unique shelter 數量為準，避免同一 shelter 因「原始村里 + 服務里別」重複計數
          final villagesDetailed = villageShelterMap.entries
              .map((e) => MapEntry(e.key, e.value.length))
              .toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          final villagesDetailedJson = villagesDetailed.map((entry) {
            final vName = entry.key;
            final vShelters = villageShelterObjects[vName] ?? <Shelter>[];
            final vShelterJson = vShelters
                .map((s) => {
                      '名稱': s.name,
                      '門牌地址': s.address,
                      '類型': s.type,
                      '村里': s.village,
                      '服務里別': (s.serviceVillages ?? '')
                          .split(RegExp(r'[、，,]'))
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .toList(),
                    })
                .toList();
            return {
              'village': vName,
              'count': entry.value,
              'shelters': vShelterJson,
            };
          }).toList();

          final shelterList = townshipShelters
              .map((s) => {
                    '名稱': s.name,
                    '門牌地址': s.address,
                    '類型': s.type,
                    '村里': s.village,
                    '服務里別': (s.serviceVillages ?? '')
                        .split(RegExp(r'[、，,]'))
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList(),
                  })
              .toList();

          townsOut.add({
            'township': t.key,
            'total': t.value['total'],
            'villages': villagesDetailedJson,
            'shelters': shelterList,
          });
        }
        townsOut.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
        out.add({'city': cityName, 'total': cityData['total'], 'townships': townsOut});
      }
      out.sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
      return out;
    }

    final byTypeList = typeCounts.entries
        .map((e) => {'type': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    // 供前端列出名稱與地址
    final items = filtered
        .map((s) => {
              '名稱': s.name,
              '門牌地址': s.address,
              '縣市': s.city,
              '鄉鎮': s.township,
        '村里': s.village,
        '服務里別': (s.serviceVillages ?? '')
          .split(RegExp(r'[、，,]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
              '類型': s.type,
              '震災': (s.quake == '備用') ? 'Y' : s.quake,
              '海嘯': (s.tsunami == '備用') ? 'Y' : s.tsunami,
            })
        .toList();

    return {
      'total': filtered.length,
      'byType': byTypeList,
      'byRegion': formatRegion(filtered),
      'items': items,
    };
  }
}
