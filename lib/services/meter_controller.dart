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

  /// True if the current [MeterState.finished] trip came from a snapshot
  /// saved before the app was killed mid-trip, rather than a normal stop.
  bool recoveredFromCrash = false;

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

  Duration get elapsed {
    if (_startTime == null) return Duration.zero;
    final end = _endTime ?? DateTime.now();
    return end.difference(_startTime!);
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
    _meter = isCarpool
        ? CarpoolFareMeter(
            fuelEfficiencyKmPerLiter: settings.fuelEfficiencyKmPerLiter,
            fuelPricePerLiterWon: settings.fuelPricePerLiterWon,
          )
        : StandardFareMeter();
    _gpsFilter = GpsFilter();
    _startTime = DateTime.now();
    _endTime = null;
    _tickCount = 0;
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
    if (_mode == null || _startTime == null || _meter == null) return;
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
    final fix = _gpsFilter.process(position);
    if (!fix.accepted) {
      gpsStatusMessage = fix.rejectReason;
      notifyListeners();
      return;
    }
    gpsStatusMessage = null;

    final slowSeconds = fix.speedMps < StandardFareMeter.slowSpeedThresholdMps
        ? fix.timeDelta.inMilliseconds / 1000
        : 0.0;

    _meter!.update(
      distanceDeltaMeters: fix.distanceDeltaMeters,
      slowTimeDeltaSeconds: slowSeconds,
      now: position.timestamp,
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
    state = MeterState.finished;
    notifyListeners();
    unawaited(WakelockPlus.disable());
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
