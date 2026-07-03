import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/fare_mode.dart';
import '../models/fare_settings.dart';
import '../models/trip_record.dart';
import 'fare_meter.dart';
import 'gps_filter.dart';
import 'location_service.dart';
import 'trip_repository.dart';

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

  MeterController({TripRepository? tripRepository})
      : _tripRepository = tripRepository ?? TripRepository();

  MeterState state = MeterState.idle;
  FareMode? _mode;
  FareMeter? _meter;
  GpsFilter _gpsFilter = GpsFilter();
  StreamSubscription<Position>? _positionSub;
  Timer? _uiTicker;
  DateTime? _startTime;
  DateTime? _endTime;

  String? gpsStatusMessage;
  String? errorMessage;

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
    _meter = settings.mode == FareMode.standard
        ? StandardFareMeter()
        : CarpoolFareMeter(
            fuelEfficiencyKmPerLiter: settings.fuelEfficiencyKmPerLiter,
          );
    _gpsFilter = GpsFilter();
    _startTime = DateTime.now();
    _endTime = null;
    _meter!.start(_startTime!);
    gpsStatusMessage = null;
    state = MeterState.running;
    notifyListeners();

    _positionSub = LocationService.positionStream().listen(
      _onPosition,
      onError: (Object e) {
        gpsStatusMessage = 'GPS 오류: $e';
        notifyListeners();
      },
    );

    // Ticks the UI (elapsed time) even between GPS fixes.
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
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
      fuelEfficiencyKmPerLiter: _mode == FareMode.carpool
          ? (_meter as CarpoolFareMeter).fuelEfficiencyKmPerLiter
          : null,
    );
    await _tripRepository.add(record);
    _reset();
  }

  void _reset() {
    _mode = null;
    _meter = null;
    _startTime = null;
    _endTime = null;
    gpsStatusMessage = null;
    errorMessage = null;
    state = MeterState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _uiTicker?.cancel();
    super.dispose();
  }
}
