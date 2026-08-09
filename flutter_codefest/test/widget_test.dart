// Smoke test for the app shell.
//
// This file used to be the `flutter create` counter template, asserting on a
// widget tree this app never had — so `flutter test` failed on a clean
// checkout and nobody could tell a real failure from the default one.
//
// It stays deliberately shallow: MapScreen calls the backend and the platform
// location service in initState, neither of which exists in a widget test.

import 'package:flutter/material.dart';
import 'package:flutter_codefest/presentation/pages/user_manual_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('使用手冊頁可以獨立渲染', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: UserManualPage()));
    await tester.pump();

    expect(find.byType(UserManualPage), findsOneWidget);
    // Should render without throwing; a missing asset or a null-unsafe field
    // would surface here.
    expect(tester.takeException(), isNull);
  });
}
