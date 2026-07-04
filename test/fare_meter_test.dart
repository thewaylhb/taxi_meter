import 'package:flutter_test/flutter_test.dart';

import 'package:taximeter/services/fare_meter.dart';

DateTime _at(int hour, [int minute = 0, int second = 0]) =>
    DateTime(2026, 7, 4, hour, minute, second);

void main() {
  group('StandardFareMeter', () {
    test('base fare only with no movement', () {
      final meter = StandardFareMeter();
      meter.start(_at(12));
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon);
      expect(meter.totalDistanceMeters, 0);
    });

    test('no distance pulse charged within the base distance', () {
      final meter = StandardFareMeter();
      meter.start(_at(12));
      meter.update(
        distanceDeltaMeters: 1600,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 5),
      );
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon);
      expect(meter.totalDistanceMeters, 1600);
    });

    test('distance pulse charges 100 won per 131m beyond base distance', () {
      final meter = StandardFareMeter();
      meter.start(_at(12));
      meter.update(
        distanceDeltaMeters: 1600 + 131,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 5),
      );
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon + 100);

      meter.update(
        distanceDeltaMeters: 131,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 6),
      );
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon + 200);
    });

    test('time pulse does not accrue before the base distance is covered', () {
      final meter = StandardFareMeter();
      meter.start(_at(12));
      // 300s of slow time is only worth 1310m of billing progress - still
      // short of the 1600m base distance, so nothing should be charged yet.
      meter.update(
        distanceDeltaMeters: 0,
        slowTimeDeltaSeconds: 300,
        now: _at(12, 5),
      );
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon);
    });

    test('time pulse charges 100 won per 30s once beyond base distance', () {
      final meter = StandardFareMeter();
      meter.start(_at(12));
      meter.update(
        distanceDeltaMeters: 1600,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 5),
      );
      meter.update(
        distanceDeltaMeters: 0,
        slowTimeDeltaSeconds: 30,
        now: _at(12, 6),
      );
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon + 100);
    });

    test('slow-time progress and crawl distance do not double count', () {
      final meter = StandardFareMeter();
      meter.start(_at(12));
      meter.update(
        distanceDeltaMeters: 1600,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 5),
      );
      // Crawling: 20m of real distance covered during a 30s slow interval.
      // Billing should count only the 30s time-equivalent (131m), not
      // 20m + 131m.
      meter.update(
        distanceDeltaMeters: 20,
        slowTimeDeltaSeconds: 30,
        now: _at(12, 6),
      );
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon + 100);
      expect(meter.totalDistanceMeters, 1620);
    });

    test('real distance is billed even when it exceeds a capped time credit', () {
      final meter = StandardFareMeter();
      meter.start(_at(12));
      meter.update(
        distanceDeltaMeters: 1600,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 5),
      );
      // A GPS gap capped the billable time to 5s (=> 21.8m equivalent), but
      // the car actually covered 200m of real distance in that interval.
      // Billing must use the larger, real value, not the smaller time
      // credit.
      meter.update(
        distanceDeltaMeters: 200,
        slowTimeDeltaSeconds: 5,
        now: _at(12, 6),
      );
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon + 100);
      expect(meter.totalDistanceMeters, 1800);
    });

    test('late-night surcharge tiers', () {
      expect(StandardFareMeter.lateNightMultiplier(_at(21)), 1.0);
      expect(StandardFareMeter.lateNightMultiplier(_at(22)), 1.2);
      expect(StandardFareMeter.lateNightMultiplier(_at(23)), 1.4);
      expect(StandardFareMeter.lateNightMultiplier(_at(0)), 1.4);
      expect(StandardFareMeter.lateNightMultiplier(_at(1)), 1.4);
      expect(StandardFareMeter.lateNightMultiplier(_at(2)), 1.2);
      expect(StandardFareMeter.lateNightMultiplier(_at(3)), 1.2);
      expect(StandardFareMeter.lateNightMultiplier(_at(4)), 1.0);
    });

    test('base fare is surcharged when the trip starts in a late-night band', () {
      final meter = StandardFareMeter();
      meter.start(_at(23));
      expect(meter.fareWon, (StandardFareMeter.defaultBaseFareWon * 1.4).round());
    });

    test('a pulse crossing into a new surcharge band bills at the new rate', () {
      final meter = StandardFareMeter();
      meter.start(_at(21, 59));
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon);

      meter.update(
        distanceDeltaMeters: 1600 + 131,
        slowTimeDeltaSeconds: 0,
        now: _at(22, 0),
      );
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon + 120);
    });
  });

  group('CarpoolFareMeter', () {
    test('base fare plus fuel cost proportional to distance / efficiency', () {
      final meter = CarpoolFareMeter(
        fuelEfficiencyKmPerLiter: 10,
        fuelPricePerLiterWon: 2000,
      );
      meter.start(_at(12));
      meter.update(
        distanceDeltaMeters: 10000,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 30),
      );
      // 10km / 10km/L = 1L * 2,000원/L = 2,000원.
      expect(meter.fareWon, 3000 + 2000);
      expect(meter.totalDistanceMeters, 10000);
    });

    test('better fuel efficiency lowers the fare', () {
      final meter = CarpoolFareMeter(
        fuelEfficiencyKmPerLiter: 20,
        fuelPricePerLiterWon: 2000,
      );
      meter.start(_at(12));
      meter.update(
        distanceDeltaMeters: 10000,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 30),
      );
      expect(meter.fareWon, 3000 + 1000);
    });

    test('higher fuel price raises the fare', () {
      final meter = CarpoolFareMeter(
        fuelEfficiencyKmPerLiter: 10,
        fuelPricePerLiterWon: 3000,
      );
      meter.start(_at(12));
      meter.update(
        distanceDeltaMeters: 10000,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 30),
      );
      expect(meter.fareWon, 3000 + 3000);
    });
  });
}
