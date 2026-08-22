import 'package:flutter_codefest/core/utils/nearby_shelters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  // 臺北車站 ≈ 25.0478 / 121.5170
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

  group('locatableShelters', () {
    test('drops shelters with no coordinate', () {
      // About 8% of the dataset: parks and intersections whose 門牌地址 is a
      // description rather than an address.
      final shelters = [
        fakeShelter(id: 1, lat: 25.05, lng: 121.52),
        fakeShelter(id: 2),
        fakeShelter(id: 3, lat: 0.0, lng: 0.0),
      ];
      expect(locatableShelters(shelters).map((s) => s.id), [1]);
    });
  });

  group('sortedByDistance', () {
    test('orders nearest first', () {
      final shelters = [
        fakeShelter(id: 3, lat: 25.0800, lng: 121.5600),
        fakeShelter(id: 1, lat: 25.0480, lng: 121.5175),
        fakeShelter(id: 2, lat: 25.0600, lng: 121.5300),
      ];
      expect(
        sortedByDistance(shelters, originLat, originLng).map((s) => s.id),
        [1, 2, 3],
      );
    });

    test('does not truncate', () {
      // This is the regression that matters most. sortedByDistance and
      // nearestShelters used to be one function whose `limit` defaulted to 5,
      // and the filter and search paths called it purely to sort — capping
      // every filtered and searched result at five entries regardless of how
      // many actually matched.
      final shelters = [
        for (var i = 0; i < 40; i++)
          fakeShelter(id: i, lat: 25.05 + i * 0.001, lng: 121.52),
      ];
      expect(sortedByDistance(shelters, originLat, originLng).length, 40);
    });

    test('empty input is fine', () {
      expect(sortedByDistance(const [], originLat, originLng), isEmpty);
    });
  });

  group('nearestShelters', () {
    test('caps at the requested limit', () {
      final shelters = [
        for (var i = 0; i < 20; i++)
          fakeShelter(id: i, lat: 25.05 + i * 0.001, lng: 121.52),
      ];
      expect(nearestShelters(shelters, originLat, originLng).length, 5);
      expect(
        nearestShelters(shelters, originLat, originLng, limit: 3).length,
        3,
      );
    });

    test('returns fewer than the limit when that is all there is', () {
      final shelters = [fakeShelter(id: 1, lat: 25.05, lng: 121.52)];
      expect(nearestShelters(shelters, originLat, originLng).length, 1);
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
