import 'package:flutter_codefest/core/map/basemap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Basemap', () {
    test('NLSC tile URLs use {z}/{y}/{x}, not {z}/{x}/{y}', () {
      // NLSC serves WMTS, whose ResourceURL template is
      // {TileMatrix}/{TileRow}/{TileCol} — z/y/x. Swapping x and y still
      // returns HTTP 200, just a blank ocean tile, so the map silently
      // renders as an empty grid. Measured: correct order 32 KB of map,
      // swapped order 2.4 KB of nothing.
      for (final basemap in Basemap.values) {
        expect(
          basemap.urlTemplate,
          endsWith('/{z}/{y}/{x}'),
          reason: '${basemap.name} has the wrong tile axis order',
        );
      }
    });

    test('no API key or query string is involved', () {
      // The point of switching off Google Maps: a fresh clone must render a
      // map with no account and no key.
      for (final basemap in Basemap.values) {
        expect(basemap.urlTemplate, isNot(contains('?')));
        expect(basemap.urlTemplate.toLowerCase(), isNot(contains('key')));
        expect(basemap.urlTemplate, startsWith('https://wmts.nlsc.gov.tw/'));
      }
    });

    test('attribution is present, as NLSC terms require', () {
      expect(Basemap.attribution, contains('內政部國土測繪中心'));
    });

    test('each layer has a distinct URL', () {
      final urls = Basemap.values.map((b) => b.urlTemplate).toSet();
      expect(urls.length, Basemap.values.length);
    });
  });
}
