import 'package:server/data/datasources/external/tdx_client.dart';
import 'package:server/domain/entities/transit_stop.dart';
import 'package:server/domain/services/transit_service.dart';
import 'package:test/test.dart';

Map<String, dynamic> _stopRow(
  String uid, {
  double lat = 25.05,
  double lng = 121.5,
  String? name,
}) => {
  'StopUID': uid,
  'StopName': {'Zh_tw': name ?? '測試站牌 $uid'},
  'StopPosition': {'PositionLon': lng, 'PositionLat': lat},
};

Map<String, dynamic> _stationRow(
  String uid, {
  double lat = 25.05,
  double lng = 121.5,
  String? stationId,
}) => {
  'StationUID': uid,
  'StationName': {'Zh_tw': '測試車站 $uid'},
  'StationPosition': {'PositionLon': lng, 'PositionLat': lat},
  if (stationId != null) 'StationID': stationId,
};

Map<String, dynamic> _busEtaRow({
  required String stopUid,
  required String route,
  required int estimateSeconds,
}) => {
  'StopUID': stopUid,
  'RouteName': {'Zh_tw': route},
  'EstimateTime': estimateSeconds,
};

Map<String, dynamic> _traLiveBoardRow({
  required int minutesFromNow,
  String destination = '新竹',
}) {
  final departure = DateTime.now().toUtc().add(
    Duration(hours: 8, minutes: minutesFromNow),
  );
  String two(int n) => n.toString().padLeft(2, '0');
  return {
    'TrainTypeName': {'Zh_tw': '區間'},
    'EndingStationName': {'Zh_tw': destination},
    'ScheduledDepartureTime':
        '${two(departure.hour)}:${two(departure.minute)}:${two(departure.second)}',
  };
}

/// Overrides the network-hitting methods so the service can be tested
/// without a real TdxClient / http.Client.
class _FakeTdxClient extends TdxClient {
  _FakeTdxClient({
    this.busResult,
    this.traResult,
    this.thsrResult,
    this.busEtaResult,
    this.traLiveBoardResults = const {},
  });

  final Object? busResult; // List<dynamic> or an Exception to throw
  final Object? traResult;
  final Object? thsrResult;
  final Object? busEtaResult; // List<dynamic> or an Exception to throw

  /// Keyed by stationId — each entry is a `List<dynamic>` or an Exception.
  final Map<String, Object> traLiveBoardResults;

  @override
  Future<List<dynamic>> nearbyBusStops({
    required String tdxCity,
    required double lat,
    required double lng,
    required double radiusMeters,
    int top = 30,
  }) async {
    if (busResult is Exception) throw busResult as Exception;
    return (busResult as List<dynamic>?) ?? const [];
  }

  @override
  Future<List<dynamic>> nearbyTraStations({
    required double lat,
    required double lng,
    required double radiusMeters,
    int top = 10,
  }) async {
    if (traResult is Exception) throw traResult as Exception;
    return (traResult as List<dynamic>?) ?? const [];
  }

  @override
  Future<List<dynamic>> nearbyThsrStations({
    required double lat,
    required double lng,
    required double radiusMeters,
    int top = 10,
  }) async {
    if (thsrResult is Exception) throw thsrResult as Exception;
    return (thsrResult as List<dynamic>?) ?? const [];
  }

  @override
  Future<List<dynamic>> busEstimatedArrivals({
    required String tdxCity,
    required List<String> stopUids,
    int top = 100,
  }) async {
    if (busEtaResult is Exception) throw busEtaResult as Exception;
    return (busEtaResult as List<dynamic>?) ?? const [];
  }

  @override
  Future<List<dynamic>> traLiveBoard({
    required String stationId,
    int top = 20,
  }) async {
    final result = traLiveBoardResults[stationId];
    if (result is Exception) throw result;
    return (result as List<dynamic>?) ?? const [];
  }
}

void main() {
  group('TransitService.nearby', () {
    test('without a city, skips bus and is not partial', () async {
      final service = TransitService(
        client: _FakeTdxClient(
          traResult: [_stationRow('TRA-1')],
          thsrResult: const [],
        ),
      );

      final result = await service.nearby(
        lat: 25.05,
        lng: 121.5,
        radiusMeters: 500,
        limit: 10,
      );

      expect(result.partial, isFalse);
      expect(result.stops, hasLength(1));
      expect(result.stops.single.mode, TransitMode.tra);
    });

    test(
      'with an unrecognized city, also skips bus without marking partial',
      () async {
        final service = TransitService(
          client: _FakeTdxClient(traResult: const [], thsrResult: const []),
        );

        final result = await service.nearby(
          lat: 25.05,
          lng: 121.5,
          city: 'Not A Real City',
          radiusMeters: 500,
          limit: 10,
        );

        expect(result.partial, isFalse);
        expect(result.stops, isEmpty);
      },
    );

    test('merges bus, TRA and THSR results sorted by distance', () async {
      final service = TransitService(
        client: _FakeTdxClient(
          busResult: [_stopRow('BUS-1', lat: 25.0501, lng: 121.5001)],
          traResult: [_stationRow('TRA-1', lat: 25.05, lng: 121.5)],
          thsrResult: [_stationRow('THSR-1', lat: 25.06, lng: 121.5)],
        ),
      );

      final result = await service.nearby(
        lat: 25.05,
        lng: 121.5,
        city: '臺北市',
        radiusMeters: 500,
        limit: 10,
      );

      expect(result.partial, isFalse);
      expect(result.stops.map((s) => s.id), ['TRA-1', 'BUS-1', 'THSR-1']);
    });

    test(
      'one failing source is reported as partial but others still return',
      () async {
        final service = TransitService(
          client: _FakeTdxClient(
            busResult: [_stopRow('BUS-1')],
            traResult: [_stationRow('TRA-1')],
            thsrResult: Exception('THSR down'),
          ),
        );

        final result = await service.nearby(
          lat: 25.05,
          lng: 121.5,
          city: '臺北市',
          radiusMeters: 500,
          limit: 10,
        );

        expect(result.partial, isTrue);
        expect(result.stops.map((s) => s.id), containsAll(['BUS-1', 'TRA-1']));
      },
    );

    test(
      'all sources failing throws instead of returning an empty result',
      () async {
        final service = TransitService(
          client: _FakeTdxClient(
            traResult: Exception('down'),
            thsrResult: Exception('down'),
          ),
        );

        await expectLater(
          service.nearby(lat: 25.05, lng: 121.5, radiusMeters: 500, limit: 10),
          throwsException,
        );
      },
    );

    test('limit truncates the merged, sorted result', () async {
      final service = TransitService(
        client: _FakeTdxClient(
          traResult: [
            _stationRow('TRA-1', lat: 25.0501, lng: 121.5),
            _stationRow('TRA-2', lat: 25.0502, lng: 121.5),
          ],
          thsrResult: [_stationRow('THSR-1', lat: 25.06, lng: 121.5)],
        ),
      );

      final result = await service.nearby(
        lat: 25.05,
        lng: 121.5,
        radiusMeters: 500,
        limit: 2,
      );

      expect(result.stops, hasLength(2));
      expect(result.stops.map((s) => s.id), ['TRA-1', 'TRA-2']);
    });

    test('attaches real-time arrivals to matching bus and TRA stops', () async {
      final service = TransitService(
        client: _FakeTdxClient(
          busResult: [_stopRow('BUS-1')],
          traResult: [_stationRow('TRA-1', stationId: '1000')],
          thsrResult: const [],
          busEtaResult: [
            _busEtaRow(stopUid: 'BUS-1', route: '299', estimateSeconds: 120),
          ],
          traLiveBoardResults: {
            '1000': [_traLiveBoardRow(minutesFromNow: 5)],
          },
        ),
      );

      final result = await service.nearby(
        lat: 25.05,
        lng: 121.5,
        city: '臺北市',
        radiusMeters: 500,
        limit: 10,
      );

      final bus = result.stops.firstWhere((s) => s.id == 'BUS-1');
      expect(bus.arrivals.single.label, '299');

      final tra = result.stops.firstWhere((s) => s.id == 'TRA-1');
      expect(tra.arrivals.single.label, '區間 開往新竹');
    });

    test('a bus stop merged from several StopUIDs (same physical pole) gets '
        'arrivals combined across all of them', () async {
      final service = TransitService(
        client: _FakeTdxClient(
          busResult: [
            _stopRow('TPE1', name: '臺北車站(忠孝)'),
            _stopRow('TPE2', name: '臺北車站(忠孝)'),
            _stopRow('TPE3', name: '臺北車站(忠孝)'),
          ],
          traResult: const [],
          thsrResult: const [],
          busEtaResult: [
            _busEtaRow(stopUid: 'TPE1', route: '299', estimateSeconds: 600),
            _busEtaRow(stopUid: 'TPE2', route: '111', estimateSeconds: 120),
            // Same route as TPE1's, but sooner via a different StopUID —
            // the soonest instance should win, not both.
            _busEtaRow(stopUid: 'TPE3', route: '299', estimateSeconds: 300),
          ],
        ),
      );

      final result = await service.nearby(
        lat: 25.05,
        lng: 121.5,
        city: '臺北市',
        radiusMeters: 500,
        limit: 10,
      );

      expect(result.stops, hasLength(1));
      final stop = result.stops.single;
      expect(stop.arrivals.map((a) => a.label), ['111', '299']);
      expect(stop.arrivals.map((a) => a.minutesUntil), [2, 5]);
    });

    test('a failing arrivals fetch leaves that stop with no arrivals, '
        'without affecting the stop list or partial', () async {
      final service = TransitService(
        client: _FakeTdxClient(
          busResult: [_stopRow('BUS-1')],
          traResult: [_stationRow('TRA-1', stationId: '1000')],
          thsrResult: const [],
          busEtaResult: Exception('bus ETA down'),
          traLiveBoardResults: {'1000': Exception('TRA live board down')},
        ),
      );

      final result = await service.nearby(
        lat: 25.05,
        lng: 121.5,
        city: '臺北市',
        radiusMeters: 500,
        limit: 10,
      );

      expect(result.partial, isFalse);
      expect(result.stops.map((s) => s.id), containsAll(['BUS-1', 'TRA-1']));
      for (final s in result.stops) {
        expect(s.arrivals, isEmpty);
      }
    });

    test(
      'a TRA station with no stationId never gets an arrivals lookup',
      () async {
        // _stationRow with no `stationId:` — mirrors a real row TDX sent
        // without a StationID, which the mapper already treats as absent.
        final service = TransitService(
          client: _FakeTdxClient(
            traResult: [_stationRow('TRA-1')],
            thsrResult: const [],
          ),
        );

        final result = await service.nearby(
          lat: 25.05,
          lng: 121.5,
          radiusMeters: 500,
          limit: 10,
        );

        expect(result.stops.single.arrivals, isEmpty);
      },
    );
  });
}
