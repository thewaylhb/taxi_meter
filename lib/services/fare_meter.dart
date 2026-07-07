/// Common interface for a running fare calculation.
///
/// Fed filtered distance/time increments as the trip progresses; tracks its
/// own running total so the UI can read [fareWon] at any time.
abstract class FareMeter {
  void start(DateTime now);

  /// [distanceDeltaMeters] is the (already jitter-filtered) distance moved
  /// since the last update. [slowTimeDeltaSeconds] is how much of that
  /// interval was spent below the "slow/stopped" speed threshold.
  /// [isSuburban] marks the interval as driven outside the service area, for
  /// meters that apply a suburban ("시외") surcharge; meters that don't
  /// support one simply ignore it.
  void update({
    required double distanceDeltaMeters,
    required double slowTimeDeltaSeconds,
    required DateTime now,
    bool isSuburban = false,
  });

  int get fareWon;

  double get totalDistanceMeters;
}

/// Standard metered fare, modeled on Seoul medium (중형) taxi rates
/// (in effect since 2023-02-01, unchanged through 2025):
///
/// - Base fare: 4,800 won covers the first 1.6 km.
/// - Beyond the base distance, fare accrues from a single combined
///   distance/time "progress" meter: +100 won per 131 m at normal speed, or
///   +100 won per 30 s while below ~15.72 km/h. The two never stack for the
///   same stretch of the trip — each interval bills the *larger* of the
///   real distance covered and the slow-time equivalent at the
///   pulse-parity rate (131 m / 30 s is exactly the threshold speed),
///   rather than summing both. Taking the max (not the sum) means a
///   crawling interval is never billed twice, but real distance actually
///   covered is also never dropped in favor of a smaller time credit —
///   which matters when a GPS gap (see [GpsFilter.maxBillableGap]) caps the
///   billable time far below the real elapsed time.
/// - Late-night surcharge, applied per-increment (so a trip crossing a
///   band boundary is billed correctly on each side): +20% from 22:00 to
///   23:00, +40% from 23:00 to 02:00, +20% from 02:00 to 04:00.
/// - Suburban ("시외") surcharge: +20% on any increment driven while
///   [isSuburban] is flagged, e.g. by the driver toggling it on once the
///   trip leaves the licensed service area. Stacks multiplicatively with
///   the late-night surcharge, same as the real meter rule.
class StandardFareMeter implements FareMeter {
  static const int defaultBaseFareWon = 4800;
  static const double defaultBaseDistanceMeters = 1600;
  static const double defaultDistancePulseMeters = 131;
  static const int defaultDistancePulseWon = 100;
  static const double defaultSlowSpeedThresholdMps = 15.72 * 1000 / 3600;
  static const double defaultTimePulseSeconds = 30;
  static const double suburbanSurchargeMultiplier = 1.2;

  /// Base fare in won, covering the first [baseDistanceMeters].
  final int baseFareWon;

  /// Distance (meters) covered by the base fare before pulse charging
  /// starts.
  final double baseDistanceMeters;

  /// Distance (meters) that corresponds to one [distancePulseWon] charge at
  /// normal speed.
  final double distancePulseMeters;

  /// Won charged per [distancePulseMeters] (or per [timePulseSeconds] while
  /// below [slowSpeedThresholdMps]).
  final int distancePulseWon;

  /// Speed (m/s) below which elapsed time bills as slow-time progress
  /// instead of distance.
  final double slowSpeedThresholdMps;

  /// Seconds of slow/stopped time that correspond to one
  /// [distancePulseWon] charge.
  final double timePulseSeconds;

  StandardFareMeter({
    this.baseFareWon = defaultBaseFareWon,
    this.baseDistanceMeters = defaultBaseDistanceMeters,
    this.distancePulseMeters = defaultDistancePulseMeters,
    this.distancePulseWon = defaultDistancePulseWon,
    this.slowSpeedThresholdMps = defaultSlowSpeedThresholdMps,
    this.timePulseSeconds = defaultTimePulseSeconds,
  });

  /// Real physical distance travelled, for display/record purposes only.
  double _realDistanceMeters = 0;

  /// Combined distance/time billing progress, in distance-equivalent
  /// meters. Only this drives pulse charging.
  double _billableProgressMeters = 0;
  int _pulsesCharged = 0;
  int _fareWon = 0;

  @override
  void start(DateTime now) {
    _realDistanceMeters = 0;
    _billableProgressMeters = 0;
    _pulsesCharged = 0;
    _fareWon = _applySurcharges(baseFareWon, now, isSuburban: false);
  }

  @override
  void update({
    required double distanceDeltaMeters,
    required double slowTimeDeltaSeconds,
    required DateTime now,
    bool isSuburban = false,
  }) {
    _realDistanceMeters += distanceDeltaMeters;

    final slowTimeEquivalentMeters =
        slowTimeDeltaSeconds / timePulseSeconds * distancePulseMeters;
    _billableProgressMeters += distanceDeltaMeters > slowTimeEquivalentMeters
        ? distanceDeltaMeters
        : slowTimeEquivalentMeters;

    _chargePulses(now, isSuburban);
  }

  void _chargePulses(DateTime now, bool isSuburban) {
    if (_billableProgressMeters <= baseDistanceMeters) return;
    final chargeableProgress = _billableProgressMeters - baseDistanceMeters;
    final totalPulses = (chargeableProgress / distancePulseMeters).floor();
    final newPulses = totalPulses - _pulsesCharged;
    if (newPulses > 0) {
      _fareWon += _applySurcharges(
        distancePulseWon * newPulses,
        now,
        isSuburban: isSuburban,
      );
      _pulsesCharged = totalPulses;
    }
  }

  int _applySurcharges(int amount, DateTime now, {required bool isSuburban}) {
    final multiplier = lateNightMultiplier(now) *
        (isSuburban ? suburbanSurchargeMultiplier : 1.0);
    return (amount * multiplier).round();
  }

  /// Seoul's late-night surcharge schedule: 20% (22-23h), 40% (23-02h),
  /// then 20% again (02-04h).
  static double lateNightMultiplier(DateTime t) {
    final hour = t.hour;
    if (hour == 22) return 1.2;
    if (hour == 23 || hour == 0 || hour == 1) return 1.4;
    if (hour == 2 || hour == 3) return 1.2;
    return 1.0;
  }

  static bool isLateNight(DateTime t) => lateNightMultiplier(t) > 1.0;

  @override
  int get fareWon => _fareWon;

  @override
  double get totalDistanceMeters => _realDistanceMeters;
}

/// Carpool cost-sharing mode: a flat base fare plus a distance fare derived
/// from the car's fuel efficiency and the fuel price, both from settings.
/// No time fare and no late-night surcharge — this isn't a commercial
/// metered fare, just a fuel-cost split.
class CarpoolFareMeter implements FareMeter {
  static const int defaultBaseFareWon = 3000;

  /// Flat base fare, from settings.
  final int baseFareWon;

  /// km travelled per liter of fuel, from settings.
  final double fuelEfficiencyKmPerLiter;

  /// Fuel price in won per liter, from settings.
  final double fuelPricePerLiterWon;

  double _distanceMeters = 0;

  CarpoolFareMeter({
    this.baseFareWon = defaultBaseFareWon,
    required this.fuelEfficiencyKmPerLiter,
    required this.fuelPricePerLiterWon,
  });

  @override
  void start(DateTime now) {
    _distanceMeters = 0;
  }

  @override
  void update({
    required double distanceDeltaMeters,
    required double slowTimeDeltaSeconds,
    required DateTime now,
    bool isSuburban = false,
  }) {
    _distanceMeters += distanceDeltaMeters;
  }

  @override
  int get fareWon {
    final distanceKm = _distanceMeters / 1000;
    final fuelCostWon =
        distanceKm / fuelEfficiencyKmPerLiter * fuelPricePerLiterWon;
    return baseFareWon + fuelCostWon.round();
  }

  @override
  double get totalDistanceMeters => _distanceMeters;
}

/// No-op fare for [FareMode.safeDriving]: tracks distance the same way as
/// the other meters (so elapsed/distance-derived stats still work) but
/// never charges anything.
class NoFareMeter implements FareMeter {
  double _distanceMeters = 0;

  @override
  void start(DateTime now) {
    _distanceMeters = 0;
  }

  @override
  void update({
    required double distanceDeltaMeters,
    required double slowTimeDeltaSeconds,
    required DateTime now,
    bool isSuburban = false,
  }) {
    _distanceMeters += distanceDeltaMeters;
  }

  @override
  int get fareWon => 0;

  @override
  double get totalDistanceMeters => _distanceMeters;
}
