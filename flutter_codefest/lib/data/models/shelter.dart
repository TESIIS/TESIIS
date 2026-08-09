/// One 避難收容處所, as served by `GET /api/shelters`.
///
/// The JSON keys are Chinese because the server passes the Taipei OpenData
/// column names straight through. Hazard fields are compared against the
/// literal 'Y': the server normalises the upstream aliases (備用, 老舊聚落) to
/// 'Y' before sending, so this side must not try to interpret them again.
class Shelter {
  const Shelter({
    required this.id,
    required this.importDate,
    required this.shelterId,
    required this.name,
    required this.city,
    required this.postalCode,
    required this.district,
    required this.village,
    required this.address,
    required this.type,
    required this.flood,
    required this.earthquake,
    required this.landslide,
    required this.tsunami,
    required this.reliefStation,
    required this.accessible,
    required this.indoor,
    required this.outdoor,
    required this.serviceVillages,
    required this.capacity,
    required this.area,
    required this.contactName,
    required this.contactPhone,
    required this.managerName,
    required this.managerPhone,
    required this.remarks,
    required this.latitude,
    required this.longitude,
    this.coordinateSource,
    this.coordinateConfidence,
    this.distanceMeters,
  });

  final int id;
  final DateTime? importDate;
  final String shelterId;
  final String name;
  final String city;
  final String postalCode;
  final String district;
  final String village;
  final String address;
  final String type;
  final String flood;
  final String earthquake;
  final String landslide;
  final String tsunami;
  final String reliefStation;
  final String accessible;
  final String indoor;
  final String outdoor;
  final List<String> serviceVillages;
  final int capacity;
  final String area;
  final String contactName;
  final String contactPhone;
  final String managerName;
  final String managerPhone;
  final String remarks;

  /// 座標y. Null for the shelters the coordinate table could not locate —
  /// about 5% of the dataset, mostly parks and intersections whose 門牌地址 is
  /// a description rather than an address.
  final double? latitude;

  /// 座標x.
  final double? longitude;

  /// Which dataset the coordinate came from: nfa_point_file, taipei_airraid,
  /// osm_overpass or manual.
  final String? coordinateSource;

  /// exact / name_match / approx. `approx` means the point was interpolated
  /// from a neighbouring street number and may be off by a building or two.
  final String? coordinateConfidence;

  /// Only present in `GET /api/shelters/nearby` responses.
  final int? distanceMeters;

  bool get hasCoordinate => latitude != null && longitude != null;

  /// True when the point is good enough to navigate to without a caveat.
  bool get isCoordinateExact => coordinateConfidence == 'exact';

  static String _string(dynamic value) => value?.toString() ?? '';

  static double? _coordinate(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  factory Shelter.fromJson(Map<String, dynamic> json) {
    final rawImportDate = json['importDate'];
    return Shelter(
      id: json['id'] is int ? json['id'] as int : 0,
      importDate: rawImportDate is String
          ? DateTime.tryParse(rawImportDate)
          : null,
      shelterId: _string(json['收容所編號']),
      name: _string(json['名稱']),
      city: _string(json['縣市']),
      postalCode: _string(json['郵遞區號']),
      district: _string(json['鄉鎮']),
      village: _string(json['村里']),
      address: _string(json['門牌地址']),
      type: _string(json['類型']),
      flood: _string(json['水災']),
      earthquake: _string(json['震災']),
      landslide: _string(json['土石流']),
      tsunami: _string(json['海嘯']),
      reliefStation: _string(json['救濟支站']),
      accessible: _string(json['無障礙設施']),
      indoor: _string(json['室內']),
      outdoor: _string(json['室外']),
      serviceVillages:
          (json['服務里別'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
      capacity: json['容納人數'] is int ? json['容納人數'] as int : 0,
      area: _string(json['收容所面積(平方公尺)']),
      contactName: _string(json['聯絡人姓名']),
      contactPhone: _string(json['聯絡人連絡電話']),
      managerName: _string(json['管理人姓名']),
      managerPhone: _string(json['管理人連絡電話']),
      remarks: _string(json['備考']),
      // Note the swap: 座標y is the latitude and 座標x the longitude.
      latitude: _coordinate(json['座標y']),
      longitude: _coordinate(json['座標x']),
      coordinateSource: json['座標來源'] as String?,
      coordinateConfidence: json['座標精度'] as String?,
      distanceMeters: json['距離公尺'] is int ? json['距離公尺'] as int : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'importDate': importDate?.toIso8601String(),
    '收容所編號': shelterId,
    '名稱': name,
    '縣市': city,
    '郵遞區號': postalCode,
    '鄉鎮': district,
    '村里': village,
    '門牌地址': address,
    '類型': type,
    '水災': flood,
    '震災': earthquake,
    '土石流': landslide,
    '海嘯': tsunami,
    '救濟支站': reliefStation,
    '無障礙設施': accessible,
    '室內': indoor,
    '室外': outdoor,
    '服務里別': serviceVillages,
    '容納人數': capacity,
    '收容所面積(平方公尺)': area,
    '聯絡人姓名': contactName,
    '聯絡人連絡電話': contactPhone,
    '管理人姓名': managerName,
    '管理人連絡電話': managerPhone,
    '備考': remarks,
    '座標y': latitude,
    '座標x': longitude,
    '座標來源': coordinateSource,
    '座標精度': coordinateConfidence,
  };
}
