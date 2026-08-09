// Regression tests for the upstream-data quirks collected in
// lib/domain/entities/shelter_fields.dart.
//
// Every case here corresponds to a real value observed in dataset
// 4c92dbd4-d259-495a-8390-52628119a4dd. If one of these starts failing after a
// refactor, the API has begun disagreeing with the data it serves.

import 'package:server/domain/entities/shelter_fields.dart';
import 'package:test/test.dart';

void main() {
  group('HazardFlag', () {
    test('備用 and 老舊聚落 count as yes', () {
      // 震災 is 備用 for 239 of 401 records and 土石流 is 老舊聚落 for 5.
      // Treating them as "not yes" would hide most of the dataset.
      expect(HazardFlag.isYes('備用'), isTrue);
      expect(HazardFlag.isYes('老舊聚落'), isTrue);
    });

    test('literal yes/no spellings', () {
      for (final yes in ['Y', 'y', 'YES', 'true', '是']) {
        expect(HazardFlag.isYes(yes), isTrue, reason: yes);
      }
      for (final no in ['N', 'n', 'NO', 'false', '否']) {
        expect(HazardFlag.isNo(no), isTrue, reason: no);
      }
    });

    test('empty and null are neither yes nor no', () {
      for (final blank in [null, '', '   ']) {
        expect(HazardFlag.isYes(blank), isFalse);
        expect(HazardFlag.isNo(blank), isFalse);
      }
    });

    test('normalizeForOutput agrees with isYes', () {
      // The API would contradict its own filters if these ever diverged:
      // a value reported as 'Y' that isYes rejects is unfilterable.
      for (final raw in ['Y', '備用', '老舊聚落', 'N', '', 'whatever']) {
        final normalized = HazardFlag.normalizeForOutput(raw);
        expect(
          normalized == 'Y',
          HazardFlag.isYes(raw),
          reason: 'raw=$raw normalized=$normalized',
        );
      }
      expect(HazardFlag.normalizeForOutput(null), isNull);
      expect(HazardFlag.normalizeForOutput('N'), 'N');
    });

    test('海嘯 is only reachable through the aliases', () {
      // 海嘯 is N(391) 備用(10) across all 401 records — there is no literal
      // 'Y'. Drop the alias handling and ?tsunami=Y silently returns zero.
      expect(HazardFlag.isYes('備用'), isTrue);
      expect(HazardFlag.normalizeForOutput('備用'), 'Y');
    });

    test('an explicit alias query does not match a plain Y', () {
      expect(HazardFlag.isAliasRequest('備用'), isTrue);
      expect(HazardFlag.isAliasRequest('Y'), isFalse);
      expect(HazardFlag.matchesAlias('備用', '備用'), isTrue);
      expect(HazardFlag.matchesAlias('Y', '備用'), isFalse);
    });
  });

  group('ShelterText.splitVillages', () {
    test('splits on the documented separator', () {
      expect(ShelterText.splitVillages('板溪里、網溪里、螢圃里'), ['板溪里', '網溪里', '螢圃里']);
    });

    test('handles the four records that a naive [、，,] split mangles', () {
      // _id 67: trailing 。
      expect(ShelterText.splitVillages('文昌里、中庄里。'), ['文昌里', '中庄里']);
      // _id 246: embedded newline instead of a separator
      expect(ShelterText.splitVillages('前港里\n義信里'), ['前港里', '義信里']);
      // _id 273: a free-text note glued onto a village name
      expect(ShelterText.splitVillages('豐年里\n(僅寒暑假可安置)'), ['豐年里']);
      // full-width comma
      expect(ShelterText.splitVillages('甲里，乙里'), ['甲里', '乙里']);
    });

    test('null and empty produce an empty list', () {
      expect(ShelterText.splitVillages(null), isEmpty);
      expect(ShelterText.splitVillages('  '), isEmpty);
    });
  });

  group('ShelterText.namesEqual', () {
    test('folds 臺 and 台', () {
      // All 401 records spell it 臺北市; clients routinely send 台北市.
      expect(ShelterText.namesEqual('臺北市', '台北市'), isTrue);
      expect(ShelterText.namesEqual(' 臺北市 ', '台北市'), isTrue);
      expect(ShelterText.namesEqual('臺北市', '新北市'), isFalse);
    });
  });

  group('ShelterNumber', () {
    test('strips the thousands separator', () {
      // 收容所面積（平方公尺） contains "14,495".
      expect(ShelterNumber.parseDouble('14,495'), 14495.0);
      expect(ShelterNumber.parseInt('1,581'), 1581);
    });

    test('free-text values degrade instead of throwing', () {
      // 容納人數 contains "俟搬遷後重新評估"; 收容所面積 also has "改建後重新評估".
      expect(ShelterNumber.parseDouble('俟搬遷後重新評估'), isNull);
      expect(ShelterNumber.parseInt('改建後重新評估'), 0);
      expect(ShelterNumber.parseDouble(null), isNull);
      expect(ShelterNumber.parseInt(null), 0);
    });

    test('accepts numbers as well as strings', () {
      expect(ShelterNumber.parseDouble(12.5), 12.5);
      expect(ShelterNumber.parseInt(7), 7);
    });
  });

  group('ShelterAddress.normalize', () {
    test('converts Chinese numerals in 段/號/巷/弄', () {
      // Upstream writes 汀州路三段四號 while the coordinate sources write
      // 汀州路3段4號. Without this the join silently drops the record.
      expect(
        ShelterAddress.normalize('汀州路三段四號', township: '中正區'),
        ShelterAddress.normalize('汀州路3段4號', township: '中正區'),
      );
      expect(ShelterAddress.parseCjkNumber('三'), 3);
      expect(ShelterAddress.parseCjkNumber('十'), 10);
      expect(ShelterAddress.parseCjkNumber('十六'), 16);
      expect(ShelterAddress.parseCjkNumber('二十'), 20);
      expect(ShelterAddress.parseCjkNumber('九十九'), 99);
      expect(ShelterAddress.parseCjkNumber('不是數字'), isNull);
    });

    test('a bare address and a fully-qualified one agree', () {
      // Dataset 4c92dbd4 writes 門牌地址 both ways.
      expect(
        ShelterAddress.normalize('公園路29號', township: '中正區'),
        ShelterAddress.normalize('臺北市中正區公園路29號'),
      );
    });

    test('keeps the district so street numbers cannot collide', () {
      expect(
        ShelterAddress.normalize('公園路29號', township: '中正區'),
        isNot(ShelterAddress.normalize('公園路29號', township: '大同區')),
      );
      expect(
        ShelterAddress.normalize('公園路29號', township: '中正區'),
        startsWith('中正區'),
      );
    });

    test('folds 臺/台 and full-width characters', () {
      expect(
        ShelterAddress.normalize('臺北市中正區公園路２９號'),
        ShelterAddress.normalize('台北市中正區公園路29號'),
      );
    });

    test('drops floor designators', () {
      // 捷運站 addresses carry B1; libraries carry 3樓/4、5樓.
      final base = ShelterAddress.normalize('中正區公園路52號');
      expect(ShelterAddress.normalize('中正區公園路52號B1'), base);
      expect(ShelterAddress.normalize('中正區公園路52號3樓'), base);
      expect(ShelterAddress.normalize('中正區公園路52號地下2樓'), base);
      expect(ShelterAddress.normalize('中正區公園路52號4F'), base);
    });

    test('normalises 之 to a hyphen without eating the number', () {
      // 民生西路198之20號 must not collapse to 19820號.
      final normalized = ShelterAddress.normalize(
        '民生西路198之20號',
        township: '大同區',
      );
      expect(normalized, contains('198-20'));
      expect(
        normalized,
        ShelterAddress.normalize('民生西路198-20號', township: '大同區'),
      );
    });

    test('empty input yields an empty key rather than a district-only key', () {
      expect(ShelterAddress.normalize(null, township: '中正區'), '');
      expect(ShelterAddress.normalize('   ', township: '中正區'), '');
    });
  });
}
