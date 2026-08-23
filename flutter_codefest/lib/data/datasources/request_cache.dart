import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One cached response, with the moment it was stored — shown to the user
/// so a stale fallback never reads as live data.
class CachedResponse {
  const CachedResponse({required this.body, required this.cachedAt});

  final Map<String, dynamic> body;
  final DateTime cachedAt;
}

/// A small LRU cache of decoded API response bodies, keyed by a canonical
/// request key (see [keyFor]).
///
/// This replaces the old `ShelterCache`, which persisted the **entire**
/// ~5,850-shelter list into shared_preferences — on web that is one
/// localStorage entry of ~4-5 MB, right at the platform's quota. Since the
/// app now fetches per-viewport clusters and paginated search pages, cached
/// entries are a few KB to a few hundred KB each; bounding the store to a
/// dozen entries keeps the whole thing comfortably under 1 MB while still
/// giving the "API is unreachable, show the last thing you saw" fallback.
///
/// Entries are raw response-shaped JSON (`{'clusters': [...]}`,
/// `{'data': [...], 'total': ..., 'truncated': ...}`), so the same
/// `fromJson` used for network responses reads them back — no second parser
/// to drift.
class RequestCache {
  RequestCache._();

  static const _storeKey = 'request_cache_v1';

  /// Eviction bounds: a dozen recent viewports/pages is more than a single
  /// session normally touches, and ~700K chars of JSON keeps the store
  /// clear of localStorage quotas even with generous per-entry sizes.
  static const int maxEntries = 12;
  static const int maxTotalChars = 700 * 1024;

  static final Future<SharedPreferences> _prefs =
      SharedPreferences.getInstance();

  /// A stable key for one request: FNV-1a over the path plus its query
  /// parameters, sorted so `?a=1&b=2` and `?b=2&a=1` share a cache entry.
  static String keyFor(String path, Map<String, String> queryParams) {
    final entries = queryParams.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final raw = '$path?'
        '${entries.map((e) => '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}').join('&')}';

    // FNV-1a 64-bit. Parsed from hex strings rather than int literals: the
    // constants exceed 2^53, which dart2js (web) cannot represent in a
    // double-backed literal.
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    for (final code in raw.codeUnits) {
      hash ^= BigInt.from(code);
      hash =
          (hash * BigInt.parse('100000001b3', radix: 16)) &
          BigInt.parse('ffffffffffffffff', radix: 16);
    }
    return hash.toRadixString(16);
  }

  static Future<void> put(String key, Map<String, dynamic> body) async {
    try {
      final entries = await _readEntries();
      entries.removeWhere((e) => e['k'] == key);
      // Newest first; eviction trims from the tail.
      entries.insert(0, {
        'k': key,
        'at': DateTime.now().toIso8601String(),
        'body': jsonEncode(body),
      });

      var totalChars = 0;
      final kept = <Map<String, dynamic>>[];
      for (final entry in entries) {
        totalChars += (entry['body'] as String).length;
        if (kept.length >= maxEntries || totalChars > maxTotalChars) break;
        kept.add(entry);
      }

      final prefs = await _prefs;
      await prefs.setString(_storeKey, jsonEncode(kept));
    } catch (_) {
      // A cache write that fails (quota, storage disabled) must never take
      // down the fetch that succeeded — caching is best-effort by design.
    }
  }

  /// Returns the cached body for [key] (moving it to the front as the most
  /// recently used), or null if there is none or it cannot be parsed — a
  /// corrupt cache must not crash the app, just behave as if it were empty.
  static Future<CachedResponse?> get(String key) async {
    try {
      final entries = await _readEntries();
      final index = entries.indexWhere((e) => e['k'] == key);
      if (index < 0) return null;

      final entry = entries.removeAt(index);
      entries.insert(0, entry);
      final prefs = await _prefs;
      await prefs.setString(_storeKey, jsonEncode(entries));

      return CachedResponse(
        body: jsonDecode(entry['body'] as String) as Map<String, dynamic>,
        cachedAt: DateTime.tryParse(entry['at'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _readEntries() async {
    try {
      final prefs = await _prefs;
      final raw = prefs.getString(_storeKey);
      if (raw == null) return <Map<String, dynamic>>[];
      return (jsonDecode(raw) as List<dynamic>)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}
