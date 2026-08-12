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

  /// Cap on the time-fare-eligible portion of a single interval. A tunnel or
  /// other long GPS blackout can leave many fixes rejected in a row (fixes
  /// keep coming in at a normal cadence, but each one fails the accuracy
  /// check); since we don't advance the clock on a rejected fix, the first
  /// fix accepted afterwards would otherwise carry the *entire* blackout gap
  /// as elapsed time, misattributing it all as slow/stopped time-fare. Real
  /// updates arrive about once a second, so anything beyond a few seconds is
  /// a gap, not a genuine slow interval, and is capped rather than billed.
  static const Duration maxBillableGap = Duration(seconds: 5);

  Position? _anchor;

  /// When the vehicle was at [_anchor]. Tracked separately from
  /// [_lastFixTime] because the anchor deliberately lags behind the fix
  /// stream while movement stays inside the jitter threshold: distance is
  /// always measured from the anchor, so the speed derived from it has to
  /// be measured over the matching span or it comes out inflated by however
  /// many fixes the anchor sat still for.
  DateTime? _anchorTime;
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

    if (_anchor == null || _lastFixTime == null || _anchorTime == null) {
      _anchor = position;
      _anchorTime = now;
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
    // Measured against the anchor's own timestamp, not the previous fix's:
    // both terms then describe the same span, so a crawl that takes several
    // fixes to clear [minMovementMeters] reports its real speed instead of
    // (accumulated distance) / (one fix interval).
    final anchorTimeDelta = now.difference(_anchorTime!);
    final impliedSpeed = rawDistance / (anchorTimeDelta.inMilliseconds / 1000);

    if (impliedSpeed > maxPlausibleSpeedMps) {
      // Likely a GPS jump. Reject the fix but keep the old anchor and clock
      // so the next fix is judged against the last known-good position.
      return const FilteredFix(accepted: false, rejectReason: 'GPS 튐 감지');
    }

    _lastFixTime = now;
    final billableTimeDelta =
        timeDelta > maxBillableGap ? maxBillableGap : timeDelta;

    if (rawDistance < minMovementMeters) {
      // Stationary jitter: don't add distance, but do report elapsed time so
      // slow/stopped time-fare can still accrue.
      //
      // Staying inside the noise radius for longer than [maxBillableGap]
      // means the vehicle is genuinely stopped rather than crawling, so
      // re-anchor here. Otherwise the anchor timestamp would keep aging for
      // the whole stop, and the first fix after pulling away would divide a
      // few meters by minutes of standing time and report a near-zero speed.
      if (anchorTimeDelta > maxBillableGap) {
        _anchor = position;
        _anchorTime = now;
      }
      return FilteredFix(
        accepted: true,
        distanceDeltaMeters: 0,
        timeDelta: billableTimeDelta,
        speedMps: 0,
      );
    }

    _anchor = position;
    _anchorTime = now;
    return FilteredFix(
      accepted: true,
      distanceDeltaMeters: rawDistance,
      timeDelta: billableTimeDelta,
      speedMps: impliedSpeed,
    );
  }

  void reset() {
    _anchor = null;
    _anchorTime = null;
    _lastFixTime = null;
  }
}
