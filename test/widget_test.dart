// Basic smoke test: the app boots to the idle meter screen with a start button.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meter/main.dart';

void main() {
  testWidgets('App boots to idle meter screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const TaxiMeterApp());
    await tester.pumpAndSettle();

    expect(find.text('운행 시작'), findsOneWidget);
  });
}
