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

  /// Recorded only for carpool trips, so history stays accurate even if the
  /// user changes the setting later.
  final double? fuelPricePerLiterWon;

  /// Number of riders the fare was split across at settlement time ("N빵").
  /// 1 means no split.
  final int riderCount;

  /// Highest instantaneous speed reached during the trip. Null for trips
  /// recorded before this field existed, rather than a misleading 0.
  final double? maxSpeedKmh;

  TripRecord({
    required this.id,
    required this.mode,
    required this.startTime,
    required this.endTime,
    required this.distanceMeters,
    required this.fareWon,
    this.fuelEfficiencyKmPerLiter,
    this.fuelPricePerLiterWon,
    this.riderCount = 1,
    this.maxSpeedKmh,
  });

  Duration get duration => endTime.difference(startTime);

  double get distanceKm => distanceMeters / 1000;

  /// Per-rider share of [fareWon], rounded up to the nearest 100 won. With a
  /// single rider there's nothing to split, so it's the exact fare rather
  /// than a rounded value that could mismatch the total shown above it.
  int get amountPerPersonWon =>
      riderCount <= 1 ? fareWon : (fareWon / riderCount / 100).ceil() * 100;

  /// 표정속도 (average operating speed): total distance divided by total
  /// elapsed time, including any stopped time. Zero for a zero-duration
  /// trip rather than dividing by zero.
  double get averageSpeedKmh {
    final hours = duration.inMilliseconds / 1000 / 3600;
    return hours > 0 ? distanceKm / hours : 0;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'mode': mode.name,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'distanceMeters': distanceMeters,
        'fareWon': fareWon,
        'fuelEfficiencyKmPerLiter': fuelEfficiencyKmPerLiter,
        'fuelPricePerLiterWon': fuelPricePerLiterWon,
        'riderCount': riderCount,
        'maxSpeedKmh': maxSpeedKmh,
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
      fuelPricePerLiterWon: (json['fuelPricePerLiterWon'] as num?)?.toDouble(),
      riderCount: (json['riderCount'] as num?)?.toInt() ?? 1,
      maxSpeedKmh: (json['maxSpeedKmh'] as num?)?.toDouble(),
    );
  }
}
