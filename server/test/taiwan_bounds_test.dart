import 'package:server/core/geo/taiwan_bounds.dart';
import 'package:test/test.dart';

void main() {
  group('TaiwanBounds', () {
    test('has all 22 counties', () {
      expect(TaiwanBounds.counties.length, 22);
      expect(TaiwanBounds.byCounty.length, 22);
      for (final county in TaiwanBounds.counties) {
        expect(
          TaiwanBounds.byCounty.containsKey(county),
          isTrue,
          reason: county,
        );
      }
    });

    test('accepts a known-good Taipei point', () {
      expect(TaiwanBounds.containsForCounty('台北市', 121.5265, 25.0190), isTrue);
    });

    test('rejects a point in the wrong county', () {
      // The known 北市大附小 mis-geocode, actually in 屏東.
      expect(TaiwanBounds.containsForCounty('台北市', 120.913, 22.4797), isFalse);
    });

    test('unknown county returns false rather than throwing', () {
      expect(TaiwanBounds.containsForCounty('火星特別行政區', 121.5, 25.0), isFalse);
    });

    group('金門縣 — two disjoint boxes for the 烏坵鄉 exclave', () {
      test('accepts the main island', () {
        expect(TaiwanBounds.containsForCounty('金門縣', 118.32, 24.44), isTrue);
      });

      test('accepts 烏坵鄉, ~130km away', () {
        expect(TaiwanBounds.containsForCounty('金門縣', 119.47, 24.98), isTrue);
      });

      test('rejects a point between the two', () {
        expect(TaiwanBounds.containsForCounty('金門縣', 118.9, 24.7), isFalse);
      });
    });

    test('連江縣 (馬祖) spans 東引 to 莒光 as one box', () {
      expect(TaiwanBounds.containsForCounty('連江縣', 120.4885, 26.3684), isTrue);
      expect(TaiwanBounds.containsForCounty('連江縣', 119.9254, 25.9567), isTrue);
    });

    test('nationwide envelope covers every county box', () {
      for (final boxes in TaiwanBounds.byCounty.values) {
        for (final box in boxes) {
          expect(TaiwanBounds.nationwide.minLng <= box.minLng, isTrue);
          expect(TaiwanBounds.nationwide.maxLng >= box.maxLng, isTrue);
          expect(TaiwanBounds.nationwide.minLat <= box.minLat, isTrue);
          expect(TaiwanBounds.nationwide.maxLat >= box.maxLat, isTrue);
        }
      }
    });
  });
}
