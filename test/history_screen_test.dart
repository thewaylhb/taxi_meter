// Safe-driving trips show up in the trip log without pretending to be a
// 0원 fare.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meter/models/fare_mode.dart';
import 'package:meter/models/trip_record.dart';
import 'package:meter/screens/history_screen.dart';
import 'package:meter/services/trip_repository.dart';

// Kept inside the current month so the monthly stats card sums both trips.
final _now = DateTime.now();

TripRecord _record({
  required FareMode mode,
  required double distanceMeters,
  required int fareWon,
}) {
  final start = _now.subtract(const Duration(hours: 2));
  return TripRecord(
    id: '${mode.name}-$distanceMeters',
    mode: mode,
    startTime: start,
    endTime: start.add(const Duration(minutes: 35)),
    distanceMeters: distanceMeters,
    fareWon: fareWon,
    maxSpeedKmh: 92.4,
  );
}

void main() {
  // main() does this at startup; the date formatter throws without it.
  setUpAll(() => initializeDateFormatting('ko_KR'));

  testWidgets('a safe-driving trip is listed by distance, not 0원',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final repository = TripRepository();
    await repository.add(
      _record(mode: FareMode.safeDriving, distanceMeters: 12345, fareWon: 0),
    );
    await repository.add(
      _record(mode: FareMode.standard, distanceMeters: 8000, fareWon: 18700),
    );

    await tester.pumpWidget(
      MaterialApp(home: HistoryScreen(tripRepository: repository)),
    );
    await tester.pumpAndSettle();

    expect(find.text('0원'), findsNothing);
    expect(find.text('12.35km'), findsOneWidget);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    expect(find.byIcon(Icons.local_taxi), findsOneWidget);
    // The billed trip keeps its fare headline.
    expect(find.text('18,700원'), findsWidgets);

    // ...and its detail screen leads with the distance too.
    await tester.tap(find.text('12.35km'));
    await tester.pumpAndSettle();

    expect(find.text('운행 상세'), findsOneWidget);
    expect(find.text('0원'), findsNothing);
    expect(find.text('12.35km'), findsWidgets);
    expect(find.text('안전 주행 모드'), findsWidgets);
    expect(find.text('92.4km/h'), findsOneWidget);
  });
}
