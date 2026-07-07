import 'fare_mode.dart';

/// Periodic snapshot of an in-progress trip, persisted so an unsettled trip
/// survives the app being killed (crash, OS memory pressure, swipe-close)
/// before the driver reaches the settlement button.
class ActiveTripSnapshot {
  final FareMode mode;
  final DateTime startTime;
  final DateTime lastUpdateTime;
  final double distanceMeters;
  final int fareWon;
  final double? fuelEfficiencyKmPerLiter;
  final double? fuelPricePerLiterWon;
  final int? carpoolBaseFareWon;

  ActiveTripSnapshot({
    required this.mode,
    required this.startTime,
    required this.lastUpdateTime,
    required this.distanceMeters,
    required this.fareWon,
    this.fuelEfficiencyKmPerLiter,
    this.fuelPricePerLiterWon,
    this.carpoolBaseFareWon,
  });

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'startTime': startTime.toIso8601String(),
        'lastUpdateTime': lastUpdateTime.toIso8601String(),
        'distanceMeters': distanceMeters,
        'fareWon': fareWon,
        'fuelEfficiencyKmPerLiter': fuelEfficiencyKmPerLiter,
        'fuelPricePerLiterWon': fuelPricePerLiterWon,
        'carpoolBaseFareWon': carpoolBaseFareWon,
      };

  factory ActiveTripSnapshot.fromJson(Map<String, dynamic> json) {
    return ActiveTripSnapshot(
      mode: FareMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => FareMode.standard,
      ),
      startTime: DateTime.parse(json['startTime'] as String),
      lastUpdateTime: DateTime.parse(json['lastUpdateTime'] as String),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      fareWon: json['fareWon'] as int,
      fuelEfficiencyKmPerLiter:
          (json['fuelEfficiencyKmPerLiter'] as num?)?.toDouble(),
      fuelPricePerLiterWon: (json['fuelPricePerLiterWon'] as num?)?.toDouble(),
      carpoolBaseFareWon: (json['carpoolBaseFareWon'] as num?)?.toInt(),
    );
  }
}
