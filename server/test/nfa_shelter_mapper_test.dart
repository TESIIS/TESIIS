import 'package:server/data/mappers/nfa_shelter_mapper.dart';
import 'package:test/test.dart';

Map<String, String> _row({
  String region = '臺北市中正區',
  String village = '林興里',
  String address = '汀州路三段四號',
  String lng = '121.5265',
  String lat = '25.0190',
  String name = '臺北市立螢橋國民中學',
  String serviceVillages = '林興里、板溪里',
  String capacity = '100',
  String hazards = '水災,震災',
  String managerName = '陳大文',
  String managerPhone = '02-11111111',
  String indoor = '是',
  String outdoor = '否',
  String accessible = '是',
}) => {
  '縣市及鄉鎮市區': region,
  '村里': village,
  '避難收容處所地址': address,
  '經度': lng,
  '緯度': lat,
  '避難收容處所名稱': name,
  '預計收容村里': serviceVillages,
  '預計收容人數': capacity,
  '適用災害類別': hazards,
  '管理人姓名': managerName,
  '管理人電話': managerPhone,
  '室內': indoor,
  '室外': outdoor,
  '適合避難弱者安置': accessible,
};

void main() {
  group('splitRegion', () {
    test('splits a normal region string', () {
      expect(NfaShelterMapper.splitRegion('臺東縣金峰鄉'), ('臺東縣', '金峰鄉'));
    });

    test('a region with no township does not throw', () {
      expect(NfaShelterMapper.splitRegion('新竹縣'), ('新竹縣', ''));
    });

    test('handles multi-character township names', () {
      expect(NfaShelterMapper.splitRegion('嘉義縣阿里山鄉'), ('嘉義縣', '阿里山鄉'));
    });
  });

  group('parseHazards', () {
    test('marks listed hazards Y and everything else N', () {
      final out = NfaShelterMapper.parseHazards('水災,震災,土石流');
      expect(out, {'水災': 'Y', '震災': 'Y', '土石流': 'Y', '海嘯': 'N', '核子事故': 'N'});
    });

    test('empty column means every hazard is N', () {
      final out = NfaShelterMapper.parseHazards('');
      expect(out.values.every((v) => v == 'N'), isTrue);
    });

    test('handles the full-width separator too', () {
      final out = NfaShelterMapper.parseHazards('水災、核子事故');
      expect(out['水災'], 'Y');
      expect(out['核子事故'], 'Y');
      expect(out['震災'], 'N');
    });
  });

  group('sourceId', () {
    test('is deterministic for the same key', () {
      final a = NfaShelterMapper.sourceId(
        city: '臺北市',
        township: '中正區',
        village: '林興里',
        address: '汀州路三段四號',
        name: '臺北市立螢橋國民中學',
      );
      final b = NfaShelterMapper.sourceId(
        city: '臺北市',
        township: '中正區',
        village: '林興里',
        address: '汀州路三段四號',
        name: '臺北市立螢橋國民中學',
      );
      expect(a, b);
    });

    test('differs for a different key', () {
      final a = NfaShelterMapper.sourceId(
        city: '臺北市',
        township: '中正區',
        village: '林興里',
        address: '汀州路三段四號',
        name: 'A',
      );
      final b = NfaShelterMapper.sourceId(
        city: '臺北市',
        township: '中正區',
        village: '林興里',
        address: '汀州路三段四號',
        name: 'B',
      );
      expect(a, isNot(b));
    });

    test('the ordinal suffix disambiguates otherwise-identical rows', () {
      final first = NfaShelterMapper.sourceId(
        city: '臺北市',
        township: '中正區',
        village: '林興里',
        address: '同一個地址',
        name: '同一個名稱',
      );
      final second = NfaShelterMapper.sourceId(
        city: '臺北市',
        township: '中正區',
        village: '林興里',
        address: '同一個地址',
        name: '同一個名稱',
        ordinal: 1,
      );
      expect(first, isNot(second));
    });

    test('is always a clean hex string, never a negative sign', () {
      // Regression: Dart's native int has no bignum promotion, so a hash
      // whose 64-bit pattern has the sign bit set used to print with a
      // leading '-' (e.g. "NFA-CHA--1186...") instead of clean hex.
      for (var i = 0; i < 200; i++) {
        final id = NfaShelterMapper.sourceId(
          city: '彰化縣',
          township: '埤頭鄉',
          village: '合興村',
          address: '文鄉路135號',
          name: 'facility-$i',
        );
        expect(id, matches(RegExp(r'^NFA-[A-Z]+-[0-9a-f]{16}$')));
      }
    });

    test('carries the ISO city code as a prefix', () {
      final id = NfaShelterMapper.sourceId(
        city: '臺北市',
        township: '中正區',
        village: '林興里',
        address: '汀州路三段四號',
        name: '臺北市立螢橋國民中學',
      );
      expect(id, startsWith('NFA-TPE-'));
    });
  });

  group('assignOrdinals', () {
    test('gives every unique row ordinal 0', () {
      final rows = [_row(name: 'A'), _row(name: 'B'), _row(name: 'C')];
      expect(NfaShelterMapper.assignOrdinals(rows), [0, 0, 0]);
    });

    test('increments for repeated (region,village,address,name) tuples', () {
      final rows = [_row(name: 'dup'), _row(name: 'dup'), _row(name: 'dup')];
      expect(NfaShelterMapper.assignOrdinals(rows), [0, 1, 2]);
    });

    test('is stable across independent duplicate groups', () {
      final rows = [_row(name: 'dup'), _row(name: 'other'), _row(name: 'dup')];
      expect(NfaShelterMapper.assignOrdinals(rows), [0, 0, 1]);
    });
  });

  group('toShelter', () {
    test('maps a well-formed row', () {
      final result = NfaShelterMapper.toShelter(_row(), rowIndex: 1);
      expect(result.rejectReason, isNull);
      final s = result.shelter!;
      expect(s.city, '臺北市');
      expect(s.township, '中正區');
      expect(s.village, '林興里');
      expect(s.name, '臺北市立螢橋國民中學');
      expect(s.x, 121.5265);
      expect(s.y, 25.0190);
      expect(s.coordinateSource, 'nfa_point_file');
      expect(s.coordinateConfidence, 'exact');
      expect(s.cityCode, 'TPE');
      expect(s.capacity, 100);
      expect(s.flood, 'Y');
      expect(s.quake, 'Y');
      expect(s.landslide, 'N');
      expect(s.indoor, '是');
      expect(s.outdoor, '否');
    });

    test('rejects a coordinate outside the county box', () {
      // 屏東-area coordinate claimed for 臺北市 — the known 北市大附小 mis-geocode.
      final result = NfaShelterMapper.toShelter(
        _row(lng: '120.913', lat: '22.4797'),
        rowIndex: 1,
      );
      expect(result.shelter, isNull);
      expect(result.rejectReason, 'out_of_county_bounds');
    });

    test('rejects a row with no parseable coordinate', () {
      final result = NfaShelterMapper.toShelter(
        _row(lng: '', lat: ''),
        rowIndex: 1,
      );
      expect(result.shelter, isNull);
      expect(result.rejectReason, 'no_coordinate');
    });

    test('rejects a row whose region does not match a known county', () {
      final result = NfaShelterMapper.toShelter(
        _row(region: '不存在的地方'),
        rowIndex: 1,
      );
      expect(result.shelter, isNull);
      expect(result.rejectReason, 'unknown_county');
    });

    test('a row with no township still maps (does not throw)', () {
      final result = NfaShelterMapper.toShelter(
        _row(
          region: '新竹縣',
          village: '',
          address: '',
          lng: '121.0',
          lat: '24.5',
        ),
        rowIndex: 1,
      );
      expect(result.shelter, isNotNull);
      expect(result.shelter!.township, '');
    });
  });
}
