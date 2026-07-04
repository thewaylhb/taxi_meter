import '../services/fare_meter.dart';
import 'fare_mode.dart';

/// User-configurable fare settings, persisted locally.
class FareSettings {
  FareMode mode;

  /// If true, [FareMode.standard] uses the custom rate fields below instead
  /// of [StandardFareMeter]'s built-in Seoul-rate defaults.
  bool useCustomStandardRates;

  /// Base fare in won, covering the first [standardBaseDistanceMeters].
  double standardBaseFareWon;

  /// Distance (meters) covered by the base fare before pulse charging
  /// starts.
  double standardBaseDistanceMeters;

  /// Distance (meters) that corresponds to one [standardDistancePulseWon]
  /// charge at normal speed.
  double standardDistancePulseMeters;

  /// Won charged per [standardDistancePulseMeters] (or per
  /// [standardTimePulseSeconds] while below [standardSlowSpeedThresholdKmh]).
  double standardDistancePulseWon;

  /// Speed (km/h) below which elapsed time bills as slow-time progress
  /// instead of distance.
  double standardSlowSpeedThresholdKmh;

  /// Seconds of slow/stopped time that correspond to one
  /// [standardDistancePulseWon] charge.
  double standardTimePulseSeconds;

  /// Car fuel efficiency in km per liter, used only in [FareMode.carpool].
  double fuelEfficiencyKmPerLiter;

  /// Fuel price in won per liter, used only in [FareMode.carpool].
  double fuelPricePerLiterWon;

  FareSettings({
    this.mode = FareMode.standard,
    this.useCustomStandardRates = false,
    this.standardBaseFareWon =
        StandardFareMeter.defaultBaseFareWon * 1.0,
    this.standardBaseDistanceMeters =
        StandardFareMeter.defaultBaseDistanceMeters,
    this.standardDistancePulseMeters =
        StandardFareMeter.defaultDistancePulseMeters,
    this.standardDistancePulseWon =
        StandardFareMeter.defaultDistancePulseWon * 1.0,
    this.standardSlowSpeedThresholdKmh =
        StandardFareMeter.defaultSlowSpeedThresholdMps * 3600 / 1000,
    this.standardTimePulseSeconds = StandardFareMeter.defaultTimePulseSeconds,
    this.fuelEfficiencyKmPerLiter = 12.0,
    this.fuelPricePerLiterWon = 2000.0,
  });

  FareSettings copyWith({
    FareMode? mode,
    bool? useCustomStandardRates,
    double? standardBaseFareWon,
    double? standardBaseDistanceMeters,
    double? standardDistancePulseMeters,
    double? standardDistancePulseWon,
    double? standardSlowSpeedThresholdKmh,
    double? standardTimePulseSeconds,
    double? fuelEfficiencyKmPerLiter,
    double? fuelPricePerLiterWon,
  }) {
    return FareSettings(
      mode: mode ?? this.mode,
      useCustomStandardRates:
          useCustomStandardRates ?? this.useCustomStandardRates,
      standardBaseFareWon: standardBaseFareWon ?? this.standardBaseFareWon,
      standardBaseDistanceMeters:
          standardBaseDistanceMeters ?? this.standardBaseDistanceMeters,
      standardDistancePulseMeters:
          standardDistancePulseMeters ?? this.standardDistancePulseMeters,
      standardDistancePulseWon:
          standardDistancePulseWon ?? this.standardDistancePulseWon,
      standardSlowSpeedThresholdKmh:
          standardSlowSpeedThresholdKmh ?? this.standardSlowSpeedThresholdKmh,
      standardTimePulseSeconds:
          standardTimePulseSeconds ?? this.standardTimePulseSeconds,
      fuelEfficiencyKmPerLiter:
          fuelEfficiencyKmPerLiter ?? this.fuelEfficiencyKmPerLiter,
      fuelPricePerLiterWon: fuelPricePerLiterWon ?? this.fuelPricePerLiterWon,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'useCustomStandardRates': useCustomStandardRates,
        'standardBaseFareWon': standardBaseFareWon,
        'standardBaseDistanceMeters': standardBaseDistanceMeters,
        'standardDistancePulseMeters': standardDistancePulseMeters,
        'standardDistancePulseWon': standardDistancePulseWon,
        'standardSlowSpeedThresholdKmh': standardSlowSpeedThresholdKmh,
        'standardTimePulseSeconds': standardTimePulseSeconds,
        'fuelEfficiencyKmPerLiter': fuelEfficiencyKmPerLiter,
        'fuelPricePerLiterWon': fuelPricePerLiterWon,
      };

  factory FareSettings.fromJson(Map<String, dynamic> json) {
    final defaults = FareSettings();
    return FareSettings(
      mode: FareMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => FareMode.standard,
      ),
      useCustomStandardRates: json['useCustomStandardRates'] as bool? ?? false,
      standardBaseFareWon: (json['standardBaseFareWon'] as num?)?.toDouble() ??
          defaults.standardBaseFareWon,
      standardBaseDistanceMeters:
          (json['standardBaseDistanceMeters'] as num?)?.toDouble() ??
              defaults.standardBaseDistanceMeters,
      standardDistancePulseMeters:
          (json['standardDistancePulseMeters'] as num?)?.toDouble() ??
              defaults.standardDistancePulseMeters,
      standardDistancePulseWon:
          (json['standardDistancePulseWon'] as num?)?.toDouble() ??
              defaults.standardDistancePulseWon,
      standardSlowSpeedThresholdKmh:
          (json['standardSlowSpeedThresholdKmh'] as num?)?.toDouble() ??
              defaults.standardSlowSpeedThresholdKmh,
      standardTimePulseSeconds:
          (json['standardTimePulseSeconds'] as num?)?.toDouble() ??
              defaults.standardTimePulseSeconds,
      fuelEfficiencyKmPerLiter:
          (json['fuelEfficiencyKmPerLiter'] as num?)?.toDouble() ?? 12.0,
      fuelPricePerLiterWon:
          (json['fuelPricePerLiterWon'] as num?)?.toDouble() ?? 2000.0,
    );
  }
}
