import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:server/data/datasources/external/taipei_shelter_resource.dart';
import 'package:server/data/models/shelter_model.dart';
import 'package:test/test.dart';

void main() {
  test(
    'rejects the malformed Taipei API response before building coordinates',
    () {
      expect(
        () => validateTaipeiShelterRows([
          {'_id': 1, 'pk\u0003\u0004': ''},
        ]),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('reads the register worksheet from ODS and maps new headers', () {
    const content = '''
<?xml version="1.0" encoding="UTF-8"?>
<office:document-content
    xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
    xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
    xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">
  <office:body><office:spreadsheet>
    <table:table table:name="清冊">
      <table:table-row>
        <table:table-cell><text:p>收容所編號</text:p></table:table-cell>
        <table:table-cell><text:p>名稱(學校機關全銜)</text:p></table:table-cell>
        <table:table-cell><text:p>鄉鎮</text:p></table:table-cell>
        <table:table-cell><text:p>門牌地址</text:p></table:table-cell>
        <table:table-cell><text:p>救濟站</text:p></table:table-cell>
        <table:table-cell><text:p>收容所面積(平方公尺)</text:p></table:table-cell>
      </table:table-row>
      <table:table-row>
        <table:table-cell><text:p>SA116-0001</text:p></table:table-cell>
        <table:table-cell><text:p>測試避難所</text:p></table:table-cell>
        <table:table-cell><text:p>中正區</text:p></table:table-cell>
        <table:table-cell><text:p>公園路29號</text:p></table:table-cell>
        <table:table-cell><text:p>是</text:p></table:table-cell>
        <table:table-cell><text:p>126</text:p></table:table-cell>
      </table:table-row>
      <table:table-row>
        <table:table-cell table:number-columns-repeated="6" />
        <table:table-cell><text:p>合計</text:p></table:table-cell>
      </table:table-row>
      <table:table-row table:number-rows-repeated="1047558">
        <table:table-cell table:number-columns-repeated="64" />
      </table:table-row>
    </table:table>
    <table:table table:name="工作表1">
      <table:table-row><table:table-cell><text:p>不是清冊</text:p></table:table-cell></table:table-row>
    </table:table>
  </office:spreadsheet></office:body>
</office:document-content>
''';
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          'mimetype',
          'application/vnd.oasis.opendocument.spreadsheet',
        ),
      )
      ..add(ArchiveFile.bytes('content.xml', utf8.encode(content)));
    final rows = decodeTaipeiShelterResource(ZipEncoder().encode(archive));

    expect(rows, hasLength(1));
    expect(rows.single['收容所編號'], 'SA116-0001');
    expect(rows.single['名稱'], '測試避難所');
    expect(rows.single['救濟支站'], '是');
    expect(rows.single['收容所面積（平方公尺）'], '126');

    final model = ShelterModel.fromJson(rows.single);
    expect(model.name, '測試避難所');
    expect(model.relief, '是');
    expect(model.area, 126);
  });

  test('accepts the original CSV header while rejecting duplicate codes', () {
    const csv =
        '收容所編號,名稱,鄉鎮,門牌地址\n'
        'SA100-0001,舊版避難所,中正區,公園路29號\n';
    final rows = decodeTaipeiShelterResource(utf8.encode(csv));
    expect(rows.single['名稱'], '舊版避難所');
    expect(
      () => validateTaipeiShelterRows([rows.single, rows.single]),
      throwsA(isA<FormatException>()),
    );
  });
}
