import 'fare_mode.dart';

/// User-configurable fare settings, persisted locally.
class FareSettings {
  FareMode mode;

  /// Car fuel efficiency in km per liter, used only in [FareMode.carpool].
  double fuelEfficiencyKmPerLiter;

  FareSettings({
    this.mode = FareMode.standard,
    this.fuelEfficiencyKmPerLiter = 12.0,
  });

  FareSettings copyWith({FareMode? mode, double? fuelEfficiencyKmPerLiter}) {
    return FareSettings(
      mode: mode ?? this.mode,
      fuelEfficiencyKmPerLiter:
          fuelEfficiencyKmPerLiter ?? this.fuelEfficiencyKmPerLiter,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'fuelEfficiencyKmPerLiter': fuelEfficiencyKmPerLiter,
      };

  factory FareSettings.fromJson(Map<String, dynamic> json) {
    return FareSettings(
      mode: FareMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => FareMode.standard,
      ),
      fuelEfficiencyKmPerLiter:
          (json['fuelEfficiencyKmPerLiter'] as num?)?.toDouble() ?? 11.0,
    );
  }
}
