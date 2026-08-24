import 'package:flutter/material.dart';
import 'package:flutter_codefest/data/models/transit_stop.dart';
import 'package:flutter_codefest/data/repositories/transit_repository.dart';
import 'package:flutter_codefest/presentation/widgets/shelter/nearby_transit_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders nothing when TDX is unavailable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTransitSection(
            lat: 25.05,
            lng: 121.5,
            city: '臺北市',
            fetcher: ({required lat, required lng, city}) async =>
                const TransitNearbyResult(available: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('附近交通'), findsNothing);
    expect(find.byType(NearbyTransitSection), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders nothing when there are no nearby stops', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTransitSection(
            lat: 25.05,
            lng: 121.5,
            city: '臺北市',
            fetcher: ({required lat, required lng, city}) async =>
                const TransitNearbyResult(available: true, stops: []),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('附近交通'), findsNothing);
  });

  testWidgets('shows the section and stop names when data is available', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTransitSection(
            lat: 25.05,
            lng: 121.5,
            city: '臺北市',
            fetcher: ({required lat, required lng, city}) async =>
                const TransitNearbyResult(
                  available: true,
                  stops: [
                    TransitStop(
                      id: 'TRA-1',
                      name: '臺北車站',
                      mode: TransitMode.tra,
                      lat: 25.0478,
                      lng: 121.517,
                      distanceMeters: 42,
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('附近交通'), findsOneWidget);
    expect(find.text('臺北車站'), findsOneWidget);
    expect(find.text('42 公尺'), findsOneWidget);
    // A nav button renders for every stop, even without arrivals.
    expect(find.byIcon(Icons.directions), findsOneWidget);
  });

  testWidgets('shows arrival text, including a delay suffix when present', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTransitSection(
            lat: 25.05,
            lng: 121.5,
            city: '臺北市',
            fetcher: ({required lat, required lng, city}) async =>
                const TransitNearbyResult(
                  available: true,
                  stops: [
                    TransitStop(
                      id: 'BUS-1',
                      name: '測試站牌',
                      mode: TransitMode.bus,
                      lat: 25.05,
                      lng: 121.5,
                      distanceMeters: 100,
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
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('299 · 6分'), findsOneWidget);
    expect(find.text('111 · 3分（誤點2分）'), findsOneWidget);
  });

  testWidgets('tapping the nav button does not throw', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NearbyTransitSection(
            lat: 25.05,
            lng: 121.5,
            city: '臺北市',
            fetcher: ({required lat, required lng, city}) async =>
                const TransitNearbyResult(
                  available: true,
                  stops: [
                    TransitStop(
                      id: 'TRA-1',
                      name: '臺北車站',
                      mode: TransitMode.tra,
                      lat: 25.0478,
                      lng: 121.517,
                      distanceMeters: 42,
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.directions));
    await tester.pumpAndSettle();

    // url_launcher has no platform implementation in a widget test, so this
    // is expected to fail and fall into NearbyTransitSection's own
    // catch-and-snackbar path rather than propagate — same depth of
    // coverage the existing shelter "開始導航" button already has (i.e.
    // none deeper than "the tap doesn't crash the app").
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to a differently-keyed instance re-fetches instead of '
      'keeping the previous shelter\'s stale data', (
    WidgetTester tester,
  ) async {
    // Regression test: `_future` is computed once in a `late final` field
    // initializer. Without a key identifying which shelter it's for (see
    // ShelterDetailSheet's `key: ValueKey(shelter.id)`), Flutter reuses
    // the same State object when the parent rebuilds with new lat/lng/city
    // — the initializer never re-runs, so the section keeps showing the
    // previous shelter's transit data forever.
    var callCount = 0;

    Widget buildFor(Key key, String stopName) => MaterialApp(
      home: Scaffold(
        body: NearbyTransitSection(
          key: key,
          lat: 25.05,
          lng: 121.5,
          city: '臺北市',
          fetcher: ({required lat, required lng, city}) async {
            callCount++;
            return TransitNearbyResult(
              available: true,
              stops: [
                TransitStop(
                  id: stopName,
                  name: stopName,
                  mode: TransitMode.bus,
                  lat: 25.05,
                  lng: 121.5,
                  distanceMeters: 10,
                ),
              ],
            );
          },
        ),
      ),
    );

    await tester.pumpWidget(buildFor(const ValueKey('shelter-A'), '站A'));
    await tester.pumpAndSettle();
    expect(find.text('站A'), findsOneWidget);
    expect(callCount, 1);

    await tester.pumpWidget(buildFor(const ValueKey('shelter-B'), '站B'));
    await tester.pumpAndSettle();

    expect(callCount, 2);
    expect(find.text('站B'), findsOneWidget);
    expect(find.text('站A'), findsNothing);
  });
}
