import 'package:flutter/material.dart';

import '../models/fare_mode.dart';
import '../services/meter_controller.dart';
import '../services/settings_controller.dart';
import '../services/trip_repository.dart';
import '../utils/formatters.dart';

class MeterScreen extends StatefulWidget {
  final SettingsController settingsController;
  final TripRepository tripRepository;

  const MeterScreen({
    super.key,
    required this.settingsController,
    required this.tripRepository,
  });

  @override
  State<MeterScreen> createState() => _MeterScreenState();
}

class _MeterScreenState extends State<MeterScreen> {
  late final MeterController _meter =
      MeterController(tripRepository: widget.tripRepository);

  @override
  void initState() {
    super.initState();
    _meter.addListener(_onChange);
    _meter.recoverIfAny();
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _meter.removeListener(_onChange);
    _meter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('택시 미터기')),
      body: SafeArea(
        child: switch (_meter.state) {
          MeterState.idle => _buildIdle(context),
          MeterState.running => _buildRunning(context),
          MeterState.finished => _buildFinished(context),
        },
      ),
    );
  }

  Widget _buildIdle(BuildContext context) {
    final mode = widget.settingsController.settings.mode;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_taxi, size: 96, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(mode.label, style: Theme.of(context).textTheme.titleLarge),
          Text(
            mode.description,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          if (_meter.errorMessage != null) ...[
            Text(
              _meter.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              onPressed: () => _meter.startTrip(widget.settingsController.settings),
              child: const Text('운행 시작', style: TextStyle(fontSize: 20)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunning(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (_meter.gpsStatusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 16),
              color: Colors.amber.shade100,
              child: Text(
                '⚠ ${_meter.gpsStatusMessage}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatWon(_meter.fareWon),
                    style: const TextStyle(fontSize: 56, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  _statRow(Icons.timer, formatDuration(_meter.elapsed)),
                  const SizedBox(height: 8),
                  _statRow(Icons.route, formatDistanceKm(_meter.distanceMeters)),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => _meter.stopTrip(),
              child: const Text('운행 종료', style: TextStyle(fontSize: 20)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinished(BuildContext context) {
    final mode = _meter.mode ?? FareMode.standard;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (_meter.recoveredFromCrash)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 16),
              color: Colors.amber.shade100,
              child: const Text(
                '앱이 예기치 않게 종료되어 이전 운행 기록을 복구했습니다. 정산을 완료해주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black87),
              ),
            ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('최종 요금', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    formatWon(_meter.fareWon),
                    style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  Text(mode.label, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  _statRow(Icons.timer, formatDuration(_meter.elapsed)),
                  const SizedBox(height: 8),
                  _statRow(Icons.route, formatDistanceKm(_meter.distanceMeters)),
                ],
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              onPressed: () => _meter.completeSettlement(),
              child: const Text('정산 완료', style: TextStyle(fontSize: 20)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 18)),
      ],
    );
  }
}
