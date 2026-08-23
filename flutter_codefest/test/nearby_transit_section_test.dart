import 'package:flutter/material.dart';
import 'package:flutter_codefest/data/models/transit_stop.dart';
import 'package:flutter_codefest/data/repositories/transit_repository.dart';
import 'package:flutter_codefest/presentation/widgets/shelter/nearby_transit_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'renders nothing when TDX is unavailable',
    (WidgetTester tester) async {
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
    },
  );

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
  });
}
