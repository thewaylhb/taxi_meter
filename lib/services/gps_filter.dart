import 'package:geolocator/geolocator.dart';

/// Result of running a raw [Position] fix through [GpsFilter].
class FilteredFix {
  /// True if this fix was usable (even if it contributed zero distance
  /// because it was judged to be stationary jitter).
  final bool accepted;

  /// Reason the fix was rejected, for surfacing a GPS-quality hint in the UI.
  final String? rejectReason;

  /// Extra distance to add to the trip total, in meters. Zero for rejected
  /// fixes and for accepted fixes that only moved by noise-level jitter.
  final double distanceDeltaMeters;

  /// Wall-clock time elapsed since the previous *accepted* fix. Used to
  /// accrue the time-based fare component even while the position itself
  /// isn't moving (e.g. stopped in traffic).
  final Duration timeDelta;

  /// Effective speed for this interval, derived from filtered distance/time
  /// rather than the device-reported speed field (which is noisy at low
  /// speed on many phones).
  final double speedMps;

  const FilteredFix({
    required this.accepted,
    this.rejectReason,
    this.distanceDeltaMeters = 0,
    this.timeDelta = Duration.zero,
    this.speedMps = 0,
  });
}

/// Cleans up raw GPS fixes before they reach the fare meter.
///
/// Consumer-grade GPS has three failure modes that would otherwise directly
/// translate into overcharging a passenger:
///
/// 1. **Low-accuracy fixes** (urban canyon, tunnels, indoors) can report a
///    location tens/hundreds of meters from the true position.
/// 2. **Jumps**: an isolated bad fix makes it look like the car teleported,
///    which would register as an implausibly high speed burst.
/// 3. **Jitter while stationary**: even with good accuracy, a parked/stopped
///    phone's reported position wobbles a few meters back and forth, which
///    would otherwise accumulate into fake distance over a long stop.
///
/// The filter rejects (1) and (2) outright, and debounces (3) by only
/// advancing its position "anchor" once movement clears a noise threshold.
class GpsFilter {
  /// Fixes reported with worse accuracy than this (meters) are dropped.
  static const double maxAccuracyMeters = 25.0;

  /// Implied speed above this (m/s, ~162 km/h) is treated as a GPS jump
  /// rather than real motion, since it exceeds any plausible taxi speed.
  static const double maxPlausibleSpeedMps = 45.0;

  /// Movement smaller than this (meters) since the last anchor is treated as
  /// GPS jitter, not real motion. Typical smartphone GPS noise is a few
  /// meters even when stationary.
  static const double minMovementMeters = 5.0;

  Position? _anchor;
  DateTime? _lastFixTime;

  /// Feed a raw position fix and get back the filtered contribution.
  FilteredFix process(Position position) {
    final now = position.timestamp;

    if (position.accuracy > maxAccuracyMeters) {
      return const FilteredFix(
        accepted: false,
        rejectReason: 'GPS 정확도 낮음',
      );
    }

    if (_anchor == null || _lastFixTime == null) {
      _anchor = position;
      _lastFixTime = now;
      return const FilteredFix(accepted: true);
    }

    final timeDelta = now.difference(_lastFixTime!);
    if (timeDelta.inMilliseconds <= 0) {
      return const FilteredFix(accepted: false, rejectReason: '중복 fix');
    }

    final rawDistance = Geolocator.distanceBetween(
      _anchor!.latitude,
      _anchor!.longitude,
      position.latitude,
      position.longitude,
    );
    final impliedSpeed = rawDistance / (timeDelta.inMilliseconds / 1000);

    if (impliedSpeed > maxPlausibleSpeedMps) {
      // Likely a GPS jump. Reject the fix but keep the old anchor and clock
      // so the next fix is judged against the last known-good position.
      return const FilteredFix(accepted: false, rejectReason: 'GPS 튐 감지');
    }

    _lastFixTime = now;

    if (rawDistance < minMovementMeters) {
      // Stationary jitter: don't move the anchor, don't add distance, but
      // do report elapsed time so slow/stopped time-fare can still accrue.
      return FilteredFix(
        accepted: true,
        distanceDeltaMeters: 0,
        timeDelta: timeDelta,
        speedMps: 0,
      );
    }

    _anchor = position;
    final speed = rawDistance / (timeDelta.inMilliseconds / 1000);
    return FilteredFix(
      accepted: true,
      distanceDeltaMeters: rawDistance,
      timeDelta: timeDelta,
      speedMps: speed,
    );
  }

  void reset() {
    _anchor = null;
    _lastFixTime = null;
  }
}
