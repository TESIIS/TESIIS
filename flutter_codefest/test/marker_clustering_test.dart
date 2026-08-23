import 'dart:math' as math;

import 'package:flutter_codefest/domain/marker_clustering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('clusterShelters', () {
    test('empty input produces no clusters', () {
      expect(clusterShelters([], zoom: 12), isEmpty);
    });

    test('a single shelter is its own single-member cluster', () {
      final shelters = [fakeShelter(id: 1, lat: 25.03, lng: 121.5)];
      final clusters = clusterShelters(shelters, zoom: 12);
      expect(clusters, hasLength(1));
      expect(clusters.single.isSingle, isTrue);
      expect(clusters.single.single.id, 1);
    });

    test('two shelters far apart stay separate at a close zoom', () {
      final shelters = [
        fakeShelter(id: 1, lat: 25.03, lng: 121.5),
        fakeShelter(id: 2, lat: 22.6, lng: 120.3), // Kaohsiung, far away
      ];
      final clusters = clusterShelters(shelters, zoom: 12);
      expect(clusters, hasLength(2));
      expect(clusters.every((c) => c.isSingle), isTrue);
    });

    test('two shelters very close together merge at a low zoom', () {
      final shelters = [
        fakeShelter(id: 1, lat: 25.0300, lng: 121.5000),
        fakeShelter(id: 2, lat: 25.0301, lng: 121.5001),
      ];
      // At a country-wide zoom, a few metres of separation is far smaller
      // than one grid cell.
      final clusters = clusterShelters(shelters, zoom: 7);
      expect(clusters, hasLength(1));
      expect(clusters.single.count, 2);
      expect(clusters.single.isSingle, isFalse);
    });

    test('the same two shelters separate again at a close zoom', () {
      final shelters = [
        fakeShelter(id: 1, lat: 25.0300, lng: 121.5000),
        fakeShelter(id: 2, lat: 25.0400, lng: 121.5100),
      ];
      final clusters = clusterShelters(shelters, zoom: 18);
      expect(clusters, hasLength(2));
    });

    test('cluster center is the centroid of its members', () {
      final shelters = [
        fakeShelter(id: 1, lat: 25.0, lng: 121.0),
        fakeShelter(id: 2, lat: 25.002, lng: 121.002),
      ];
      final clusters = clusterShelters(shelters, zoom: 5);
      expect(clusters, hasLength(1));
      expect(clusters.single.center.latitude, closeTo(25.001, 0.0001));
      expect(clusters.single.center.longitude, closeTo(121.001, 0.0001));
    });

    test('minPointsToCluster=1 clusters even a lone pair of neighbours', () {
      final shelters = [
        fakeShelter(id: 1, lat: 25.0300, lng: 121.5000),
        fakeShelter(id: 2, lat: 25.0301, lng: 121.5001),
      ];
      final clusters = clusterShelters(
        shelters,
        zoom: 7,
        minPointsToCluster: 1,
      );
      expect(clusters, hasLength(1));
    });

    test('a large number of co-located shelters all land in one cluster', () {
      final shelters = [
        for (var i = 0; i < 200; i++)
          fakeShelter(id: i, lat: 25.0300, lng: 121.5000),
      ];
      final clusters = clusterShelters(shelters, zoom: 5);
      expect(clusters, hasLength(1));
      expect(clusters.single.count, 200);
    });

    // The grid exists to make clusters a fixed size *on screen*, so the test
    // for it has to be in screen space too. Measuring in degrees alone hides
    // the bug this guards: a degree of latitude and a degree of longitude are
    // different numbers of pixels under Web Mercator, and the conversion
    // between them was inverted, leaving cells ~19% taller than wide at
    // Taiwan's latitudes. `shelter_service.dart` clusters the same points for
    // the map's viewport queries and must stay in step.
    group('cell geometry is square in screen space', () {
      /// Longitude degrees -> pixels at [zoom] (Web Mercator, 256px tiles).
      double lngDegreesToPixels(double degrees, double zoom) =>
          degrees * 256 * math.pow(2, zoom) / 360;

      /// Latitude degrees -> pixels: the same scale divided by cos(latitude),
      /// because a degree of latitude covers more pixels the further north
      /// you are.
      double latDegreesToPixels(double degrees, double zoom, double atLat) =>
          lngDegreesToPixels(degrees, zoom) /
          math.cos(atLat * math.pi / 180).abs();

      /// Cell size in degrees, measured by how many distinct cells a dense
      /// run of points spanning [span] degrees lands in.
      ///
      /// Counting occupied cells rather than bisecting for the point where a
      /// pair splits: that split happens at the next cell *boundary*, whose
      /// distance depends on where the pair sits inside its cell, so it
      /// measures an offset rather than a size.
      double cellDegrees(
        double zoom,
        double atLat, {
        required bool vertical,
        required double span,
      }) {
        const steps = 4000;
        final shelters = [
          for (var i = 0; i < steps; i++)
            fakeShelter(
              id: i,
              lat: vertical ? atLat + span * i / steps : atLat,
              lng: vertical ? 121.0 : 121.0 + span * i / steps,
            ),
        ];
        // Every occupied cell yields exactly one cluster, whether it holds
        // one point or many, so the cluster count is the cell count.
        return span / clusterShelters(shelters, zoom: zoom).length;
      }

      for (final (zoom, lat) in [
        (15.0, 22.0),
        (15.0, 25.1),
        (17.0, 23.5),
        (17.0, 26.4),
      ]) {
        test('zoom $zoom at ${lat}N', () {
          // ~40 cells wide: enough that the off-by-one at the ends is under a
          // percent, small enough that cos(latitude) barely moves across it.
          final span = 40 * 360 / (256 * math.pow(2, zoom)) * 80;
          final widthPx = lngDegreesToPixels(
            cellDegrees(zoom, lat, vertical: false, span: span),
            zoom,
          );
          final heightPx = latDegreesToPixels(
            cellDegrees(zoom, lat, vertical: true, span: span),
            zoom,
            lat,
          );

          expect(widthPx, closeTo(80, 4), reason: 'cellPixels is 80');
          // Before the fix this ratio was 1/cos^2(lat) — 1.16 at 22N rising
          // to 1.25 at 26.4N, every one of them outside this bound.
          expect(
            heightPx / widthPx,
            closeTo(1.0, 0.05),
            reason: 'cells must be square on screen, not $widthPx x $heightPx',
          );
        });
      }
    });
  });
}
