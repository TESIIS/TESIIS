import 'package:flutter_codefest/domain/navigation_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('buildNavigationUri', () {
    test('routes from the current position when both are known', () {
      final shelter = fakeShelter(id: 1, lat: 25.02, lng: 121.51);
      final from = fakePosition(lat: 25.0, lng: 121.5);

      final uri = buildNavigationUri(shelter, from: from);

      expect(uri.toString(), contains('origin=25.0,121.5'));
      expect(uri.toString(), contains('destination=25.02,121.51'));
      expect(uri.toString(), contains('travelmode=walking'));
    });

    test('falls back to a plain search when there is no current position', () {
      final shelter = fakeShelter(id: 1, lat: 25.02, lng: 121.51);

      final uri = buildNavigationUri(shelter);

      expect(uri.toString(), contains('maps/search'));
      expect(uri.toString(), contains('query=25.02,121.51'));
    });

    test(
      'falls back to an address search when the shelter has no coordinate',
      () {
        final shelter = fakeShelter(
          id: 1,
          district: '中正區',
          address: '公園路29號',
          lat: null,
          lng: null,
        );

        final uri = buildNavigationUri(
          shelter,
          from: fakePosition(lat: 25.0, lng: 121.5),
        );

        expect(uri.toString(), contains('maps/search'));
        expect(uri.queryParameters['query'], contains('中正區'));
        expect(uri.queryParameters['query'], contains('公園路29號'));
      },
    );
  });
}
