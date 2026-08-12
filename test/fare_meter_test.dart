import 'package:flutter_test/flutter_test.dart';

import 'package:meter/services/fare_meter.dart';

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
      expect(meter.fareWon, 6700);
    });

    // Seoul's published 중형택시 rate table (2023-02-01, unchanged through
    // 2025). These are the exact numbers a passenger sees on a real meter,
    // so they're pinned literally rather than recomputed from the
    // multiplier - recomputing would just restate whatever the code does.
    test('surcharged base fare matches the published Seoul rate table', () {
      int baseFareAt(int hour) {
        final meter = StandardFareMeter();
        meter.start(_at(hour));
        return meter.fareWon;
      }

      expect(baseFareAt(12), 4800, reason: '주간');
      expect(baseFareAt(22), 5800, reason: '22~23시 +20%');
      expect(baseFareAt(23), 6700, reason: '23~02시 +40%');
      expect(baseFareAt(1), 6700, reason: '23~02시 +40%');
      expect(baseFareAt(2), 5800, reason: '02~04시 +20%');
      expect(baseFareAt(3), 5800, reason: '02~04시 +20%');
      expect(baseFareAt(4), 4800, reason: '할증 종료');
    });

    test('a custom base fare is not snapped to 100 won outside surcharge hours',
        () {
      final meter = StandardFareMeter(baseFareWon: 3333);
      meter.start(_at(12));
      expect(meter.fareWon, 3333);
    });

    test('distance pulse costs match the published Seoul rate table', () {
      int pulseCostAt(int hour) {
        final meter = StandardFareMeter();
        meter.start(_at(hour));
        final base = meter.fareWon;
        meter.update(
          distanceDeltaMeters: 1600 + 131,
          slowTimeDeltaSeconds: 0,
          now: _at(hour, 5),
        );
        return meter.fareWon - base;
      }

      // The table states these as per-pulse amounts (131m당 100/120/140원),
      // so the running total is deliberately not rounded to 100-won steps.
      expect(pulseCostAt(12), 100, reason: '주간 131m당 100원');
      expect(pulseCostAt(22), 120, reason: '22~23시 131m당 120원');
      expect(pulseCostAt(23), 140, reason: '23~02시 131m당 140원');
      expect(pulseCostAt(2), 120, reason: '02~04시 131m당 120원');
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

    test('suburban surcharge adds 20% to a pulse driven while flagged', () {
      final meter = StandardFareMeter();
      meter.start(_at(12));
      meter.update(
        distanceDeltaMeters: 1600 + 131,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 5),
        isSuburban: true,
      );
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon + 120);
    });

    test('suburban surcharge does not apply to a pulse driven while unflagged', () {
      final meter = StandardFareMeter();
      meter.start(_at(12));
      meter.update(
        distanceDeltaMeters: 1600 + 131,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 5),
      );
      expect(meter.fareWon, StandardFareMeter.defaultBaseFareWon + 100);
    });

    test('suburban and late-night surcharge rates add rather than compound',
        () {
      final meter = StandardFareMeter();
      meter.start(_at(23));
      meter.update(
        distanceDeltaMeters: 1600 + 131,
        slowTimeDeltaSeconds: 0,
        now: _at(23, 5),
        isSuburban: true,
      );
      // Base: 4800 * 1.4 = 6720, rounded to the published 6,700.
      // Pulse: 100 * (1 + 0.4 + 0.2) = 160.
      // Compounding instead would give 100 * 1.4 * 1.2 = 168, i.e. a 68%
      // combined surcharge, above Seoul's published 60% cap.
      expect(meter.fareWon, 6700 + 160);
    });

    test('the combined surcharge never exceeds the published 60% cap', () {
      // 40% is the steepest late-night band, 20% the suburban rate.
      final worstCase =
          StandardFareMeter.combinedMultiplier(_at(23), isSuburban: true);
      expect(worstCase, closeTo(1.6, 1e-9));

      for (var hour = 0; hour < 24; hour++) {
        for (final suburban in [true, false]) {
          final multiplier = StandardFareMeter.combinedMultiplier(
            _at(hour),
            isSuburban: suburban,
          );
          expect(multiplier, lessThanOrEqualTo(1.6 + 1e-9),
              reason: '$hour시 시계외=$suburban');
        }
      }
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

    test('custom base fare overrides the 3,000원 default', () {
      final meter = CarpoolFareMeter(
        baseFareWon: 5000,
        fuelEfficiencyKmPerLiter: 10,
        fuelPricePerLiterWon: 2000,
      );
      meter.start(_at(12));
      meter.update(
        distanceDeltaMeters: 10000,
        slowTimeDeltaSeconds: 0,
        now: _at(12, 30),
      );
      expect(meter.fareWon, 5000 + 2000);
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

  group('NoFareMeter', () {
    test('tracks distance but never charges anything', () {
      final meter = NoFareMeter();
      meter.start(_at(12));
      expect(meter.fareWon, 0);

      meter.update(
        distanceDeltaMeters: 10000,
        slowTimeDeltaSeconds: 999999,
        now: _at(12, 30),
      );
      expect(meter.fareWon, 0);
      expect(meter.totalDistanceMeters, 10000);
    });
  });
}
