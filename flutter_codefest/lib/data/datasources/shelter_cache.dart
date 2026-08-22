import 'dart:convert';

import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A previously-fetched shelter list, plus when it was fetched — shown to
/// the user so a stale fallback never reads as live data.
class CachedShelters {
  const CachedShelters({required this.shelters, required this.cachedAt});

  final List<Shelter> shelters;
  final DateTime cachedAt;
}

/// Persists the last successful `GET /shelters` response so the app still
/// has something to show if the API becomes unreachable after first load —
/// e.g. a flaky network right after a disaster. Mirrors the server's own
/// stale-on-error caching (`ShelterRepositoryImpl`), but client-side.
class ShelterCache {
  static const _sheltersKey = 'cached_shelters_v1';
  static const _cachedAtKey = 'cached_shelters_at_v1';

  static Future<void> save(List<Shelter> shelters) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sheltersKey,
      jsonEncode(shelters.map((s) => s.toJson()).toList()),
    );
    await prefs.setString(_cachedAtKey, DateTime.now().toIso8601String());
  }

  /// Returns null if there is no cache, or if it can't be parsed (a corrupt
  /// cache must not crash the app — just behave as if there were none).
  static Future<CachedShelters?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sheltersKey);
      final cachedAtRaw = prefs.getString(_cachedAtKey);
      if (raw == null || cachedAtRaw == null) return null;

      final cachedAt = DateTime.tryParse(cachedAtRaw);
      if (cachedAt == null) return null;

      final decoded = jsonDecode(raw) as List<dynamic>;
      final shelters = decoded
          .map((e) => Shelter.fromJson(e as Map<String, dynamic>))
          .toList();
      return CachedShelters(shelters: shelters, cachedAt: cachedAt);
    } catch (_) {
      return null;
    }
  }
}
