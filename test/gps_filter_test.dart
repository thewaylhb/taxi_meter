import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:taximeter/services/gps_filter.dart';

Position _pos({
  required double lat,
  required double lon,
  required DateTime time,
  double accuracy = 5,
}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: time,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  final base = DateTime(2026, 7, 4, 12, 0, 0);

  group('GpsFilter', () {
    test('rejects low-accuracy fixes', () {
      final filter = GpsFilter();
      final fix =
          filter.process(_pos(lat: 37.5, lon: 127.0, time: base, accuracy: 30));
      expect(fix.accepted, isFalse);
      expect(fix.rejectReason, 'GPS 정확도 낮음');
    });

    test('accepts the first fix as the anchor with no distance', () {
      final filter = GpsFilter();
      final fix = filter.process(_pos(lat: 37.5, lon: 127.0, time: base));
      expect(fix.accepted, isTrue);
      expect(fix.distanceDeltaMeters, 0);
    });

    test(
        'treats small movement while stationary as jitter '
        '(no distance, time still accrues)', () {
      final filter = GpsFilter();
      filter.process(_pos(lat: 37.5, lon: 127.0, time: base));

      // ~2m north - within GPS noise, below the jitter threshold.
      final jitterLat = 37.5 + (2 / 111320);
      final fix = filter.process(_pos(
        lat: jitterLat,
        lon: 127.0,
        time: base.add(const Duration(seconds: 2)),
      ));

      expect(fix.accepted, isTrue);
      expect(fix.distanceDeltaMeters, 0);
      expect(fix.timeDelta, const Duration(seconds: 2));
    });

    test('registers real movement beyond the jitter threshold', () {
      final filter = GpsFilter();
      filter.process(_pos(lat: 37.5, lon: 127.0, time: base));

      const movedLat = 37.5009; // roughly 100m north
      final expectedDistance =
          Geolocator.distanceBetween(37.5, 127.0, movedLat, 127.0);
      final fix = filter.process(_pos(
        lat: movedLat,
        lon: 127.0,
        time: base.add(const Duration(seconds: 10)),
      ));

      expect(fix.accepted, isTrue);
      expect(fix.distanceDeltaMeters, closeTo(expectedDistance, 0.01));
      expect(fix.speedMps, closeTo(expectedDistance / 10, 0.01));
    });

    test('rejects an implausible speed jump and keeps the old anchor', () {
      final filter = GpsFilter();
      filter.process(_pos(lat: 37.5, lon: 127.0, time: base));

      // ~5km away in 1 second: far above any plausible taxi speed.
      final jumpFix = filter.process(_pos(
        lat: 37.545,
        lon: 127.0,
        time: base.add(const Duration(seconds: 1)),
      ));
      expect(jumpFix.accepted, isFalse);
      expect(jumpFix.rejectReason, 'GPS 튐 감지');

      // A fix close to the ORIGINAL anchor should still read as plausible
      // movement from the pre-jump position, proving the anchor and clock
      // weren't corrupted by the rejected jump.
      const movedLat = 37.5009;
      final expectedDistance =
          Geolocator.distanceBetween(37.5, 127.0, movedLat, 127.0);
      final followUp = filter.process(_pos(
        lat: movedLat,
        lon: 127.0,
        time: base.add(const Duration(seconds: 11)),
      ));

      expect(followUp.accepted, isTrue);
      expect(followUp.distanceDeltaMeters, closeTo(expectedDistance, 0.01));
    });

    test('caps the billable time delta after a long gap between fixes', () {
      final filter = GpsFilter();
      filter.process(_pos(lat: 37.5, lon: 127.0, time: base));

      // A minute later, still essentially stationary (jitter). The real gap
      // shouldn't be billed in full as slow time.
      final jitterLat = 37.5 + (2 / 111320);
      final fix = filter.process(_pos(
        lat: jitterLat,
        lon: 127.0,
        time: base.add(const Duration(minutes: 1)),
      ));

      expect(fix.accepted, isTrue);
      expect(fix.timeDelta, GpsFilter.maxBillableGap);
    });
  });
}
