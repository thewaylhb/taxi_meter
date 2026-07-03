/// Common interface for a running fare calculation.
///
/// Fed filtered distance/time increments as the trip progresses; tracks its
/// own running total so the UI can read [fareWon] at any time.
abstract class FareMeter {
  void start(DateTime now);

  /// [distanceDeltaMeters] is the (already jitter-filtered) distance moved
  /// since the last update. [slowTimeDeltaSeconds] is how much of that
  /// interval was spent below the "slow/stopped" speed threshold.
  void update({
    required double distanceDeltaMeters,
    required double slowTimeDeltaSeconds,
    required DateTime now,
  });

  int get fareWon;

  double get totalDistanceMeters;
}

/// Standard metered fare, modeled on Seoul medium (중형) taxi rates
/// (in effect since 2023-02-01, unchanged through 2025):
///
/// - Base fare: 4,800 won covers the first 1.6 km.
/// - Distance fare: +100 won per 131 m beyond the base distance.
/// - Time fare: +100 won per 30 s spent below ~15.72 km/h (the
///   time/distance-combined metering used to compensate for slow traffic),
///   accruing independently of the distance fare for the whole trip.
/// - Late-night surcharge: +20% on each fare increment charged between
///   22:00 and 04:00 (applied per-increment so a trip crossing midnight is
///   still billed correctly on each side of the boundary).
class StandardFareMeter implements FareMeter {
  static const int baseFareWon = 4800;
  static const double baseDistanceMeters = 1600;
  static const double distancePulseMeters = 131;
  static const int distancePulseWon = 100;
  static const double slowSpeedThresholdMps = 15.72 * 1000 / 3600;
  static const double timePulseSeconds = 30;
  static const int timePulseWon = 100;
  static const double lateNightMultiplier = 1.2;

  double _distanceMeters = 0;
  double _slowSeconds = 0;
  int _distancePulsesCharged = 0;
  int _timePulsesCharged = 0;
  int _fareWon = 0;

  @override
  void start(DateTime now) {
    _distanceMeters = 0;
    _slowSeconds = 0;
    _distancePulsesCharged = 0;
    _timePulsesCharged = 0;
    _fareWon = _applyLateNight(baseFareWon, now);
  }

  @override
  void update({
    required double distanceDeltaMeters,
    required double slowTimeDeltaSeconds,
    required DateTime now,
  }) {
    _distanceMeters += distanceDeltaMeters;
    _slowSeconds += slowTimeDeltaSeconds;
    _chargeDistancePulses(now);
    _chargeTimePulses(now);
  }

  void _chargeDistancePulses(DateTime now) {
    if (_distanceMeters <= baseDistanceMeters) return;
    final chargeableDistance = _distanceMeters - baseDistanceMeters;
    final totalPulses = (chargeableDistance / distancePulseMeters).floor();
    final newPulses = totalPulses - _distancePulsesCharged;
    if (newPulses > 0) {
      _fareWon += _applyLateNight(distancePulseWon * newPulses, now);
      _distancePulsesCharged = totalPulses;
    }
  }

  void _chargeTimePulses(DateTime now) {
    final totalPulses = (_slowSeconds / timePulseSeconds).floor();
    final newPulses = totalPulses - _timePulsesCharged;
    if (newPulses > 0) {
      _fareWon += _applyLateNight(timePulseWon * newPulses, now);
      _timePulsesCharged = totalPulses;
    }
  }

  int _applyLateNight(int amount, DateTime now) {
    return isLateNight(now) ? (amount * lateNightMultiplier).round() : amount;
  }

  static bool isLateNight(DateTime t) => t.hour >= 22 || t.hour < 4;

  @override
  int get fareWon => _fareWon;

  @override
  double get totalDistanceMeters => _distanceMeters;
}

/// Carpool cost-sharing mode: a flat base fare plus a distance fare derived
/// from the car's fuel efficiency, at a fixed fuel price. No time fare and
/// no late-night surcharge — this isn't a commercial metered fare, just a
/// fuel-cost split.
class CarpoolFareMeter implements FareMeter {
  static const int baseFareWon = 3000;
  static const double fuelPricePerLiterWon = 2000;

  /// km travelled per liter of fuel, from settings.
  final double fuelEfficiencyKmPerLiter;

  double _distanceMeters = 0;

  CarpoolFareMeter({required this.fuelEfficiencyKmPerLiter});

  @override
  void start(DateTime now) {
    _distanceMeters = 0;
  }

  @override
  void update({
    required double distanceDeltaMeters,
    required double slowTimeDeltaSeconds,
    required DateTime now,
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
