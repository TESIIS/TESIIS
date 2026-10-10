import 'package:server/data/mappers/cap_alert_mapper.dart';
import 'package:test/test.dart';

import 'support/alert_fixtures.dart';

void main() {
  final source = Uri.parse('https://alerts.example/Capstorage/test.cap');
  test(
    'accepts namespace prefixes and prefers all traditional-Chinese info bands',
    () {
      final xml = capXml(
        infos:
            capInfo(language: 'en-US', headline: 'English') +
            capInfo(headline: '嚴重', severity: 'Severe') +
            capInfo(area: '高雄市苓雅區', headline: '普通', severity: 'Moderate'),
      );
      final message = parseTestCap(
        xml
            .replaceFirst('<alert xmlns=', '<cap:alert xmlns:cap=')
            .replaceFirst('</alert>', '</cap:alert>'),
      );
      expect(message.infos.map((i) => i.headline), ['嚴重', '普通']);
      expect(message.infos.last.regions.single.city, '高雄市');
      expect(message.infos.last.severity, 'Moderate');
    },
  );
  test(
    'Actual/Public only: exercises, tests and restricted documents do not publish',
    () {
      for (final status in ['Test', 'Exercise', 'Draft', 'System']) {
        expect(CapAlertMapper.parseCap(capXml(status: status), source), isNull);
      }
      expect(CapAlertMapper.parseCap(capXml(scope: 'Private'), source), isNull);
    },
  );
  test(
    'timezone conversion and Taiwan AM/PM correctly handle midnight and noon',
    () {
      expect(
        CapAlertMapper.capDate('2026-10-10T16:00:00+08:00'),
        DateTime.utc(2026, 10, 10, 8),
      );
      expect(
        CapAlertMapper.feedDate('2026/10/10 上午 12:30:00'),
        DateTime.utc(2026, 10, 9, 16, 30),
      );
      expect(
        CapAlertMapper.feedDate('2026/10/10 下午 12:30:00'),
        DateTime.utc(2026, 10, 10, 4, 30),
      );
      for (final raw in [
        '2026-10-10T16:00:00',
        '2026-02-30T16:00:00Z',
        '2026-10-10T25:00:00Z',
      ]) {
        expect(CapAlertMapper.capDate(raw), isNull);
      }
    },
  );
  test('missing expiry is unknown; malformed expiry is a partial document', () {
    expect(
      parseTestCap(
        capXml(infos: capInfo(expires: null)),
      ).infos.single.temporalState(alertNow),
      'unknown',
    );
    final bad = parseTestCap(capXml(infos: capInfo(expires: 'not a date')));
    expect(bad.infos, isEmpty);
    expect(bad.invalidInfoCount, greaterThan(0));
  });
  test('county summaries are narrowed by explicit township parameters', () {
    final info = parseTestCap(
      capXml(
        infos: capInfo(
          area: '臺北市(共2個鄉鎮)，新北市(共1個鄉鎮)',
          parameters:
              '<parameter><valueName>townships</valueName><value>臺北市中正區,臺北市北投區,新北市汐止區</value></parameter>',
        ),
      ),
    ).infos.single;
    expect(
      info.regions.map((r) => r.key),
      containsAll(['臺北市|中正區', '臺北市|北投區', '新北市|汐止區']),
    );
    expect(info.regions.where((r) => r.township == null), isEmpty);
  });
  test('multi-town area descriptions keep the city context', () {
    final info = parseTestCap(
      capXml(infos: capInfo(area: '台北市士林區、北投區')),
    ).infos.single;
    expect(info.regions.map((r) => r.key), ['臺北市|士林區', '臺北市|北投區']);
  });
  test(
    'geographic-only areas remain explicitly unmatched; unsafe web links drop',
    () {
      final info = parseTestCap(
        capXml(
          infos: capInfo(area: '沿海警戒區域', web: 'javascript:alert(1)'),
        ),
      ).infos.single;
      expect(info.regions, isEmpty);
      expect(info.web, isNull);
    },
  );
  test('Atom links must remain under same-origin Capstorage', () {
    final feed = CapAlertMapper.parseFeed(
      atomFeed(
        atomEntry() +
            atomEntry(id: 'B', url: 'https://other.example/Capstorage/B.cap') +
            atomEntry(id: 'C', url: 'file:///etc/passwd') +
            atomEntry(id: 'D', url: 'https://alerts.example/private.cap'),
      ),
      Uri.parse('https://alerts.example/feed'),
    );
    expect(feed.entries.single.id, 'A');
    expect(feed.invalidEntries, 3);
  });
  test('an HTML error or DTD cannot become an empty successful feed', () {
    expect(
      () => CapAlertMapper.parseFeed(
        '<html>unavailable</html>',
        Uri.parse('https://alerts.example/feed'),
      ),
      throwsFormatException,
    );
    expect(
      () => CapAlertMapper.parseCap('<!DOCTYPE alert>${capXml()}', source),
      throwsFormatException,
    );
  });
  test('cancellation without info retains reference identity', () {
    final message = parseTestCap(
      capXml(
        type: 'Cancel',
        infos: '',
        references: '$alertSender,A,$alertSent',
      ),
    );
    expect(message.infos, isEmpty);
    expect(message.references.single.identifier, 'A');
    expect(message.references.single.sender, alertSender);
  });
}
