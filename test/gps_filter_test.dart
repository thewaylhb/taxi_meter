import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:meter/services/gps_filter.dart';

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

    test(
        'reports the real speed of a crawl that needs several fixes to clear '
        'the jitter threshold', () {
      final filter = GpsFilter();
      const metersPerDegLat = 111320.0;
      // 3 m/s (10.8 km/h) due north, one fix per second. Each single fix
      // moves only 3m, so the anchor can't advance every second - it takes
      // two fixes to clear the 5m jitter threshold.
      const trueSpeedMps = 3.0;
      var lat = 37.5;
      filter.process(_pos(lat: lat, lon: 127.0, time: base));

      final acceptedSpeeds = <double>[];
      for (var i = 1; i <= 6; i++) {
        lat += trueSpeedMps / metersPerDegLat;
        final fix = filter.process(_pos(
          lat: lat,
          lon: 127.0,
          time: base.add(Duration(seconds: i)),
        ));
        if (fix.distanceDeltaMeters > 0) acceptedSpeeds.add(fix.speedMps);
      }

      // Regression: measuring anchor-relative distance against the previous
      // *fix* time reported 6 m/s here - double the truth - which pushed the
      // interval above the 15.72 km/h slow threshold and silently dropped
      // its time fare.
      expect(acceptedSpeeds, isNotEmpty);
      for (final speed in acceptedSpeeds) {
        expect(speed, closeTo(trueSpeedMps, 0.05));
      }
    });

    test('a crawl below the slow-speed threshold stays below it', () {
      final filter = GpsFilter();
      const metersPerDegLat = 111320.0;
      const thresholdMps = 15.72 * 1000 / 3600;
      // 14 km/h: genuinely slow, so every interval must read as slow.
      const trueSpeedMps = 14 * 1000 / 3600;
      var lat = 37.5;
      filter.process(_pos(lat: lat, lon: 127.0, time: base));

      for (var i = 1; i <= 8; i++) {
        lat += trueSpeedMps / metersPerDegLat;
        final fix = filter.process(_pos(
          lat: lat,
          lon: 127.0,
          time: base.add(Duration(seconds: i)),
        ));
        expect(fix.accepted, isTrue);
        expect(fix.speedMps, lessThan(thresholdMps));
      }
    });

    test('re-anchors after a long stop so pulling away reads a real speed',
        () {
      final filter = GpsFilter();
      const metersPerDegLat = 111320.0;
      const lat0 = 37.5;
      filter.process(_pos(lat: lat0, lon: 127.0, time: base));

      // Parked for two minutes: jitter fixes only, no distance credited.
      for (var i = 1; i <= 24; i++) {
        final jitterLat = lat0 + (i.isEven ? 2 : -2) / metersPerDegLat;
        final fix = filter.process(_pos(
          lat: jitterLat,
          lon: 127.0,
          time: base.add(Duration(seconds: i * 5)),
        ));
        expect(fix.distanceDeltaMeters, 0);
      }

      // Now pull away at 10 m/s. Without re-anchoring during the stop, the
      // anchor timestamp would be two minutes stale and this would report a
      // fraction of a m/s instead.
      var lat = lat0;
      final speeds = <double>[];
      for (var i = 1; i <= 3; i++) {
        lat += 10.0 / metersPerDegLat;
        final fix = filter.process(_pos(
          lat: lat,
          lon: 127.0,
          time: base.add(Duration(seconds: 120 + i)),
        ));
        if (fix.distanceDeltaMeters > 0) speeds.add(fix.speedMps);
      }

      expect(speeds, isNotEmpty);
      expect(speeds.last, closeTo(10.0, 1.0));
    });
  });
}
