import 'package:flutter/material.dart';
import 'package:flutter_codefest/presentation/widgets/shelter/shelter_detail_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('未定位時仍可以開始導航', (tester) async {
    var navigationCalls = 0;
    final shelter = fakeShelter(id: 1, lat: 25.0, lng: 121.5);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ShelterDetailSheet(
                shelter: shelter,
                currentPosition: null,
                onClose: () {},
                onNavigate: () => navigationCalls++,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.widgetWithText(ElevatedButton, '開始導航'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, '開始導航'));
    expect(navigationCalls, 1);
  });

  testWidgets('缺少座標時可透過地址開始導航', (tester) async {
    final shelter = fakeShelter(
      id: 2,
      address: '公園路 29 號',
      lat: null,
      lng: null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ShelterDetailSheet(
                shelter: shelter,
                currentPosition: null,
                onClose: () {},
                onNavigate: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.widgetWithText(ElevatedButton, '開始導航'), findsOneWidget);
  });
}
