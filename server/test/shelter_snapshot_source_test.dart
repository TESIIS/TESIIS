import 'package:server/data/datasources/local/shelter_snapshot_source.dart';
import 'package:test/test.dart';

String _csv(List<Map<String, String>> rows) {
  final header = shelterSnapshotCsvHeader;
  final buffer = StringBuffer()..writeln(header.join(','));
  for (final row in rows) {
    buffer.writeln(header.map((h) => row[h] ?? '').join(','));
  }
  return buffer.toString();
}

Map<String, String> _row({
  String sourceId = 'NFA-TPE-abc123',
  String source = 'nfa_point_file',
  String sourceUpdatedAt = '2026-08-23T00:00:00.000Z',
  String cityCode = 'TPE',
  String city = '臺北市',
  String township = '中正區',
  String village = '林興里',
  String name = '測試避難所',
  String address = '公園路29號',
  String lng = '121.5265',
  String lat = '25.0190',
  String coordinateConfidence = 'exact',
  String capacity = '100',
}) => {
  'source_id': sourceId,
  'source': source,
  'source_updated_at': sourceUpdatedAt,
  'city_code': cityCode,
  'city': city,
  'township': township,
  'village': village,
  'name': name,
  'address': address,
  'lng': lng,
  'lat': lat,
  'coordinate_confidence': coordinateConfidence,
  'capacity': capacity,
  'flood': 'Y',
  'quake': 'N',
  'landslide': 'N',
  'tsunami': 'N',
  'nuclear': 'N',
  'indoor': '是',
  'outdoor': '否',
  'accessible': '是',
  'service_villages': '',
  'manager_name': '',
  'manager_phone': '',
};

void main() {
  group('ShelterSnapshotSource.fromCsv', () {
    test('parses a well-formed snapshot', () {
      final source = ShelterSnapshotSource.fromCsv(_csv([_row()]));
      expect(source.shelters, hasLength(1));
      final s = source.shelters.first;
      expect(s.shelterCode, 'NFA-TPE-abc123');
      expect(s.city, '臺北市');
      expect(s.x, 121.5265);
      expect(s.y, 25.0190);
      expect(s.capacity, 100);
      expect(s.cityCode, 'TPE');
      expect(
        source.snapshotUpdatedAt,
        DateTime.parse('2026-08-23T00:00:00.000Z'),
      );
    });

    test('an empty snapshot has no shelters and no crash', () {
      final source = ShelterSnapshotSource.fromCsv('');
      expect(source.shelters, isEmpty);
      expect(source.snapshotUpdatedAt, isNull);
    });

    test('re-applies the county bounds gate and drops a bad row', () {
      // 屏東-area coordinate claimed for 臺北市.
      final bad = _row(sourceId: 'NFA-TPE-bad', lng: '120.913', lat: '22.4797');
      final good = _row(sourceId: 'NFA-TPE-good');
      final source = ShelterSnapshotSource.fromCsv(_csv([bad, good]));
      expect(source.shelters, hasLength(1));
      expect(source.shelters.single.shelterCode, 'NFA-TPE-good');
    });

    test('coverage counts all rows, including dropped ones', () {
      final bad = _row(sourceId: 'NFA-TPE-bad', lng: '120.913', lat: '22.4797');
      final good = _row(sourceId: 'NFA-TPE-good');
      final source = ShelterSnapshotSource.fromCsv(_csv([bad, good]));
      expect(source.coverage.total, 2);
      expect(source.coverage.withCoordinates, 1);
    });

    test('throws a FormatException when required columns are missing', () {
      expect(
        () => ShelterSnapshotSource.fromCsv('a,b,c\n1,2,3\n'),
        throwsFormatException,
      );
    });

    test('countsByCity groups by the city field', () {
      final a = _row(sourceId: 'A', city: '臺北市');
      final b = _row(
        sourceId: 'B',
        city: '高雄市',
        cityCode: 'KHH',
        lng: '120.5',
        lat: '22.6',
      );
      final source = ShelterSnapshotSource.fromCsv(_csv([a, b]));
      expect(source.countsByCity, {'臺北市': 1, '高雄市': 1});
    });
  });

  group('ShelterSnapshotSource.empty', () {
    test('has no shelters', () {
      expect(ShelterSnapshotSource.empty().shelters, isEmpty);
    });
  });
}
