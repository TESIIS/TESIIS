import 'dart:async';
import 'dart:convert';

import 'package:server/data/datasources/external/ncdr_alert_source.dart';
import 'package:server/domain/entities/disaster_alert.dart';
import 'package:server/domain/services/alert_service.dart';
import 'package:server/presentation/controllers/alert_controller.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/alert_fixtures.dart';

class _Source implements AlertSource {
  _Source(this.load);
  Future<AlertBatch> Function() load;
  int calls = 0;
  @override
  Future<AlertBatch> fetch() {
    calls++;
    return load();
  }
}

void main() {
  test(
    'update and cancellation follow references transitively, regardless of expiry',
    () async {
      final first = parseTestCap(capXml());
      final update = parseTestCap(
        capXml(
          id: 'B',
          type: 'Update',
          sent: '2026-10-10T08:05:00Z',
          references: '$alertSender,A,$alertSent',
        ),
      );
      final cancel = parseTestCap(
        capXml(
          id: 'C',
          type: 'Cancel',
          sent: '2026-10-10T08:10:00Z',
          references: '$alertSender,B,2026-10-10T08:05:00Z',
          infos: '',
        ),
      );
      final service = AlertService(
        source: _Source(() async => alertBatch([cancel, first, update])),
        now: () => alertNow,
      );
      expect((await service.query())['data'], isEmpty);
      final history = await service.query(
        city: '臺北市',
        township: '中正區',
        includeHistory: true,
      );
      expect(
        (history['data'] as List).map((r) => r['state']),
        everyElement('cancelled'),
      );
      expect((history['data'] as List).first['headline'], contains('解除'));
    },
  );
  test(
    'same event/name is not deduplicated and another sender cannot share an identity',
    () async {
      final first = parseTestCap(capXml());
      final other = parseTestCap(capXml(sender: 'other@example.gov.tw'));
      final update = parseTestCap(
        capXml(
          id: 'B',
          type: 'Update',
          references: '$alertSender,A,$alertSent',
        ),
      );
      final service = AlertService(
        source: _Source(() async => alertBatch([first, other, update])),
        now: () => alertNow,
      );
      final data = (await service.query())['data'] as List;
      expect(data, hasLength(2));
      expect(data.map((e) => e['messageId']), containsAll(['A', 'B']));
    },
  );
  test('future controls do not remove the current message early', () async {
    final service = AlertService(
      source: _Source(
        () async => alertBatch([
          parseTestCap(capXml()),
          parseTestCap(
            capXml(
              id: 'cancel',
              type: 'Cancel',
              sent: '2026-10-11T08:00:00Z',
              references: '$alertSender,A,$alertSent',
              infos: '',
            ),
          ),
        ]),
      ),
      now: () => alertNow,
    );
    expect((await service.query())['total'], 1);
  });
  test(
    'expires at the exact boundary even while serving a cached batch',
    () async {
      var now = alertNow;
      final source = _Source(
        () async => alertBatch([
          parseTestCap(capXml(infos: capInfo(expires: '2026-10-10T08:31:00Z'))),
        ]),
      );
      final service = AlertService(source: source, now: () => now);
      expect((await service.query())['total'], 1);
      now = now.add(const Duration(minutes: 1));
      expect((await service.query())['total'], 0);
      expect(source.calls, 1);
    },
  );
  test(
    'outage is stale with original fetched time; retry is backed off',
    () async {
      var now = alertNow;
      final source = _Source(() async => alertBatch([parseTestCap(capXml())]));
      final service = AlertService(source: source, now: () => now);
      await service.query();
      source.load = () async => throw StateError('network down');
      now = now.add(const Duration(minutes: 3));
      final stale = await service.query();
      expect(stale['freshness'], 'stale');
      expect(stale['fetchedAt'], alertNow.toIso8601String());
      await service.query();
      expect(source.calls, 2);
    },
  );
  test('concurrent queries share one refresh', () async {
    final gate = Completer<AlertBatch>();
    final source = _Source(() => gate.future);
    final service = AlertService(source: source, now: () => alertNow);
    final queries = [service.query(), service.query(city: '臺北市')];
    gate.complete(alertBatch([]));
    await Future.wait(queries);
    expect(source.calls, 1);
  });
  test(
    'unknown geography is counted, and county-only matches are marked broad',
    () async {
      final source = _Source(
        () async => alertBatch([
          parseTestCap(
            capXml(
              infos: capInfo(area: '臺北市') + capInfo(area: '海域'),
            ),
          ),
        ]),
      );
      final data = await AlertService(
        source: source,
        now: () => alertNow,
      ).query(city: '臺北市', township: '中正區');
      expect(data['unknownRegionCount'], 1);
      expect((data['data'] as List).single['regionMatch'], 'city');
    },
  );
  test(
    'API distinguishes an unavailable source from a successful empty list',
    () async {
      final controller = AlertController(
        service: AlertService(
          source: _Source(() async => throw StateError('private detail')),
          now: () => alertNow,
        ),
      );
      final response = await controller.router.call(
        Request('GET', Uri.parse('http://localhost/alerts')),
      );
      expect(response.statusCode, 503);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['available'], false);
      expect(body.toString(), isNot(contains('private detail')));
    },
  );
  test(
    'API validates scope and returns no-store with freshness metadata',
    () async {
      final controller = AlertController(
        service: AlertService(
          source: _Source(() async => alertBatch([])),
          now: () => alertNow,
        ),
      );
      for (final query in [
        'city=不存在',
        'township=中正區',
        'history=yes',
        'limit=0',
        'lat=25',
      ]) {
        final response = await controller.router.call(
          Request('GET', Uri.parse('http://localhost/alerts?$query')),
        );
        expect(response.statusCode, 400);
      }
      final response = await controller.router.call(
        Request('GET', Uri.parse('http://localhost/alerts?city=台北市')),
      );
      expect(response.statusCode, 200);
      expect(response.headers['cache-control'], 'no-store');
      expect(jsonDecode(await response.readAsString())['freshness'], 'fresh');
    },
  );
}
