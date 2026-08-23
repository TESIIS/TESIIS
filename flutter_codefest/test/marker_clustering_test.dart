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
  });
}
