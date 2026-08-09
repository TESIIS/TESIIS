// lib/data/models/shelter_model.dart

import '../../domain/entities/shelter_fields.dart';

class ShelterModel {
  final int id;
  final DateTime? importDate;
  final String shelterCode;
  final String name;
  final String city;
  final String zipcode;
  final String township;
  final String village;
  final String address;
  final String type;
  final String? flood;
  final String? quake;
  final String? landslide;
  final String? tsunami;
  final String? relief;
  final String? accessible;
  final String? indoor;
  final String? outdoor;
  final String? serviceVillages;
  final int capacity;
  final double? area;
  final String? contactName;
  final String? contactPhone;
  final String? managerName;
  final String? managerPhone;
  final String? notes;
  final double? x;
  final double? y;

  ShelterModel({
    required this.id,
    required this.importDate,
    required this.shelterCode,
    required this.name,
    required this.city,
    required this.zipcode,
    required this.township,
    required this.village,
    required this.address,
    required this.type,
    this.flood,
    this.quake,
    this.landslide,
    this.tsunami,
    this.relief,
    this.accessible,
    this.indoor,
    this.outdoor,
    this.serviceVillages,
    required this.capacity,
    this.area,
    this.contactName,
    this.contactPhone,
    this.managerName,
    this.managerPhone,
    this.notes,
    this.x,
    this.y,
  });

  factory ShelterModel.fromJson(Map<String, dynamic> json) {
    DateTime? importDate;
    try {
      final import = json['_importdate'] as Map<String, dynamic>?;
      final dateStr = import?['date'] as String?;
      if (dateStr != null) importDate = DateTime.tryParse(dateStr);
    } catch (_) {}

    // Numbers arrive as strings, sometimes with a thousands separator
    // ("14,495") and sometimes as free text ("俟搬遷後重新評估"); see
    // ShelterNumber.
    return ShelterModel(
      id: ShelterNumber.parseInt(json['_id']),
      importDate: importDate,
      shelterCode: (json['收容所編號'] ?? '').toString(),
      name: (json['名稱'] ?? '').toString(),
      city: (json['縣市'] ?? '').toString(),
      zipcode: (json['郵遞區號'] ?? '').toString(),
      township: (json['鄉鎮'] ?? '').toString(),
      village: (json['村里'] ?? '').toString(),
      address: (json['門牌地址'] ?? '').toString(),
      type: (json['類型'] ?? '').toString(),
      flood: json['水災']?.toString(),
      quake: json['震災']?.toString(),
      landslide: json['土石流']?.toString(),
      tsunami: json['海嘯']?.toString(),
      relief: json['救濟支站']?.toString(),
      accessible: json['無障礙設施']?.toString(),
      indoor: json['室內']?.toString(),
      outdoor: json['室外']?.toString(),
      serviceVillages: json['服務里別']?.toString(),
      capacity: ShelterNumber.parseInt(json['容納人數']),
      area: ShelterNumber.parseDouble(
        json['收容所面積（平方公尺）'] ?? json['收容所面積'] ?? json['面積'],
      ),
      contactName: json['聯絡人姓名']?.toString(),
      contactPhone: json['聯絡人連絡電話']?.toString(),
      managerName: json['管理人姓名']?.toString(),
      managerPhone: json['管理人連絡電話']?.toString(),
      notes: json['備考']?.toString(),
      x: ShelterNumber.parseDouble(
        json['座標x'] ?? json['X'] ?? json['longitude'],
      ),
      y: ShelterNumber.parseDouble(
        json['座標y'] ?? json['Y'] ?? json['latitude'],
      ),
    );
  }
}
