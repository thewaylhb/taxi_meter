import 'fare_mode.dart';

/// User-configurable fare settings, persisted locally.
class FareSettings {
  FareMode mode;

  /// Car fuel efficiency in km per liter, used only in [FareMode.carpool].
  double fuelEfficiencyKmPerLiter;

  /// Fuel price in won per liter, used only in [FareMode.carpool].
  double fuelPricePerLiterWon;

  FareSettings({
    this.mode = FareMode.standard,
    this.fuelEfficiencyKmPerLiter = 12.0,
    this.fuelPricePerLiterWon = 2000.0,
  });

  FareSettings copyWith({
    FareMode? mode,
    double? fuelEfficiencyKmPerLiter,
    double? fuelPricePerLiterWon,
  }) {
    return FareSettings(
      mode: mode ?? this.mode,
      fuelEfficiencyKmPerLiter:
          fuelEfficiencyKmPerLiter ?? this.fuelEfficiencyKmPerLiter,
      fuelPricePerLiterWon: fuelPricePerLiterWon ?? this.fuelPricePerLiterWon,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'fuelEfficiencyKmPerLiter': fuelEfficiencyKmPerLiter,
        'fuelPricePerLiterWon': fuelPricePerLiterWon,
      };

  factory FareSettings.fromJson(Map<String, dynamic> json) {
    return FareSettings(
      mode: FareMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => FareMode.standard,
      ),
      fuelEfficiencyKmPerLiter:
          (json['fuelEfficiencyKmPerLiter'] as num?)?.toDouble() ?? 12.0,
      fuelPricePerLiterWon:
          (json['fuelPricePerLiterWon'] as num?)?.toDouble() ?? 2000.0,
    );
  }
}
