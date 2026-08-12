// Settings screen keyboard/save-button behavior: the 저장 button must stay
// tappable while the keyboard is up, and tapping empty space must drop focus
// without blocking text entry or button taps.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meter/models/fare_mode.dart';
import 'package:meter/screens/settings_screen.dart';
import 'package:meter/services/settings_controller.dart';

final _efficiencyField = find.widgetWithText(TextField, '연비 (km/L)');

Future<SettingsController> _pumpCarpoolSettings(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final controller = SettingsController();
  await controller.load();
  await controller.setMode(FareMode.carpool);
  await tester.pumpWidget(
    MaterialApp(home: SettingsScreen(settingsController: controller)),
  );
  await tester.pumpAndSettle();
  // `.first` is the ListView's own Scrollable; text fields bring their own.
  await tester.scrollUntilVisible(
    _efficiencyField,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return controller;
}

bool _fieldHasFocus(WidgetTester tester) {
  final editable = tester.widget<EditableText>(
    find.descendant(of: _efficiencyField, matching: find.byType(EditableText)),
  );
  return editable.focusNode.hasFocus;
}

Finder _saveButtonFor(Finder field) => find.descendant(
      of: find.ancestor(of: field, matching: find.byType(Row)).first,
      matching: find.widgetWithText(FilledButton, '저장'),
    );

void main() {
  testWidgets('저장 button sits in the same row as its field and saves',
      (WidgetTester tester) async {
    final controller = await _pumpCarpoolSettings(tester);

    // Same row as the field, so it scrolls above the keyboard with it.
    final saveButton = _saveButtonFor(_efficiencyField);
    expect(saveButton, findsOneWidget);
    expect(
      tester.getTopLeft(saveButton).dx >
          tester.getTopRight(_efficiencyField).dx - 1,
      isTrue,
      reason: '저장 button should sit to the right of the input field',
    );

    await tester.enterText(_efficiencyField, '12.5');
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(controller.settings.fuelEfficiencyKmPerLiter, 12.5);
    expect(find.text('설정이 저장되었습니다.'), findsOneWidget);
  });

  testWidgets('tapping empty space drops focus but input still works',
      (WidgetTester tester) async {
    await _pumpCarpoolSettings(tester);

    await tester.tap(_efficiencyField);
    await tester.pump();
    expect(_fieldHasFocus(tester), isTrue);

    // A plain label is not interactive, so the tap reaches the dismiss handler.
    await tester.tap(find.text('차량 연비 설정'));
    await tester.pumpAndSettle();
    expect(_fieldHasFocus(tester), isFalse);

    // Focus can be regained: the dismiss handler does not swallow taps.
    await tester.tap(_efficiencyField);
    await tester.pump();
    expect(_fieldHasFocus(tester), isTrue);

    await tester.enterText(_efficiencyField, '9.9');
    await tester.pump();
    expect(find.widgetWithText(TextField, '9.9'), findsOneWidget);
  });

  testWidgets('field and 저장 button fit a phone-width screen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpCarpoolSettings(tester);

    // A RenderFlex overflow here would fail the test on its own.
    expect(_saveButtonFor(_efficiencyField), findsOneWidget);
    expect(tester.getSize(_efficiencyField).width > 100, isTrue);
  });

  testWidgets('radio selection still works with the tap-to-dismiss wrapper',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController();
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settingsController: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(FareMode.carpool.label));
    await tester.pumpAndSettle();

    expect(controller.settings.mode, FareMode.carpool);
  });
}
