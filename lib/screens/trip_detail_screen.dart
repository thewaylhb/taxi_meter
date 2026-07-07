import 'package:flutter/material.dart';

import '../models/fare_mode.dart';
import '../models/trip_record.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class TripDetailScreen extends StatelessWidget {
  final TripRecord record;

  const TripDetailScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('운행 상세')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Text(
                  formatWon(record.fareWon),
                  style: fareTextStyle(context, fontSize: 40),
                ),
                const SizedBox(height: 4),
                Text(record.mode.label),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          _row('모드', record.mode.label),
          _row('시작 시각', formatDateTime(record.startTime)),
          _row('종료 시각', formatDateTime(record.endTime)),
          _row('운행 시간', formatDuration(record.duration)),
          _row('이동 거리', formatDistanceKm(record.distanceMeters)),
          _row('표정속도', formatSpeedKmh(record.averageSpeedKmh, decimals: 1)),
          _row(
            '최고속도',
            record.maxSpeedKmh != null
                ? formatSpeedKmh(record.maxSpeedKmh!, decimals: 1)
                : '-',
          ),
          if (record.mode == FareMode.carpool) ...[
            const Divider(),
            _row(
              '연비',
              record.fuelEfficiencyKmPerLiter != null
                  ? '${record.fuelEfficiencyKmPerLiter!.toStringAsFixed(1)} km/L'
                  : '-',
            ),
            _row(
              '유가',
              record.fuelPricePerLiterWon != null
                  ? '${formatWon(record.fuelPricePerLiterWon!.round())}/L'
                  : '-',
            ),
          ],
          if (record.riderCount > 1) ...[
            const Divider(),
            _row('인원수', '${record.riderCount}명'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('1인당 금액', style: TextStyle(color: Colors.grey)),
                  Text(
                    formatWon(record.amountPerPersonWon),
                    style: fareTextStyle(context, fontSize: 18),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
