import 'package:server/data/mappers/tdx_transit_mapper.dart';
import 'package:test/test.dart';

Map<String, dynamic> _busEtaRow({
  required String stopUid,
  required String route,
  required int estimateSeconds,
}) => {
  'StopUID': stopUid,
  'RouteName': {'Zh_tw': route},
  'EstimateTime': estimateSeconds,
};

String _hms(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';

Map<String, dynamic> _traRow({
  required String trainType,
  required String destination,
  required String scheduledDepartureTime,
  int? delayMinutes,
}) => {
  'TrainTypeName': {'Zh_tw': trainType},
  'EndingStationName': {'Zh_tw': destination},
  'ScheduledDepartureTime': scheduledDepartureTime,
  if (delayMinutes != null) 'DelayTime': delayMinutes,
};

Map<String, dynamic> _busStopRow(
  String uid, {
  String name = '測試站牌',
  double lat = 25.05,
  double lng = 121.5,
}) => {
  'StopUID': uid,
  'StopName': {'Zh_tw': name},
  'StopPosition': {'PositionLon': lng, 'PositionLat': lat},
};

void main() {
  group('TdxTransitMapper.busArrivalsByStop', () {
    test('groups by stop and sorts soonest first', () {
      final result = TdxTransitMapper.busArrivalsByStop([
        _busEtaRow(stopUid: 'A', route: '299', estimateSeconds: 600),
        _busEtaRow(stopUid: 'A', route: '111', estimateSeconds: 120),
        _busEtaRow(stopUid: 'B', route: '5', estimateSeconds: 60),
      ]);

      expect(result.keys, containsAll(['A', 'B']));
      expect(result['A']!.map((a) => a.label), ['111', '299']);
      expect(result['A']!.map((a) => a.minutesUntil), [2, 10]);
      expect(result['B']!.single.label, '5');
    });

    test('caps at 3 per stop', () {
      final result = TdxTransitMapper.busArrivalsByStop([
        for (var i = 0; i < 5; i++)
          _busEtaRow(stopUid: 'A', route: 'R$i', estimateSeconds: i * 60),
      ]);

      expect(result['A'], hasLength(3));
      expect(result['A']!.map((a) => a.label), ['R0', 'R1', 'R2']);
    });

    test('skips rows with no estimate or a negative one', () {
      final result = TdxTransitMapper.busArrivalsByStop([
        {
          'StopUID': 'A',
          'RouteName': {'Zh_tw': '299'},
          'EstimateTime': null,
        },
        _busEtaRow(stopUid: 'A', route: '111', estimateSeconds: -30),
        _busEtaRow(stopUid: 'A', route: '5', estimateSeconds: 60),
      ]);

      expect(result['A']!.map((a) => a.label), ['5']);
    });
  });

  group('TdxTransitMapper.traArrivals', () {
    test('computes minutesUntil relative to Taipei now', () {
      final taipeiNow = DateTime.now().toUtc().add(const Duration(hours: 8));
      final departure = taipeiNow.add(const Duration(minutes: 12));

      final result = TdxTransitMapper.traArrivals([
        _traRow(
          trainType: '區間',
          destination: '新竹',
          scheduledDepartureTime: _hms(departure),
        ),
      ]);

      expect(result, hasLength(1));
      expect(result.single.label, '區間 開往新竹');
      // Allow ±1 minute of slack for the test's own execution time.
      expect(result.single.minutesUntil, inInclusiveRange(11, 13));
      expect(result.single.delayMinutes, isNull);
    });

    test('carries a positive delay but omits a zero one', () {
      final taipeiNow = DateTime.now().toUtc().add(const Duration(hours: 8));
      final departure = taipeiNow.add(const Duration(minutes: 5));

      final delayed = TdxTransitMapper.traArrivals([
        _traRow(
          trainType: '自強',
          destination: '高雄',
          scheduledDepartureTime: _hms(departure),
          delayMinutes: 3,
        ),
      ]);
      expect(delayed.single.delayMinutes, 3);

      final onTime = TdxTransitMapper.traArrivals([
        _traRow(
          trainType: '自強',
          destination: '高雄',
          scheduledDepartureTime: _hms(departure),
          delayMinutes: 0,
        ),
      ]);
      expect(onTime.single.delayMinutes, isNull);
    });

    test('drops entries far outside the near-term window', () {
      final taipeiNow = DateTime.now().toUtc().add(const Duration(hours: 8));
      final farFuture = taipeiNow.add(const Duration(hours: 4));

      final result = TdxTransitMapper.traArrivals([
        _traRow(
          trainType: '區間',
          destination: '新竹',
          scheduledDepartureTime: _hms(farFuture),
        ),
      ]);

      expect(result, isEmpty);
    });

    test('sorts soonest first and caps at 3', () {
      final taipeiNow = DateTime.now().toUtc().add(const Duration(hours: 8));

      final result = TdxTransitMapper.traArrivals([
        for (final minutes in [40, 10, 25, 5, 15])
          _traRow(
            trainType: '區間',
            destination: '新竹',
            scheduledDepartureTime: _hms(
              taipeiNow.add(Duration(minutes: minutes)),
            ),
          ),
      ]);

      expect(result, hasLength(3));
      final minutes = result.map((a) => a.minutesUntil).toList();
      for (final (i, expected) in [5, 10, 15].indexed) {
        expect(
          minutes[i],
          inInclusiveRange(expected - 1, expected + 1),
          reason: 'entry $i',
        );
      }
    });
  });

  group('TdxTransitMapper.fromBusStops', () {
    test(
      'merges same-name-and-position rows into one stop, keeping every StopUID',
      () {
        final result = TdxTransitMapper.fromBusStops(
          [
            _busStopRow('TPE1', name: '臺北車站(忠孝)'),
            _busStopRow('TPE2', name: '臺北車站(忠孝)'),
            _busStopRow('TPE3', name: '臺北車站(忠孝)'),
          ],
          originLat: 25.05,
          originLng: 121.5,
        );

        expect(result, hasLength(1));
        expect(result.single.name, '臺北車站(忠孝)');
        expect(result.single.busStopUids, ['TPE1', 'TPE2', 'TPE3']);
      },
    );

    test(
      'merges same-named rows a few meters apart, not just exact matches',
      () {
        // Real TDX data isn't always byte-identical across route records for
        // what is obviously the same physical stop — this is the case that
        // slipped through an exact (name, lat, lng) match.
        final result = TdxTransitMapper.fromBusStops(
          [
            _busStopRow('TPE1', name: '中清雅潭路口', lat: 25.05000, lng: 121.50000),
            _busStopRow('TPE2', name: '中清雅潭路口', lat: 25.05003, lng: 121.50002),
          ],
          originLat: 25.05,
          originLng: 121.5,
        );

        expect(result, hasLength(1));
        expect(result.single.busStopUids, ['TPE1', 'TPE2']);
      },
    );

    test('keeps different-position stops separate even with the same name', () {
      final result = TdxTransitMapper.fromBusStops(
        [
          _busStopRow('TPE1', name: '中山市場', lat: 25.05, lng: 121.5),
          _busStopRow('TPE2', name: '中山市場', lat: 25.06, lng: 121.5),
        ],
        originLat: 25.05,
        originLng: 121.5,
      );

      expect(result, hasLength(2));
    });

    test('an unmerged stop still carries its own id as busStopUids', () {
      final result = TdxTransitMapper.fromBusStops(
        [_busStopRow('TPE1', name: '中山市場')],
        originLat: 25.05,
        originLng: 121.5,
      );

      expect(result.single.busStopUids, ['TPE1']);
    });
  });
}
