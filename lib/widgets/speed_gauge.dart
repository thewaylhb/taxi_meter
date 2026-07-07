import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'speed_limit_sign.dart' show SpeedBand, speedBandFor;

const double _gaugeWidth = 200;
const double _gaugeHeight = 150;
const double _strokeWidth = 16;
const double _centerY = 110;

/// Half-circle speedometer for 안전 주행 모드: current speed sits in the
/// center, framed by an upward-arcing track. The track fills and recolors
/// together as speed changes (see [speedBandFor]) — comfortably under the
/// limit is blue/green, over it moves through yellow/orange/red. The
/// road's speed limit itself is fixed at the 2/3 point of the arc (like a
/// nav app's speed dial scaled around the posted limit), so the gauge's
/// full-scale reading is `limit * 1.5`. Falls back to a neutral gray fill
/// on a fixed 0-140 scale when no limit is known yet.
class SpeedGauge extends StatelessWidget {
  final double currentSpeedKmh;
  final int? limitKmh;

  const SpeedGauge({super.key, required this.currentSpeedKmh, this.limitKmh});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLimit = limitKmh != null && limitKmh! > 0;
    final band = hasLimit
        ? speedBandFor(currentSpeedKmh, limitKmh!)
        : const SpeedBand(Color(0xFF9E9E9E), Colors.white);
    final gaugeMax = hasLimit ? limitKmh! * 1.5 : 140.0;
    final fraction = (currentSpeedKmh / gaugeMax).clamp(0.0, 1.0);

    return SizedBox(
      width: _gaugeWidth,
      height: _gaugeHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(_gaugeWidth, _gaugeHeight),
            painter: _SpeedGaugePainter(
              fraction: fraction,
              trackColor: theme.colorScheme.surfaceContainerHighest,
              progressColor: band.background,
              showLimitTick: hasLimit,
            ),
          ),
          Positioned(
            top: _centerY - 70,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentSpeedKmh.round().toString(),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  'km/h',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedGaugePainter extends CustomPainter {
  final double fraction;
  final Color trackColor;
  final Color progressColor;
  final bool showLimitTick;

  _SpeedGaugePainter({
    required this.fraction,
    required this.trackColor,
    required this.progressColor,
    required this.showLimitTick,
  });

  // Dome shape: starts at 9 o'clock (pi), sweeps clockwise through 12
  // o'clock (top) to 3 o'clock (2*pi) — "위로 반원" wrapped over the top.
  static const double _start = math.pi;
  static const double _sweep = math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (size.width - _strokeWidth) / 2;
    final center = Offset(size.width / 2, _centerY);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, trackPaint);

    if (showLimitTick) {
      final tickAngle = _start + _sweep * (2 / 3);
      final dir = Offset(math.cos(tickAngle), math.sin(tickAngle));
      final tickPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        center + dir * (radius - _strokeWidth / 2 - 5),
        center + dir * (radius + _strokeWidth / 2 + 5),
        tickPaint,
      );
    }

    if (fraction > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, _start, _sweep * fraction, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedGaugePainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.showLimitTick != showLimitTick;
  }
}
