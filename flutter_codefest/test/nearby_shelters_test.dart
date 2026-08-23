import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 臺北車站 — 25.0478 / 121.5170
  const originLat = 25.0478;
  const originLng = 121.5170;

  group('calculateDistance', () {
    test('zero distance for the same point', () {
      expect(
        calculateDistance(originLat, originLng, originLat, originLng),
        closeTo(0, 0.001),
      );
    });

    test('roughly matches a known separation', () {
      // 臺北車站 -> 臺北101 is about 4.6 km.
      final metres = calculateDistance(originLat, originLng, 25.0340, 121.5645);
      expect(metres, closeTo(4800, 600));
    });
  });

  group('estimateWalkingDuration', () {
    test('divides distance by average walking speed', () {
      expect(estimateWalkingDuration(1400).inSeconds, 1000);
    });

    test('zero distance is zero duration', () {
      expect(estimateWalkingDuration(0).inSeconds, 0);
    });
  });

  group('formatWalkingTime', () {
    test('rounds up to whole minutes', () {
      // 1400 m / 1.4 m/s = 1000 s = 16 min 40 s -> ceil to 17 min.
      expect(formatWalkingTime(1400), '約 17 分鐘（步行，直線距離估算）');
    });

    test('never reads as less than 1 minute', () {
      expect(formatWalkingTime(0), '約 1 分鐘（步行，直線距離估算）');
    });
  });
}
