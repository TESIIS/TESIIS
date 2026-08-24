import 'dart:convert';

import 'package:server/core/config/env.dart';
import 'package:server/data/datasources/external/tdx_client.dart';
import 'package:server/domain/entities/transit_stop.dart';
import 'package:server/domain/services/transit_service.dart';
import 'package:server/presentation/controllers/transit_controller.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _StubTransitService extends TransitService {
  _StubTransitService({this.result, this.error}) : super(client: TdxClient());

  final TransitResult? result;
  final Object? error;

  @override
  Future<TransitResult> nearby({
    required double lat,
    required double lng,
    String? city,
    required double radiusMeters,
    required int limit,
  }) async {
    if (error != null) throw error!;
    return result!;
  }
}

Future<Map<String, dynamic>> get(
  TransitController controller,
  String path,
) async {
  final response = await controller.router.call(
    Request('GET', Uri.parse('http://localhost$path')),
  );
  return {
    'status': response.statusCode,
    'body': jsonDecode(await response.readAsString()),
  };
}

void main() {
  setUp(() {
    Env.loadFromLines([
      'TDX_CLIENT_ID=test-id',
      'TDX_CLIENT_SECRET=test-secret',
    ]);
  });

  test('returns 503 available:false when TDX is not configured', () async {
    Env.loadFromLines(const []);
    final controller = TransitController(
      service: _StubTransitService(
        result: const TransitResult(stops: [], partial: false),
      ),
    );

    final res = await get(controller, '/transit/nearby?lat=25.05&lng=121.5');

    expect(res['status'], 503);
    expect(res['body']['available'], isFalse);
  });

  test('returns 400 when lat/lng are missing', () async {
    final controller = TransitController(
      service: _StubTransitService(
        result: const TransitResult(stops: [], partial: false),
      ),
    );

    final res = await get(controller, '/transit/nearby');

    expect(res['status'], 400);
  });

  test('returns the merged stops on success', () async {
    final controller = TransitController(
      service: _StubTransitService(
        result: TransitResult(
          stops: [
            const TransitStop(
              id: 'TRA-1',
              name: '臺北',
              mode: TransitMode.tra,
              lat: 25.05,
              lng: 121.5,
              distanceMeters: 12.4,
            ),
          ],
          partial: true,
        ),
      ),
    );

    final res = await get(
      controller,
      '/transit/nearby?lat=25.05&lng=121.5&city=%E8%87%BA%E5%8C%97%E5%B8%82',
    );

    expect(res['status'], 200);
    expect(res['body']['success'], isTrue);
    expect(res['body']['available'], isTrue);
    expect(res['body']['partial'], isTrue);
    expect(res['body']['total'], 1);
    expect(res['body']['data'][0]['id'], 'TRA-1');
    expect(res['body']['data'][0]['mode'], 'tra');
    expect(res['body']['data'][0]['distanceMeters'], 12);
    expect(res['body']['data'][0]['arrivals'], isEmpty);
  });

  test(
    'serialises arrivals, omitting delayMinutes when null or zero',
    () async {
      final controller = TransitController(
        service: _StubTransitService(
          result: TransitResult(
            stops: [
              const TransitStop(
                id: 'BUS-1',
                name: '測試站牌',
                mode: TransitMode.bus,
                lat: 25.05,
                lng: 121.5,
                distanceMeters: 42,
                arrivals: [
                  TransitArrival(label: '299', minutesUntil: 6),
                  TransitArrival(
                    label: '111',
                    minutesUntil: 3,
                    delayMinutes: 2,
                  ),
                ],
              ),
            ],
            partial: false,
          ),
        ),
      );

      final res = await get(controller, '/transit/nearby?lat=25.05&lng=121.5');

      final arrivals = res['body']['data'][0]['arrivals'] as List<dynamic>;
      expect(arrivals, hasLength(2));
      expect(arrivals[0], {'label': '299', 'minutes': 6});
      expect(arrivals[1], {'label': '111', 'minutes': 3, 'delayMinutes': 2});
    },
  );

  test('a service failure degrades to 503 rather than 500', () async {
    final controller = TransitController(
      service: _StubTransitService(error: Exception('TDX down')),
    );

    final res = await get(controller, '/transit/nearby?lat=25.05&lng=121.5');

    expect(res['status'], 503);
    expect(res['body']['available'], isFalse);
  });
}
