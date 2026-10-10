import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_codefest/core/platform/preparedness_platform.dart'
    as platform;
import 'package:flutter_codefest/data/models/preparedness.dart';
import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_codefest/data/models/disaster_alert.dart';

/// One atomic, versioned document in IndexedDB on Web. Writes are serialized
/// and state is published only AFTER commit, including quota/storage failures.
class PreparednessStore extends ChangeNotifier {
  PreparednessStore({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? platform.readLibrary,
       _write = write ?? platform.writeLibrary;
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  Future<void> _queue = Future.value();
  Map<String, dynamic> _document = {'schemaVersion': 1};
  bool ready = false;
  String? storageError;
  List<SavedShelter> _favorites = [];
  List<OfflinePackage> _packages = [];
  FamilyPlan _plan = const FamilyPlan();
  List<AlertRegion> _alertRegions = [];
  List<SavedShelter> get favorites => List.unmodifiable(_favorites);
  List<OfflinePackage> get packages => List.unmodifiable(_packages);
  FamilyPlan get plan => _plan;
  List<AlertRegion> get alertRegions => List.unmodifiable(_alertRegions);
  bool get offlineMode => _document['offlineMode'] == true;
  bool get listMode => _document['listMode'] == true;
  bool get largeText => _document['largeText'] == true;
  ThemeMode get themeMode => switch (_document['theme']) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.light,
  };
  int dataRevision = 0;

  Future<void> load() async {
    try {
      final raw = await _read();
      final next = raw == null
          ? <String, dynamic>{'schemaVersion': 1}
          : jsonDecode(raw) as Map<String, dynamic>;
      _decode(next);
      _document = next;
      storageError = null;
    } catch (_) {
      storageError = '無法讀取裝置資料，收藏與下載暫時無法儲存。請檢查瀏覽器儲存設定後重試。';
    }
    ready = true;
    notifyListeners();
  }

  void _decode(Map<String, dynamic> value) {
    if (value['schemaVersion'] != 1) {
      throw const FormatException('Unknown library version');
    }
    final favorites = (value['favorites'] as List? ?? [])
        .map((e) => SavedShelter.fromJson(e as Map<String, dynamic>))
        .toList();
    final packages = (value['packages'] as List? ?? [])
        .map((e) => OfflinePackage.fromJson(e as Map<String, dynamic>))
        .toList();
    final plan = FamilyPlan.fromJson(
      value['plan'] as Map<String, dynamic>? ?? {},
    );
    final alertRegions = (value['alertRegions'] as List? ?? [])
        .map((e) => AlertRegion.fromJson(e as Map<String, dynamic>))
        .toList();
    _favorites = favorites;
    _packages = packages;
    _plan = plan;
    _alertRegions = alertRegions;
  }

  Future<void> _change(
    void Function(Map<String, dynamic>) edit, {
    bool data = false,
  }) {
    final operation = _queue.then((_) async {
      if (!ready || storageError != null) throw StateError('裝置儲存尚未就緒');
      final next = Map<String, dynamic>.of(_document);
      edit(next);
      next['_revision'] = ((_document['_revision'] as num?)?.toInt() ?? 0) + 1;
      await _write(jsonEncode(next));
      _decode(next);
      _document = next;
      if (data) dataRevision++;
      notifyListeners();
    });
    _queue = operation.catchError((_) {});
    return operation;
  }

  SavedShelter? favorite(String code) {
    for (final item in _favorites) {
      if (item.shelter.shelterId == code) return item;
    }
    return null;
  }

  Future<void> saveFavorite(
    Shelter shelter, {
    String group = '常用',
    String note = '',
    String status = 'saved',
  }) => _change((next) {
    final previous = favorite(shelter.shelterId);
    next['favorites'] = [
      for (final f in _favorites)
        if (f.shelter.shelterId != shelter.shelterId) f.toJson(),
      SavedShelter(
        shelter: shelter,
        savedAt: previous?.savedAt ?? DateTime.now(),
        group: group.trim().isEmpty ? '常用' : group.trim(),
        note: note.trim(),
        status: status,
      ).toJson(),
    ];
  });
  Future<void> removeFavorite(String code) => _change((next) {
    next['favorites'] = [
      for (final f in _favorites)
        if (f.shelter.shelterId != code) f.toJson(),
    ];
  });
  Future<void> savePlan(FamilyPlan plan) => _change((next) {
    next['plan'] = plan.toJson();
  });
  Future<void> followAlertRegion(AlertRegion region) => _change((next) {
    final regions = alertRegions.where((r) => r.key != region.key).toList();
    if (regions.length >= 8) throw StateError('最多可關注 8 個區域');
    next['alertRegions'] = [...regions.map((r) => r.toJson()), region.toJson()];
  });
  Future<void> unfollowAlertRegion(AlertRegion region) => _change((next) {
    next['alertRegions'] = [
      for (final r in alertRegions)
        if (r.key != region.key) r.toJson(),
    ];
  });
  Future<void> savePackage(OfflinePackage package) => _change((next) {
    next['packages'] = [
      for (final p in _packages)
        if (p.key != package.key) p.toJson(),
      package.toJson(),
    ];
  }, data: true);
  Future<void> removePackage(String key) => _change((next) {
    next['packages'] = [
      for (final p in _packages)
        if (p.key != key) p.toJson(),
    ];
    if ((next['packages'] as List).isEmpty) next['offlineMode'] = false;
  }, data: true);
  Future<void> settings({
    ThemeMode? theme,
    bool? largeText,
    bool? listMode,
    bool? offlineMode,
  }) => _change((next) {
    if (theme != null) next['theme'] = theme.name;
    if (largeText != null) next['largeText'] = largeText;
    if (listMode != null) next['listMode'] = listMode;
    if (offlineMode != null) next['offlineMode'] = offlineMode;
  }, data: offlineMode != null);

  /// Newer overlapping packages win; one shelter appears only once.
  List<Shelter> get offlineShelters {
    final sorted = [..._packages]
      ..sort((a, b) => a.downloadedAt.compareTo(b.downloadedAt));
    final byCode = <String, Shelter>{};
    for (final p in sorted) {
      for (final s in p.shelters) {
        byCode[s.shelterId] = s;
      }
    }
    return byCode.values.toList();
  }

  Shelter? savedShelter(String code) {
    for (final s in offlineShelters) {
      if (s.shelterId == code) return s;
    }
    if (_plan.primary?.shelterId == code) return _plan.primary;
    if (_plan.backup?.shelterId == code) return _plan.backup;
    return favorite(code)?.shelter;
  }

  String get coverageLabel => _packages.map((p) => p.label).join('、');
}
