import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/active_trip_snapshot.dart';
import '../models/fare_mode.dart';
import '../models/fare_settings.dart';
import '../models/trip_record.dart';
import 'active_trip_repository.dart';
import 'fare_meter.dart';
import 'gps_filter.dart';
import 'location_service.dart';
import 'trip_repository.dart';

/// Redisplays a trip recovered from a saved [ActiveTripSnapshot] after the
/// app was killed mid-trip. It never accepts further updates - the driver
/// can only settle it from here.
class _RecoveredFareMeter implements FareMeter {
  _RecoveredFareMeter({
    required this.fareWon,
    required this.totalDistanceMeters,
  });

  @override
  final int fareWon;

  @override
  final double totalDistanceMeters;

  @override
  void start(DateTime now) {}

  @override
  void update({
    required double distanceDeltaMeters,
    required double slowTimeDeltaSeconds,
    required DateTime now,
    bool isSuburban = false,
  }) {}
}

enum MeterState {
  /// No trip running; ready to start.
  idle,

  /// Trip in progress, GPS stream active, fare accumulating.
  running,

  /// Trip ended, final fare is shown, waiting for the settlement button.
  finished,
}

/// Drives one taxi trip end to end: GPS stream -> filtering -> fare
/// accumulation -> settlement -> local trip log.
class MeterController extends ChangeNotifier {
  final TripRepository _tripRepository;
  final ActiveTripRepository _activeTripRepository;

  MeterController({
    TripRepository? tripRepository,
    ActiveTripRepository? activeTripRepository,
  })  : _tripRepository = tripRepository ?? TripRepository(),
        _activeTripRepository = activeTripRepository ?? ActiveTripRepository();

  MeterState state = MeterState.idle;
  FareMode? _mode;
  FareMeter? _meter;
  GpsFilter _gpsFilter = GpsFilter();
  StreamSubscription<Position>? _positionSub;
  Timer? _uiTicker;
  DateTime? _startTime;
  DateTime? _endTime;
  int _tickCount = 0;

  /// Carried alongside [_meter] rather than read back off it, since a
  /// recovered trip's meter is a [_RecoveredFareMeter], not the original
  /// [CarpoolFareMeter].
  double? _fuelEfficiencyKmPerLiter;
  double? _fuelPricePerLiterWon;

  /// The slow-speed threshold the running trip's meter was started with;
  /// mirrors [StandardFareMeter.slowSpeedThresholdMps] since that's not
  /// exposed on the [FareMeter] interface (only [StandardFareMeter] cares
  /// about it — [CarpoolFareMeter] ignores slow-time entirely).
  double _slowSpeedThresholdMps = StandardFareMeter.defaultSlowSpeedThresholdMps;

  /// Instantaneous device-reported speed from the latest GPS fix, for
  /// display only. Not used for fare calculation, so it isn't run through
  /// [GpsFilter] — the driver just wants to see roughly how fast the car is
  /// going right now.
  double _currentSpeedMps = 0;

  /// Highest [_currentSpeedMps] seen so far this trip, for the 최고속도 stat.
  double _maxSpeedMps = 0;

  /// True if the current [MeterState.finished] trip came from a snapshot
  /// saved before the app was killed mid-trip, rather than a normal stop.
  bool recoveredFromCrash = false;

  /// Driver-toggled "시외" (suburban) surcharge, for trips that leave the
  /// licensed service area. Only meaningful for [FareMode.standard] — there
  /// are no surcharges in [FareMode.carpool].
  bool suburbanSurchargeActive = false;

  /// Number of riders to split the finished trip's fare across ("N빵"),
  /// chosen on the settlement screen. Reset to 1 for each new trip.
  int riderCount = 1;

  String? gpsStatusMessage;
  String? errorMessage;

  /// Checks for a trip snapshot saved before the app was killed mid-trip and
  /// surfaces it as a finished-but-unsettled trip so the record isn't lost.
  /// Call once at startup, before any trip is started.
  Future<void> recoverIfAny() async {
    if (state != MeterState.idle) return;
    final snapshot = await _activeTripRepository.load();
    if (snapshot == null) return;
    // Re-check after the await: the driver could have tapped "운행 시작"
    // while this load was in flight, in which case a live trip is now
    // running and must not be clobbered by the stale snapshot.
    if (state != MeterState.idle) return;

    _mode = snapshot.mode;
    _meter = _RecoveredFareMeter(
      fareWon: snapshot.fareWon,
      totalDistanceMeters: snapshot.distanceMeters,
    );
    _fuelEfficiencyKmPerLiter = snapshot.fuelEfficiencyKmPerLiter;
    _fuelPricePerLiterWon = snapshot.fuelPricePerLiterWon;
    _startTime = snapshot.startTime;
    _endTime = snapshot.lastUpdateTime;
    recoveredFromCrash = true;
    state = MeterState.finished;
    notifyListeners();
  }

  FareMode? get mode => _mode;
  double get distanceMeters => _meter?.totalDistanceMeters ?? 0;
  int get fareWon => _meter?.fareWon ?? 0;

  /// Per-rider share of [fareWon] ("N빵"), rounded up to the nearest 100 won.
  /// With a single rider there's nothing to split, so it's the exact fare.
  int get amountPerPersonWon =>
      riderCount <= 1 ? fareWon : (fareWon / riderCount / 100).ceil() * 100;

  /// Instantaneous current speed (km/h), for display during a running trip.
  /// Zero when idle/finished or before the first GPS fix arrives.
  double get currentSpeedKmh => _currentSpeedMps * 3600 / 1000;

  /// Highest instantaneous speed reached so far this trip.
  double get maxSpeedKmh => _maxSpeedMps * 3600 / 1000;

  /// 표정속도 (average operating speed): total distance divided by total
  /// elapsed time, including any stopped time. Zero for a zero-duration
  /// trip rather than dividing by zero.
  double get averageSpeedKmh {
    final hours = elapsed.inMilliseconds / 1000 / 3600;
    return hours > 0 ? (distanceMeters / 1000) / hours : 0;
  }

  Duration get elapsed {
    if (_startTime == null) return Duration.zero;
    final end = _endTime ?? DateTime.now();
    return end.difference(_startTime!);
  }

  /// Toggled by the driver during a running standard-mode trip to mark the
  /// current (and following) interval as driven outside the service area.
  void setSuburbanSurcharge(bool active) {
    if (state != MeterState.running) return;
    suburbanSurchargeActive = active;
    notifyListeners();
  }

  /// Sets how many riders to split the finished trip's fare across.
  /// Clamped to a sensible 1-8 range for a taxi.
  void setRiderCount(int count) {
    if (state != MeterState.finished) return;
    riderCount = count.clamp(1, 8);
    notifyListeners();
  }

  Future<void> startTrip(FareSettings settings) async {
    errorMessage = null;
    final err = await LocationService.ensureReady();
    if (err != null) {
      errorMessage = err;
      notifyListeners();
      return;
    }

    _mode = settings.mode;
    final isCarpool = settings.mode == FareMode.carpool;
    _fuelEfficiencyKmPerLiter =
        isCarpool ? settings.fuelEfficiencyKmPerLiter : null;
    _fuelPricePerLiterWon = isCarpool ? settings.fuelPricePerLiterWon : null;
    if (settings.mode == FareMode.safeDriving) {
      _meter = NoFareMeter();
      _slowSpeedThresholdMps = StandardFareMeter.defaultSlowSpeedThresholdMps;
    } else if (isCarpool) {
      _meter = CarpoolFareMeter(
        fuelEfficiencyKmPerLiter: settings.fuelEfficiencyKmPerLiter,
        fuelPricePerLiterWon: settings.fuelPricePerLiterWon,
      );
      _slowSpeedThresholdMps = StandardFareMeter.defaultSlowSpeedThresholdMps;
    } else if (settings.useCustomStandardRates) {
      _meter = StandardFareMeter(
        baseFareWon: settings.standardBaseFareWon.round(),
        baseDistanceMeters: settings.standardBaseDistanceMeters,
        distancePulseMeters: settings.standardDistancePulseMeters,
        distancePulseWon: settings.standardDistancePulseWon.round(),
        slowSpeedThresholdMps:
            settings.standardSlowSpeedThresholdKmh * 1000 / 3600,
        timePulseSeconds: settings.standardTimePulseSeconds,
      );
      _slowSpeedThresholdMps =
          settings.standardSlowSpeedThresholdKmh * 1000 / 3600;
    } else {
      _meter = StandardFareMeter();
      _slowSpeedThresholdMps = StandardFareMeter.defaultSlowSpeedThresholdMps;
    }
    _gpsFilter = GpsFilter();
    _startTime = DateTime.now();
    _endTime = null;
    _tickCount = 0;
    _currentSpeedMps = 0;
    _maxSpeedMps = 0;
    suburbanSurchargeActive = false;
    recoveredFromCrash = false;
    _meter!.start(_startTime!);
    gpsStatusMessage = null;
    state = MeterState.running;
    notifyListeners();
    unawaited(WakelockPlus.enable());
    unawaited(_persistActiveTripSnapshot());

    _positionSub = LocationService.positionStream().listen(
      _onPosition,
      onError: (Object e) {
        gpsStatusMessage = 'GPS 오류: $e';
        notifyListeners();
      },
    );

    // Ticks the UI (elapsed time) even between GPS fixes, and periodically
    // persists a snapshot so an unsettled trip survives the app being
    // killed mid-trip.
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
      _tickCount++;
      if (_tickCount % 10 == 0) {
        unawaited(_persistActiveTripSnapshot());
      }
    });
  }

  Future<void> _persistActiveTripSnapshot() async {
    // Safe-driving trips aren't billed or settled, so there's nothing worth
    // recovering after a crash.
    if (_mode == null ||
        _mode == FareMode.safeDriving ||
        _startTime == null ||
        _meter == null) {
      return;
    }
    await _activeTripRepository.save(ActiveTripSnapshot(
      mode: _mode!,
      startTime: _startTime!,
      lastUpdateTime: DateTime.now(),
      distanceMeters: _meter!.totalDistanceMeters,
      fareWon: _meter!.fareWon,
      fuelEfficiencyKmPerLiter: _fuelEfficiencyKmPerLiter,
      fuelPricePerLiterWon: _fuelPricePerLiterWon,
    ));
  }

  void _onPosition(Position position) {
    // Instantaneous display-only speed, tracked regardless of whether the
    // fix is accepted for fare billing purposes.
    _currentSpeedMps = position.speed > 0 ? position.speed : 0;
    if (_currentSpeedMps > _maxSpeedMps) _maxSpeedMps = _currentSpeedMps;

    final fix = _gpsFilter.process(position);
    if (!fix.accepted) {
      gpsStatusMessage = fix.rejectReason;
      notifyListeners();
      return;
    }
    gpsStatusMessage = null;

    final slowSeconds = fix.speedMps < _slowSpeedThresholdMps
        ? fix.timeDelta.inMilliseconds / 1000
        : 0.0;

    _meter!.update(
      distanceDeltaMeters: fix.distanceDeltaMeters,
      slowTimeDeltaSeconds: slowSeconds,
      now: position.timestamp,
      isSuburban: suburbanSurchargeActive,
    );
    notifyListeners();
  }

  Future<void> stopTrip() async {
    if (state != MeterState.running) return;
    _endTime = DateTime.now();
    await _positionSub?.cancel();
    _positionSub = null;
    _uiTicker?.cancel();
    _uiTicker = null;
    _currentSpeedMps = 0;
    unawaited(WakelockPlus.disable());

    // Nothing to settle in safe-driving mode: skip the fare/finished screen
    // and go straight back to idle.
    if (_mode == FareMode.safeDriving) {
      _reset();
      return;
    }

    state = MeterState.finished;
    notifyListeners();
    unawaited(_persistActiveTripSnapshot());
  }

  /// Writes the finished trip to the local log and returns to idle.
  Future<void> completeSettlement() async {
    if (state != MeterState.finished ||
        _mode == null ||
        _startTime == null ||
        _endTime == null ||
        _meter == null) {
      return;
    }

    final record = TripRecord(
      id: _startTime!.microsecondsSinceEpoch.toString(),
      mode: _mode!,
      startTime: _startTime!,
      endTime: _endTime!,
      distanceMeters: _meter!.totalDistanceMeters,
      fareWon: _meter!.fareWon,
      fuelEfficiencyKmPerLiter: _fuelEfficiencyKmPerLiter,
      fuelPricePerLiterWon: _fuelPricePerLiterWon,
      riderCount: riderCount,
    );

    // Clear in-memory state synchronously, before the async writes below,
    // so a snapshot-persist call still in flight from the ticker/stopTrip
    // sees the cleared fields and no-ops instead of racing
    // _activeTripRepository.clear() and resurrecting a settled trip.
    _reset();

    await _tripRepository.add(record);
    await _activeTripRepository.clear();
  }

  void _reset() {
    _mode = null;
    _meter = null;
    _fuelEfficiencyKmPerLiter = null;
    _fuelPricePerLiterWon = null;
    _startTime = null;
    _endTime = null;
    _maxSpeedMps = 0;
    riderCount = 1;
    recoveredFromCrash = false;
    gpsStatusMessage = null;
    errorMessage = null;
    state = MeterState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _uiTicker?.cancel();
    if (state == MeterState.running) {
      unawaited(WakelockPlus.disable());
    }
    super.dispose();
  }
}
