import 'package:server/core/csv/csv_codec.dart';
import 'package:test/test.dart';

void main() {
  group('parseCsv', () {
    test('parses plain rows', () {
      expect(parseCsv('a,b\n1,2\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('handles quoted fields with embedded commas', () {
      // The 消防署 export quotes 適用災害類別 as "水災,震災,土石流".
      expect(parseCsv('a,b\n1,"水災,震災,土石流"\n'), [
        ['a', 'b'],
        ['1', '水災,震災,土石流'],
      ]);
    });

    test('handles doubled quotes and embedded newlines', () {
      expect(parseCsv('a\n"he said ""hi""\nagain"\n'), [
        ['a'],
        ['he said "hi"\nagain'],
      ]);
    });

    test('strips a UTF-8 BOM', () {
      // The 消防署 export ships one; without stripping, the first header name
      // becomes "﻿序號" and every lookup by that key misses.
      expect(parseCsv('\u{FEFF}序號,名稱\n1,甲\n').first, ['序號', '名稱']);
    });

    test('CRLF line endings', () {
      expect(parseCsv('a,b\r\n1,2\r\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('a trailing newline does not create a phantom row', () {
      expect(parseCsv('a\n1\n').length, 2);
    });

    test('empty input', () {
      expect(parseCsv(''), isEmpty);
    });
  });

  group('parseCsvAsMaps', () {
    test('keys rows by header and pads short rows', () {
      final rows = parseCsvAsMaps('a,b,c\n1,2\n');
      expect(rows.single, {'a': '1', 'b': '2', 'c': ''});
    });

    test('header-only input yields no rows', () {
      expect(parseCsvAsMaps('a,b\n'), isEmpty);
    });
  });

  group('encoding', () {
    test('quotes only what needs quoting, so diffs stay readable', () {
      expect(encodeCsvField('plain'), 'plain');
      expect(encodeCsvField('a,b'), '"a,b"');
      expect(encodeCsvField('say "hi"'), '"say ""hi"""');
      expect(encodeCsvRow(['a', 'b,c']), 'a,"b,c"');
    });

    test('round-trips', () {
      const original = ['SA100-0002', '下塔悠 (公7)公園', 'a,b "c"'];
      final parsed = parseCsv(encodeCsvRow(original)).single;
      expect(parsed, original);
    });
  });
}
