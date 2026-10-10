import 'dart:convert';

import 'package:flutter_codefest/data/models/shelter.dart';

/// A saved summary survives renamed/deleted upstream records. The stable source
/// code is the identity; the ordinal `id` is deliberately never used as a key.
class SavedShelter {
  const SavedShelter({
    required this.shelter,
    required this.savedAt,
    this.group = '常用',
    this.note = '',
    this.status = 'saved',
  });
  final Shelter shelter;
  final DateTime savedAt;
  final String group;
  final String note;
  final String status; // saved / updated / unavailable

  factory SavedShelter.fromJson(Map<String, dynamic> json) => SavedShelter(
    shelter: Shelter.fromJson(json['shelter'] as Map<String, dynamic>),
    savedAt: DateTime.parse(json['savedAt'] as String),
    group: json['group'] as String? ?? '常用',
    note: json['note'] as String? ?? '',
    status: json['status'] as String? ?? 'saved',
  );
  Map<String, dynamic> toJson() => {
    'shelter': shelter.toJson(),
    'savedAt': savedAt.toIso8601String(),
    'group': group,
    'note': note,
    'status': status,
  };
}

class OfflinePackage {
  const OfflinePackage({
    required this.city,
    this.township,
    required this.version,
    required this.downloadedAt,
    required this.shelters,
    this.dataUpdatedAt,
    this.freshness,
  });
  final String city;
  final String? township;
  final String version;
  final DateTime downloadedAt;
  final DateTime? dataUpdatedAt;
  final String? freshness;
  final List<Shelter> shelters;
  String get key => '$city|${township ?? ''}';
  String get label => '$city${township ?? ''}';
  int get bytes => utf8.encode(jsonEncode(toJson())).length;

  factory OfflinePackage.fromJson(
    Map<String, dynamic> json, {
    DateTime? downloadedAt,
  }) {
    if (json['schemaVersion'] != 1 || json['truncated'] != false) {
      throw const FormatException('資料包格式不支援或資料不完整');
    }
    final coverage = json['coverage'] as Map<String, dynamic>;
    final city = coverage['city'] as String;
    final township = coverage['township'] as String?;
    final shelters = (json['data'] as List)
        .map((e) => Shelter.fromJson(e as Map<String, dynamic>))
        .toList();
    if (city.isEmpty ||
        shelters.isEmpty ||
        shelters.length != json['total'] ||
        shelters.any(
          (s) =>
              s.shelterId.isEmpty ||
              s.city != city ||
              (township != null && s.district != township),
        ) ||
        shelters.map((s) => s.shelterId).toSet().length != shelters.length) {
      throw const FormatException('資料包筆數或涵蓋範圍不一致');
    }
    return OfflinePackage(
      city: city,
      township: township,
      version: json['snapshotVersion'] as String,
      downloadedAt:
          downloadedAt ?? DateTime.parse(json['downloadedAt'] as String),
      dataUpdatedAt: DateTime.tryParse(json['dataUpdatedAt']?.toString() ?? ''),
      freshness: json['dataFreshness'] as String?,
      shelters: List.unmodifiable(shelters),
    );
  }
  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'snapshotVersion': version,
    'coverage': {'city': city, if (township != null) 'township': township},
    'downloadedAt': downloadedAt.toIso8601String(),
    'dataUpdatedAt': dataUpdatedAt?.toIso8601String(),
    'dataFreshness': freshness,
    'total': shelters.length,
    'truncated': false,
    'data': shelters.map((s) => s.toJson()).toList(),
  };
}

class FamilyPlan {
  const FamilyPlan({
    this.title = '我的家庭避難計畫',
    this.primary,
    this.backup,
    this.contact = '',
    this.notes = '',
    this.checked = const {},
    this.updatedAt,
  });
  final String title;
  final Shelter? primary;
  final Shelter? backup;
  final String contact;
  final String notes;
  final Set<String> checked;
  final DateTime? updatedAt;
  static const checklist = [
    '飲水與食物',
    '常用藥品',
    '行動電源與照明',
    '證件與緊急聯絡資訊',
    '確認主要與備用集合點',
  ];
  factory FamilyPlan.fromJson(Map<String, dynamic> json) => FamilyPlan(
    title: json['title'] as String? ?? '我的家庭避難計畫',
    primary: json['primary'] == null
        ? null
        : Shelter.fromJson(json['primary'] as Map<String, dynamic>),
    backup: json['backup'] == null
        ? null
        : Shelter.fromJson(json['backup'] as Map<String, dynamic>),
    contact: json['contact'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    checked: (json['checked'] as List? ?? []).cast<String>().toSet(),
    updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
  );
  Map<String, dynamic> toJson() => {
    'title': title,
    'primary': primary?.toJson(),
    'backup': backup?.toJson(),
    'contact': contact,
    'notes': notes,
    'checked': checked.toList(),
    'updatedAt': updatedAt?.toIso8601String(),
  };
}
