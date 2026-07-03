import 'fare_mode.dart';

/// A single completed & settled trip, stored in the local trip log.
class TripRecord {
  final String id;
  final FareMode mode;
  final DateTime startTime;
  final DateTime endTime;
  final double distanceMeters;
  final int fareWon;

  /// Recorded only for carpool trips, so history stays accurate even if the
  /// user changes the setting later.
  final double? fuelEfficiencyKmPerLiter;

  TripRecord({
    required this.id,
    required this.mode,
    required this.startTime,
    required this.endTime,
    required this.distanceMeters,
    required this.fareWon,
    this.fuelEfficiencyKmPerLiter,
  });

  Duration get duration => endTime.difference(startTime);

  double get distanceKm => distanceMeters / 1000;

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': mode.name,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'distanceMeters': distanceMeters,
        'fareWon': fareWon,
        'fuelEfficiencyKmPerLiter': fuelEfficiencyKmPerLiter,
      };

  factory TripRecord.fromJson(Map<String, dynamic> json) {
    return TripRecord(
      id: json['id'] as String,
      mode: FareMode.values.firstWhere(
        (e) => e.name == json['mode'],
        orElse: () => FareMode.standard,
      ),
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      fareWon: json['fareWon'] as int,
      fuelEfficiencyKmPerLiter:
          (json['fuelEfficiencyKmPerLiter'] as num?)?.toDouble(),
    );
  }
}
