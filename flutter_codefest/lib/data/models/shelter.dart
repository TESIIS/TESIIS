class Shelter {
  final int id;
  final DateTime importDate;
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
  final dynamic area;
  final String contactName;
  final String contactPhone;
  final String managerName;
  final String managerPhone;
  final String remarks;
  final dynamic latitude;
  final dynamic longitude;

  Shelter({
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
  });

  // 從 JSON 建構
  factory Shelter.fromJson(Map<String, dynamic> json) {
    return Shelter(
      id: json['id'],
      importDate: DateTime.parse(json['importDate']),
      shelterId: json['收容所編號'],
      name: json['名稱'],
      city: json['縣市'],
      postalCode: json['郵遞區號'],
      district: json['鄉鎮'],
      village: json['村里'],
      address: json['門牌地址'],
      type: json['類型'],
      flood: json['水災'],
      earthquake: json['震災'],
      landslide: json['土石流'],
      tsunami: json['海嘯'],
      reliefStation: json['救濟支站'],
      accessible: json['無障礙設施'],
      indoor: json['室內'],
      outdoor: json['室外'],
      serviceVillages:
          (json['服務里別'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          [],
      capacity: json['容納人數'],
      area: json['收容所面積(平方公尺)'],
      contactName: json['聯絡人姓名'],
      contactPhone: json['聯絡人連絡電話'],
      managerName: json['管理人姓名'],
      managerPhone: json['管理人連絡電話'],
      remarks: json['備考'],
      latitude: json['座標y'] != null ? (json['座標y'] as num).toDouble() : null,
      longitude: json['座標x'] != null ? (json['座標x'] as num).toDouble() : null,
    );
  }

  // 轉成 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'importDate': importDate.toIso8601String(),
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
    };
  }
}
