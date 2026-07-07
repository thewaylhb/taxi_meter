import '../services/fare_meter.dart';
import '../utils/formatters.dart';
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

  /// Flat base fare in won, used only in [FareMode.carpool].
  double carpoolBaseFareWon;

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
    this.carpoolBaseFareWon = CarpoolFareMeter.defaultBaseFareWon * 1.0,
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
    double? carpoolBaseFareWon,
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
      carpoolBaseFareWon: carpoolBaseFareWon ?? this.carpoolBaseFareWon,
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
        'carpoolBaseFareWon': carpoolBaseFareWon,
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
      carpoolBaseFareWon: (json['carpoolBaseFareWon'] as num?)?.toDouble() ??
          defaults.carpoolBaseFareWon,
      fuelEfficiencyKmPerLiter:
          (json['fuelEfficiencyKmPerLiter'] as num?)?.toDouble() ?? 12.0,
      fuelPricePerLiterWon:
          (json['fuelPricePerLiterWon'] as num?)?.toDouble() ?? 2000.0,
    );
  }
}

/// [FareMode.description] reflecting the user's actual configured rates,
/// where the static getter would otherwise show a stale default (e.g.
/// carpool's hardcoded "3,000원" even after the base fare is changed in
/// settings). Null for safeDriving, which has no rates to describe.
String? dynamicFareModeDescription(FareMode mode, FareSettings settings) {
  switch (mode) {
    case FareMode.standard:
      return settings.useCustomStandardRates
          ? '사용자 설정 요금제'
          : mode.description;
    case FareMode.carpool:
      return '기본요금 ${formatWon(settings.carpoolBaseFareWon.round())} + 주행거리 할증';
    case FareMode.safeDriving:
      return null;
  }
}
