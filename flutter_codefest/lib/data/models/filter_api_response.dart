// 最底層 shelter 資料
class SimpleShelter {
  final String name;
  final String address;
  final String type;
  final String village;
  final List<String> serviceVillages;
  final String? city;
  final String? township;

  SimpleShelter({
    required this.name,
    required this.address,
    required this.type,
    required this.village,
    required this.serviceVillages,
    this.city,
    this.township,
  });

  factory SimpleShelter.fromJson(Map<String, dynamic> json) {
    return SimpleShelter(
      name: json['名稱'],
      address: json['門牌地址'],
      type: json['類型'],
      village: json['村里'],
      serviceVillages: (json['服務里別'] as List<dynamic>).cast<String>(),
      city: json['縣市'],
      township: json['鄉鎮'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '名稱': name,
      '門牌地址': address,
      '類型': type,
      '村里': village,
      '服務里別': serviceVillages,
      '縣市': city,
      '鄉鎮': township,
    };
  }
}

// township 下的 village
class VillageRegion {
  final String village;
  final int count;
  final List<SimpleShelter> shelters;

  VillageRegion({
    required this.village,
    required this.count,
    required this.shelters,
  });

  factory VillageRegion.fromJson(Map<String, dynamic> json) {
    return VillageRegion(
      village: json['village'],
      count: json['count'],
      shelters: (json['shelters'] as List<dynamic>)
          .map((e) => SimpleShelter.fromJson(e))
          .toList(),
    );
  }
}

// township 層級
class TownshipRegion {
  final String township;
  final int total;
  final List<VillageRegion> villages;
  final List<SimpleShelter> shelters;

  TownshipRegion({
    required this.township,
    required this.total,
    required this.villages,
    required this.shelters,
  });

  factory TownshipRegion.fromJson(Map<String, dynamic> json) {
    return TownshipRegion(
      township: json['township'],
      total: json['total'],
      villages: (json['villages'] as List<dynamic>)
          .map((e) => VillageRegion.fromJson(e))
          .toList(),
      shelters: (json['shelters'] as List<dynamic>)
          .map((e) => SimpleShelter.fromJson(e))
          .toList(),
    );
  }
}

// city 層級
class CityRegion {
  final String city;
  final int total;
  final List<TownshipRegion> townships;

  CityRegion({
    required this.city,
    required this.total,
    required this.townships,
  });

  factory CityRegion.fromJson(Map<String, dynamic> json) {
    return CityRegion(
      city: json['city'],
      total: json['total'],
      townships: (json['townships'] as List<dynamic>)
          .map((e) => TownshipRegion.fromJson(e))
          .toList(),
    );
  }
}

// byType 統計
class ShelterTypeCount {
  final String type;
  final int count;

  ShelterTypeCount({required this.type, required this.count});

  factory ShelterTypeCount.fromJson(Map<String, dynamic> json) {
    return ShelterTypeCount(type: json['type'], count: json['count']);
  }
}

// filters
class ShelterFilters {
  final String city;
  final String township;
  final String match;
  final Map<String, String> hazards;

  ShelterFilters({
    required this.city,
    required this.township,
    required this.match,
    required this.hazards,
  });

  factory ShelterFilters.fromJson(Map<String, dynamic> json) {
    return ShelterFilters(
      city: json['city'],
      township: json['township'],
      match: json['match'],
      hazards: (json['hazards'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v as String),
      ),
    );
  }
}

// 完整 API Response
class ShelterApiResponse {
  final bool success;
  final ShelterFilters filters;
  final int total;
  final List<ShelterTypeCount> byType;
  final List<CityRegion> byRegion;
  final List<SimpleShelter> items;

  ShelterApiResponse({
    required this.success,
    required this.filters,
    required this.total,
    required this.byType,
    required this.byRegion,
    required this.items,
  });

  factory ShelterApiResponse.fromJson(Map<String, dynamic> json) {
    return ShelterApiResponse(
      success: json['success'],
      filters: ShelterFilters.fromJson(json['filters']),
      total: json['total'],
      byType: (json['byType'] as List<dynamic>)
          .map((e) => ShelterTypeCount.fromJson(e))
          .toList(),
      byRegion: (json['byRegion'] as List<dynamic>)
          .map((e) => CityRegion.fromJson(e))
          .toList(),
      items: (json['items'] as List<dynamic>)
          .map((e) => SimpleShelter.fromJson(e))
          .toList(),
    );
  }
}
