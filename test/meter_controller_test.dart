// Trip-logging behavior around safe-driving mode, which has no settlement
// step of its own, plus the snapshot round-trip that keeps an interrupted
// trip's stats.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meter/models/active_trip_snapshot.dart';
import 'package:meter/models/fare_mode.dart';
import 'package:meter/services/active_trip_repository.dart';
import 'package:meter/services/meter_controller.dart';
import 'package:meter/services/trip_repository.dart';

ActiveTripSnapshot _snapshot(FareMode mode) => ActiveTripSnapshot(
      mode: mode,
      startTime: DateTime(2026, 8, 13, 9, 30),
      lastUpdateTime: DateTime(2026, 8, 13, 10, 5),
      distanceMeters: 12345,
      fareWon: mode == FareMode.safeDriving ? 0 : 18700,
      maxSpeedKmh: 92.4,
    );

void main() {
  late TripRepository tripRepository;
  late ActiveTripRepository activeTripRepository;
  late MeterController controller;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tripRepository = TripRepository();
    activeTripRepository = ActiveTripRepository();
    controller = MeterController(
      tripRepository: tripRepository,
      activeTripRepository: activeTripRepository,
    );
  });

  test('an interrupted safe-driving trip is logged instead of awaiting '
      'a settlement it has no fare for', () async {
    final snapshot = _snapshot(FareMode.safeDriving);
    await activeTripRepository.save(snapshot);

    await controller.recoverIfAny();

    expect(controller.state, MeterState.idle);
    final records = await tripRepository.loadAll();
    expect(records, hasLength(1));
    expect(records.single.mode, FareMode.safeDriving);
    expect(records.single.fareWon, 0);
    expect(records.single.distanceMeters, snapshot.distanceMeters);
    expect(records.single.startTime, snapshot.startTime);
    expect(records.single.endTime, snapshot.lastUpdateTime);
    expect(records.single.maxSpeedKmh, 92.4);
    expect(await activeTripRepository.load(), isNull);
  });

  test('recovering the same safe-driving trip twice logs it once', () async {
    await activeTripRepository.save(_snapshot(FareMode.safeDriving));
    await controller.recoverIfAny();
    await activeTripRepository.save(_snapshot(FareMode.safeDriving));
    await controller.recoverIfAny();

    expect(await tripRepository.loadAll(), hasLength(1));
  });

  test('a billed trip still surfaces for settlement, keeping its max speed',
      () async {
    await activeTripRepository.save(_snapshot(FareMode.standard));

    await controller.recoverIfAny();

    expect(controller.state, MeterState.finished);
    expect(controller.recoveredFromCrash, isTrue);
    expect(controller.fareWon, 18700);
    expect(controller.maxSpeedKmh, closeTo(92.4, 0.001));
    expect(await tripRepository.loadAll(), isEmpty);

    await controller.completeSettlement();

    final records = await tripRepository.loadAll();
    expect(records, hasLength(1));
    expect(records.single.maxSpeedKmh, closeTo(92.4, 0.001));
    expect(controller.state, MeterState.idle);
  });

  test('snapshot JSON carries max speed and tolerates older snapshots', () {
    final json = _snapshot(FareMode.safeDriving).toJson();
    expect(ActiveTripSnapshot.fromJson(json).maxSpeedKmh, 92.4);

    json.remove('maxSpeedKmh');
    final legacy = ActiveTripSnapshot.fromJson(json);
    expect(legacy.maxSpeedKmh, isNull);
    expect(legacy.mode, FareMode.safeDriving);
  });
}
