import 'package:server/data/datasources/external/tdx_client.dart';
import 'package:server/domain/entities/transit_stop.dart';
import 'package:server/domain/services/transit_service.dart';
import 'package:test/test.dart';

Map<String, dynamic> _stopRow(String uid, {double lat = 25.05, double lng = 121.5}) => {
  'StopUID': uid,
  'StopName': {'Zh_tw': '測試站牌 $uid'},
  'StopPosition': {'PositionLon': lng, 'PositionLat': lat},
};

Map<String, dynamic> _stationRow(String uid, {double lat = 25.05, double lng = 121.5}) => {
  'StationUID': uid,
  'StationName': {'Zh_tw': '測試車站 $uid'},
  'StationPosition': {'PositionLon': lng, 'PositionLat': lat},
};

/// Overrides the three network-hitting methods so the service can be tested
/// without a real TdxClient / http.Client.
class _FakeTdxClient extends TdxClient {
  _FakeTdxClient({this.busResult, this.traResult, this.thsrResult});

  final Object? busResult; // List<dynamic> or an Exception to throw
  final Object? traResult;
  final Object? thsrResult;

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

    test('with an unrecognized city, also skips bus without marking partial', () async {
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
    });

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

    test('one failing source is reported as partial but others still return', () async {
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
    });

    test('all sources failing throws instead of returning an empty result', () async {
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
    });

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
  });
}
