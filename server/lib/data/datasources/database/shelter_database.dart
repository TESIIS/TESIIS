import 'package:sqlite3/sqlite3.dart';
import 'dart:io';
import '../../../core/errors/app_exception.dart';

class ShelterDatabase {
  final Database db;
  // In-memory address index: normalizedAddress -> (lon, lat)
  final Map<String, (double lon, double lat)> _addressIndex = {};
  bool _indexBuilt = false;
  String? _addressColumn;
  String? _lonColumn;
  String? _latColumn;

  ShelterDatabase._(this.db);

  factory ShelterDatabase.open(String path) {
    final db = sqlite3.open(path);
    return ShelterDatabase._(db);
  }

  List<Map<String, Object?>> fetchShelters({
    String? query,
    String? city,
    int limit = 1000,
    int offset = 0,
  }) {
    try {
      // Check if geocoding table exists
      final tables = db.select('SELECT name FROM sqlite_master WHERE type="table" AND name="geocoding";');
      if (tables.isEmpty) {
        throw NotFoundException('geocoding 資料表不存在', code: 'MISSING_GEOCODING_TABLE');
      }

      // detect available columns in geocoding table
      final colsRes = db.select("PRAGMA table_info(geocoding)");
      final available = colsRes.map((r) => (r['name'] as String).toLowerCase()).toList();

      // candidate address columns to match against
      final addrCandidates = ['address', 'formatted_address', 'formattedaddress', '門牌地址'];
      final matchedAddrCols = addrCandidates.where((c) => available.contains(c)).toList();

      // build query
      final params = <Object?>[];
      final buffer = StringBuffer('SELECT * FROM geocoding WHERE status = "OK"');

      if (query != null && query.isNotEmpty) {
        if (matchedAddrCols.isNotEmpty) {
          buffer.write(' AND (');
          for (var i = 0; i < matchedAddrCols.length; i++) {
            if (i > 0) buffer.write(' OR ');
            buffer.write('${matchedAddrCols[i]} LIKE ?');
            params.add('%$query%');
          }
          buffer.write(')');
        } else {
          // fallback to address column name
          buffer.write(' AND address LIKE ?');
          params.add('%$query%');
        }
      }

      if (city != null && city.isNotEmpty) {
        if (matchedAddrCols.isNotEmpty) {
          buffer.write(' AND (');
          for (var i = 0; i < matchedAddrCols.length; i++) {
            if (i > 0) buffer.write(' OR ');
            buffer.write('${matchedAddrCols[i]} LIKE ?');
            params.add('%$city%');
          }
          buffer.write(')');
        } else {
          buffer.write(' AND address LIKE ?');
          params.add('%$city%');
        }
      }

      buffer.write(' LIMIT ? OFFSET ?');
      params.add(limit);
      params.add(offset);

      final result = db.select(buffer.toString(), params);
      return result.map((row) => row.toTableColumnMap() as Map<String, Object?>).toList();
    } on NotFoundException {
      rethrow; // 讓 NotFoundException 繼續往上拋出
    } catch (e) {
      throw ServerException('查詢座標資料庫時發生錯誤：$e', code: 'GEOCODING_QUERY_ERROR');
    }
  }

  void close() => db.dispose();

  /// Return list of column names for a given table (lowercased)
  List<String> tableColumns(String table) {
    try {
      final res = db.select('PRAGMA table_info($table)');
      return res.map((r) => (r['name'] as String).toLowerCase()).toList();
    } catch (_) {
      return <String>[];
    }
  }

  /// Return list of user tables in the database (their names)
  List<String> listTables() {
    try {
      final res = db.select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';");
      return res.map((r) => r['name'] as String).toList();
    } catch (_) {
      return <String>[];
    }
  }

  // --- New: Build a global address->coords index for fast fill ---
  void buildAddressIndex({String? preferredTable}) {
    if (_indexBuilt) return; // idempotent
    try {
      final tables = preferredTable != null && preferredTable.isNotEmpty
          ? [preferredTable]
          : listTables();
      if (tables.isEmpty) return;

      // Heuristic scoring to pick best table: has address-like + 2 coord columns & more than 0 rows
      String? bestTable;
      int bestScore = -1;
      for (final t in tables) {
        final cols = tableColumns(t);
        if (cols.isEmpty) continue;
        final lower = cols.map((c) => c.toLowerCase()).toList();
        final hasAddr = lower.any((c) => c.contains('address') || c.contains('門牌') || c.contains('住址'));
        final hasLon = lower.any((c) => c.contains('lon') || c.contains('lng') || c.contains('x') || c.contains('經度'));
        final hasLat = lower.any((c) => c.contains('lat') || c.contains('y') || c.contains('緯度'));
        if (hasAddr && hasLon && hasLat) {
          final score = (hasAddr ? 1 : 0) + (hasLon ? 1 : 0) + (hasLat ? 1 : 0) + lower.length;
          if (score > bestScore) {
            bestScore = score;
            bestTable = t;
          }
        }
      }
      bestTable ??= tables.first; // fallback

      final cols = tableColumns(bestTable);
      if (cols.isEmpty) return;
      // Determine column names
      _addressColumn = cols.firstWhere(
        (c) => c.contains('address') || c.contains('門牌') || c.contains('住址'),
        orElse: () => cols.first,
      );
      _lonColumn = cols.firstWhere(
        (c) => c == 'lon' || c == 'lng' || c.contains('longitude') || c == 'x' || c.contains('經度'),
        orElse: () => 'lon',
      );
      _latColumn = cols.firstWhere(
        (c) => c == 'lat' || c.contains('latitude') || c == 'y' || c.contains('緯度'),
        orElse: () => 'lat',
      );

      // Attempt to select all rows (may be large; assume manageable). If huge, could add LIMIT or streaming.
      final sql = 'SELECT * FROM ' + bestTable;
      final rows = db.select(sql);
      for (final row in rows) {
        final rawAddr = row[_addressColumn];
        if (rawAddr == null) continue;
        final addrStr = rawAddr.toString();
        final norm = _normalizeAddress(addrStr);
        final lonVal = row[_lonColumn];
        final latVal = row[_latColumn];
        final lon = _parseNum(lonVal);
        final lat = _parseNum(latVal);
        if (norm.isEmpty || lon == null || lat == null) continue;
        _addressIndex.putIfAbsent(norm, () => (lon, lat));
      }
      _indexBuilt = true;
      stdout.writeln('[ShelterDatabase] Address index built: ${_addressIndex.length} entries (table=$bestTable, addrCol=$_addressColumn lonCol=$_lonColumn latCol=$_latColumn)');
    } catch (e) {
      stdout.writeln('[ShelterDatabase] Failed building address index: $e');
    }
  }

  (double lon, double lat)? lookupAddress(String address) {
    if (!_indexBuilt) return null;
    final norm = _normalizeAddress(address);
    return _addressIndex[norm];
  }

  String _normalizeAddress(String input) {
    var s = input.trim();
    // Normalize 台 / 臺
    s = s.replaceAll('臺', '台');
    // Remove whitespace & certain punctuation and floor/level markers
    s = s.replaceAll(RegExp(r'[\s,、，。\.()（）:：;；-]'), '');
    // Remove common floor/level indicators after number (e.g., 3樓, 5F)
    s = s.replaceAll(RegExp(r'[0-9]+樓'), '');
    s = s.replaceAll(RegExp(r'[0-9]+F', caseSensitive: false), '');
    return s;
  }

  double? _parseNum(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  /// Return sample rows from a table (as list of maps)
  List<Map<String, Object?>> sampleRows(String table, {int limit = 5}) {
    try {
      final res = db.select('SELECT * FROM $table LIMIT ?', [limit]);
      return res.map((r) => r.toTableColumnMap() as Map<String, Object?>).toList();
    } catch (_) {
      return <Map<String, Object?>>[];
    }
  }
}
