import 'package:server/data/datasources/local/coordinate_source.dart';
import 'package:test/test.dart';

const _header =
    'shelter_code,name,address,lng,lat,source,confidence,updated_at';

String _csv(List<String> rows) => '$_header\n${rows.join('\n')}\n';

void main() {
  group('CoordinateSource', () {
    test('looks up by shelter code', () {
      final source = CoordinateSource.fromCsv(
        _csv([
          'SA100-0002,螢橋國中,汀州路三段四號,121.5265,25.0190,nfa_point_file,exact,2026-08-09',
        ]),
      );
      final hit = source.lookupByCode('SA100-0002')!;
      expect(hit.lng, 121.5265);
      expect(hit.lat, 25.0190);
      expect(hit.source, CoordinateSourceKind.nfaPointFile);
      expect(hit.confidence, CoordinateConfidence.exact);
      expect(source.lookupByCode('NOPE'), isNull);
      expect(source.lookupByCode(null), isNull);
    });

    test('falls back to a normalised address match', () {
      final source = CoordinateSource.fromCsv(
        _csv([
          'SA100-0003,北市大附小,臺北市中正區公園路29號,121.5153,25.0363,taipei_airraid,exact,2026-08-09',
        ]),
      );
      // Same place, written the other way round.
      expect(source.lookupByAddress('公園路29號', township: '中正區'), isNotNull);
      // …and with a Chinese numeral, which normalisation folds to the same key.
      expect(source.lookupByAddress('公園路二九號', township: '中正區'), isNotNull);
      expect(source.lookupByAddress('公園路31號', township: '中正區'), isNull);
    });

    test('code wins over address', () {
      final source = CoordinateSource.fromCsv(
        _csv([
          'A,甲,中正區公園路29號,121.50,25.00,manual,exact,2026-08-09',
          'B,乙,中正區公園路31號,121.60,25.10,manual,exact,2026-08-09',
        ]),
      );
      final hit = source.lookup(shelterCode: 'B', address: '中正區公園路29號')!;
      expect(hit.lng, 121.60);
    });

    test('rejects coordinates outside the Taipei bounding box', () {
      // The 消防署 point file geocodes 北市大附小 to 屏東. A typo in the
      // committed table must not put a shelter in another county either.
      final source = CoordinateSource.fromCsv(
        _csv([
          'BAD,北市大附小,公園路29號,120.913,22.4797,nfa_point_file,exact,2026-08-09',
          'OK,弘道國中,公園路21號,121.5153,25.0375,nfa_point_file,exact,2026-08-09',
        ]),
      );
      expect(source.lookupByCode('BAD'), isNull);
      expect(source.lookupByCode('OK'), isNotNull);
      expect(source.coverage.total, 2);
      expect(source.coverage.withCoordinates, 1);
    });

    test('rows with no coordinate are counted, not dropped', () {
      // Coverage has to be auditable: a shelter we cannot locate is a known
      // gap, not a silent absence.
      final source = CoordinateSource.fromCsv(
        _csv([
          'A,甲,中正區公園路29號,121.51,25.03,manual,exact,2026-08-09',
          'B,乙,中山區樂群一路旁基隆河截彎取直範圍內,,,none,none,2026-08-09',
        ]),
      );
      expect(source.coverage.total, 2);
      expect(source.coverage.withCoordinates, 1);
      expect(source.coverage.bySource['none'], 1);
      expect(source.coverage.ratio, 0.5);
    });

    test('unknown source and confidence names degrade to none', () {
      final source = CoordinateSource.fromCsv(
        _csv(['A,甲,中正區公園路29號,121.51,25.03,martians,vibes,2026-08-09']),
      );
      final hit = source.lookupByCode('A')!;
      expect(hit.source, CoordinateSourceKind.none);
      expect(hit.confidence, CoordinateConfidence.none);
    });

    test('a missing required column fails loudly', () {
      expect(
        () => CoordinateSource.fromCsv('shelter_code,name\nA,甲\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('empty source answers every lookup with null', () {
      final source = CoordinateSource.empty();
      expect(source.lookup(shelterCode: 'A', address: 'anything'), isNull);
      expect(source.coverage.total, 0);
      expect(source.coverage.ratio, 0);
    });

    test('coverage serialises for the stats endpoint', () {
      final source = CoordinateSource.fromCsv(
        _csv([
          'A,甲,中正區公園路29號,121.51,25.03,manual,exact,2026-08-09',
          'B,乙,中正區公園路31號,,,none,none,2026-08-09',
        ]),
      );
      expect(source.coverage.toJson(), {
        'total': 2,
        'withCoordinates': 1,
        'missing': 1,
        'ratio': 0.5,
        'bySource': {'manual': 1, 'none': 1},
      });
    });
  });

  group('the committed coordinate table', () {
    test('loads and covers most of the dataset', () {
      // Guards the file the map actually depends on. If a rebuild or a manual
      // edit tanks coverage, this fails instead of quietly emptying the map.
      final source = CoordinateSource.loadFromFile(
        'data/shelter_coordinates.csv',
      );
      expect(source.coverage.total, greaterThanOrEqualTo(400));
      expect(
        source.coverage.ratio,
        greaterThan(0.90),
        reason:
            'coordinate coverage regressed; rerun tool/build_coordinates.dart',
      );
    });
  });
}
