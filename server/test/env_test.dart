import 'package:server/core/config/env.dart';
import 'package:test/test.dart';

void main() {
  // Env reads the process environment first, so these exercise the parsing and
  // defaulting behaviour that applies when nothing is set. The tests would be
  // meaningless if the surrounding environment defined these keys.
  setUp(Env.load);

  group('Env defaults', () {
    test('port', () {
      expect(Env.port, Env.defaultPort);
    });

    test('coordinate table path', () {
      expect(Env.coordinatesCsvPath, Env.defaultCoordinatesCsvPath);
    });

    test('cache TTL', () {
      expect(Env.cacheTtl, Duration(seconds: Env.defaultCacheTtlSeconds));
    });

    test('log level is lower-cased', () {
      expect(Env.logLevel, Env.defaultLogLevel);
      expect(Env.logLevel, Env.logLevel.toLowerCase());
    });

    test('upstream base URL', () {
      expect(Env.baseUrl, Env.defaultBaseUrl);
    });
  });

  group('.env parsing', () {
    test('a negative cache TTL clamps to zero', () {
      // A negative Duration makes the freshness check always fail, disabling
      // the cache in a way nobody reading the config would predict.
      Env.loadFromLines(['CACHE_TTL_SECONDS=-30']);
      expect(Env.cacheTtl, Duration.zero);
    });

    test('zero is honoured — it means never serve from cache', () {
      Env.loadFromLines(['CACHE_TTL_SECONDS=0']);
      expect(Env.cacheTtl, Duration.zero);
    });

    test('a non-numeric TTL falls back to the default', () {
      Env.loadFromLines(['CACHE_TTL_SECONDS=soon']);
      expect(Env.cacheTtl, Duration(seconds: Env.defaultCacheTtlSeconds));
    });

    test('comments, blank lines and export prefixes', () {
      Env.loadFromLines([
        '# a comment',
        '',
        'export PORT=3000',
        'LOG_LEVEL=DEBUG',
      ]);
      expect(Env.port, 3000);
      expect(Env.logLevel, 'debug');
    });

    test('quoted values are unwrapped', () {
      Env.loadFromLines(['COORDINATES_CSV="/tmp/table.csv"']);
      expect(Env.coordinatesCsvPath, '/tmp/table.csv');
    });

    test('an empty value falls through to the default', () {
      Env.loadFromLines(['COORDINATES_CSV=']);
      expect(Env.coordinatesCsvPath, Env.defaultCoordinatesCsvPath);
    });

    test('upstream base URL can be overridden', () {
      Env.loadFromLines([
        'UPSTREAM_BASE_URL=https://proxy.example.com/dataset',
      ]);
      expect(Env.baseUrl, 'https://proxy.example.com/dataset');
    });
  });
}
