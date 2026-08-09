import 'dart:io';

/// Application configuration.
///
/// Every tunable resolves in this order:
///   1. process environment (`PORT=3000 dart run bin/server.dart`)
///   2. the optional `.env` file next to `pubspec.yaml`
///   3. the compile-time default below
///
/// Call [load] once at startup before reading any getter. See `.env.example`
/// for the supported keys.
class Env {
  static const baseUrl = "https://data.taipei/api/v1/dataset";

  /// 臺北市可供避難收容處所一覽表 — 401 records, no coordinate columns.
  static const shelterDatasetId = '4c92dbd4-d259-495a-8390-52628119a4dd';

  /// 北市警政APP_防空避難設備位置 — 6052 records that *do* carry 座標x/座標y.
  /// Used offline by tool/build_coordinates.dart.
  static const airRaidDatasetId = '39ca53a1-c861-40bc-b329-fc9b28c10e01';

  static const defaultPort = 8080;
  static const defaultLogLevel = 'info';

  /// The committed coordinate table. The OpenData dataset carries no
  /// 座標x/座標y, so this file is the only source of coordinates.
  /// Rebuild with `dart run tool/build_coordinates.dart`.
  static const defaultCoordinatesCsvPath = 'data/shelter_coordinates.csv';

  /// How long an upstream fetch stays fresh. The dataset is republished a few
  /// times a year, so anything on this scale is generous; the point is to stop
  /// re-downloading 401 records on every single request.
  static const defaultCacheTtlSeconds = 600;

  /// Upper bound on records pulled from upstream. The dataset holds 401, so
  /// this is only a runaway guard.
  static const maxUpstreamItems = 3000;

  static Map<String, String> _fileValues = const {};
  static bool _loaded = false;

  /// Reads `path` if it exists. Missing file is not an error — the process
  /// environment and the defaults still apply.
  static void load({String path = '.env'}) {
    _loaded = true;
    final file = File(path);
    if (!file.existsSync()) {
      _fileValues = const {};
      return;
    }
    _fileValues = _parse(file.readAsLinesSync());
  }

  static Map<String, String> _parse(List<String> lines) {
    final out = <String, String>{};
    for (final raw in lines) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) line = line.substring(7).trim();

      final eq = line.indexOf('=');
      if (eq <= 0) continue;

      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      if (key.isNotEmpty) out[key] = value;
    }
    return out;
  }

  static String? _read(String key) {
    final fromProcess = Platform.environment[key];
    if (fromProcess != null && fromProcess.isNotEmpty) return fromProcess;
    final fromFile = _fileValues[key];
    if (fromFile != null && fromFile.isNotEmpty) return fromFile;
    return null;
  }

  /// True once [load] has run, so callers can warn about reading config early.
  static bool get isLoaded => _loaded;

  static int get port => int.tryParse(_read('PORT') ?? '') ?? defaultPort;

  static String get coordinatesCsvPath =>
      _read('COORDINATES_CSV') ?? defaultCoordinatesCsvPath;

  static Duration get cacheTtl => Duration(
    seconds:
        int.tryParse(_read('CACHE_TTL_SECONDS') ?? '') ??
        defaultCacheTtlSeconds,
  );

  static String get logLevel =>
      (_read('LOG_LEVEL') ?? defaultLogLevel).toLowerCase();
}
