import 'package:flutter_codefest/data/datasources/shelter_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ShelterCache', () {
    test('round-trips a saved shelter list', () async {
      final shelters = [
        fakeShelter(id: 1, lat: 25.02, lng: 121.51),
        fakeShelter(id: 2, lat: null, lng: null),
      ];

      await ShelterCache.save(shelters);
      final cached = await ShelterCache.load();

      expect(cached, isNotNull);
      expect(cached!.shelters.map((s) => s.id), [1, 2]);
      expect(cached.shelters.first.latitude, 25.02);
      expect(cached.cachedAt, isNotNull);
    });

    test('returns null when nothing has been cached', () async {
      expect(await ShelterCache.load(), isNull);
    });

    test('returns null instead of throwing on corrupt cached JSON', () async {
      SharedPreferences.setMockInitialValues({
        'cached_shelters_v1': 'not valid json',
        'cached_shelters_at_v1': DateTime.now().toIso8601String(),
      });

      expect(await ShelterCache.load(), isNull);
    });
  });
}
