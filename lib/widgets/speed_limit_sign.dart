import 'package:flutter/material.dart';

import '../services/road_match_service.dart';

/// Fixed alert-style colors, deliberately not theme-dependent (like traffic
/// lights) so the driver reads the same blue/green/yellow/orange/red
/// meaning regardless of light/dark mode.
class SpeedBand {
  final Color background;
  final Color foreground;

  const SpeedBand(this.background, this.foreground);

  static const blue = SpeedBand(Color(0xFF1976D2), Colors.white);
  static const green = SpeedBand(Color(0xFF2E7D32), Colors.white);
  static const yellow = SpeedBand(Color(0xFFF9A825), Colors.black);
  static const orange = SpeedBand(Color(0xFFEF6C00), Colors.white);
  static const red = SpeedBand(Color(0xFFD32F2F), Colors.white);
}

/// Buckets how far [currentKmh] is from [limitKmh] into a driver-facing
/// alert color: comfortably under the limit reads blue, right at it reads
/// green, then yellow/orange/red as the overage grows.
SpeedBand speedBandFor(double currentKmh, int limitKmh) {
  final over = currentKmh - limitKmh;
  if (over > 20) return SpeedBand.red;
  if (over > 10) return SpeedBand.orange;
  if (over > 0) return SpeedBand.yellow;
  if (over >= -10) return SpeedBand.green;
  return SpeedBand.blue;
}

/// Circular speed-limit sign shown under the "운행 중" badge, the way
/// turn-by-turn nav apps overlay the current road's speed limit near the
/// driver's own speed. Colored by [speedBandFor] so the limit and the
/// current speed read together at a glance. Hidden while no limit is known.
class SpeedLimitSign extends StatelessWidget {
  final RoadMatchService roadMatchService;
  final double currentSpeedKmh;

  const SpeedLimitSign({
    super.key,
    required this.roadMatchService,
    required this.currentSpeedKmh,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: roadMatchService,
      builder: (context, _) {
        final match = roadMatchService.current;
        if (match == null || match.maxSpeedKmh <= 0) {
          return const SizedBox.shrink();
        }
        final band = speedBandFor(currentSpeedKmh, match.maxSpeedKmh);
        return Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: band.background,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Text(
            '${match.maxSpeedKmh}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: band.foreground,
            ),
          ),
        );
      },
    );
  }
}
