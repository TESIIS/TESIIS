// Contract tests for the JSON the Dart backend sends.
//
// Nothing enforces this shape across the two packages, so it is asserted here.

import 'package:flutter_codefest/data/models/shelter.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> serverRow({
  Object? x = 121.5265,
  Object? y = 25.0190,
  Object? area = '209',
  Object? capacity = 52,
}) => {
  'id': 1,
  'importDate': '2025-11-28T14:50:10.208313',
  '收容所編號': 'SA100-0002',
  '名稱': '臺北市立螢橋國民中學',
  '縣市': '臺北市',
  '郵遞區號': '100',
  '鄉鎮': '中正區',
  '村里': '林興里',
  '門牌地址': '汀州路三段四號',
  '類型': '學校',
  '水災': 'Y',
  '震災': 'Y',
  '土石流': 'N',
  '海嘯': 'N',
  '救濟支站': 'Y',
  '無障礙設施': 'Y',
  '室內': 'Y',
  '室外': 'N',
  '服務里別': ['板溪里', '網溪里'],
  '容納人數': capacity,
  '收容所面積(平方公尺)': area,
  '聯絡人姓名': '黃君宜',
  '聯絡人連絡電話': '02-23688667#500',
  '管理人姓名': '陳錦謀',
  '管理人連絡電話': '02-23688667#100',
  '備考': '',
  '座標x': x,
  '座標y': y,
  '座標來源': 'nfa_point_file',
  '座標精度': 'exact',
};

void main() {
  group('Shelter.fromJson', () {
    test('座標y is latitude and 座標x is longitude', () {
      // The axes are swapped relative to the key names. Getting this backwards
      // puts every shelter in the Indian Ocean, and nothing else catches it.
      final shelter = Shelter.fromJson(serverRow());
      expect(shelter.latitude, 25.0190);
      expect(shelter.longitude, 121.5265);
    });

    test('reads the Chinese keys', () {
      final shelter = Shelter.fromJson(serverRow());
      expect(shelter.shelterId, 'SA100-0002');
      expect(shelter.name, '臺北市立螢橋國民中學');
      expect(shelter.district, '中正區');
      expect(shelter.address, '汀州路三段四號');
      expect(shelter.serviceVillages, ['板溪里', '網溪里']);
      expect(shelter.capacity, 52);
    });

    test('hazard values arrive already normalised to Y', () {
      // The server folds 備用 and 老舊聚落 into 'Y'. This side must compare
      // against 'Y' only — reinterpreting the aliases here would double-handle
      // them and disagree with the server's own filtering.
      final shelter = Shelter.fromJson(serverRow());
      expect(shelter.earthquake, 'Y');
      expect(shelter.tsunami, 'N');
    });

    test('a shelter with no coordinate parses instead of throwing', () {
      // ~8% of the dataset. These must stay listable.
      final shelter = Shelter.fromJson(serverRow(x: null, y: null));
      expect(shelter.hasCoordinate, isFalse);
      expect(shelter.latitude, isNull);
      expect(shelter.name, isNotEmpty);
    });

    test('coordinate provenance is carried through', () {
      final shelter = Shelter.fromJson(serverRow());
      expect(shelter.coordinateSource, 'nfa_point_file');
      expect(shelter.isCoordinateExact, isTrue);

      final approx = Shelter.fromJson({...serverRow(), '座標精度': 'approx'});
      expect(approx.isCoordinateExact, isFalse);
    });

    test('null strings degrade to empty rather than crashing', () {
      final row = serverRow()
        ..['備考'] = null
        ..['聯絡人姓名'] = null
        ..['服務里別'] = null;
      final shelter = Shelter.fromJson(row);
      expect(shelter.remarks, '');
      expect(shelter.contactName, '');
      expect(shelter.serviceVillages, isEmpty);
    });

    test('非數值的面積不會爆掉', () {
      // 收容所面積 contains free text for three records
      // ("俟搬遷後重新評估", "改建後重新評估") and one thousands-separated value.
      expect(Shelter.fromJson(serverRow(area: '俟搬遷後重新評估')).area, '俟搬遷後重新評估');
      expect(Shelter.fromJson(serverRow(area: '14,495')).area, '14,495');
      expect(Shelter.fromJson(serverRow(area: null)).area, '');
    });

    test('coordinates sent as strings still parse', () {
      final shelter = Shelter.fromJson(serverRow(x: '121.5265', y: '25.0190'));
      expect(shelter.longitude, 121.5265);
      expect(shelter.latitude, 25.0190);
    });

    test('round-trips through toJson', () {
      final shelter = Shelter.fromJson(serverRow());
      final again = Shelter.fromJson(shelter.toJson());
      expect(again.shelterId, shelter.shelterId);
      expect(again.latitude, shelter.latitude);
      expect(again.longitude, shelter.longitude);
      expect(again.serviceVillages, shelter.serviceVillages);
    });
  });
}
