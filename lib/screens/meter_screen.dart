import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../models/fare_mode.dart';
import '../services/fare_meter.dart';
import '../services/meter_controller.dart';
import '../services/road_match_service.dart';
import '../services/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/speed_gauge.dart';
import '../widgets/speed_limit_sign.dart';

class MeterScreen extends StatefulWidget {
  final SettingsController settingsController;
  final MeterController meterController;
  final RoadMatchService roadMatchService;

  const MeterScreen({
    super.key,
    required this.settingsController,
    required this.meterController,
    required this.roadMatchService,
  });

  @override
  State<MeterScreen> createState() => _MeterScreenState();
}

class _MeterScreenState extends State<MeterScreen> {
  MeterController get _meter => widget.meterController;

  @override
  void initState() {
    super.initState();
    _meter.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _meter.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No AppBar here: the bottom nav's "미터기" tab already says what this
      // screen is, and a title bar just steals space from the meter itself.
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
    final settings = widget.settingsController.settings;
    final mode = settings.mode;
    final description = mode == FareMode.standard && settings.useCustomStandardRates
        ? '사용자 설정 요금제'
        : mode.description;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_taxi, size: 96, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(mode.label, style: Theme.of(context).textTheme.titleLarge),
          if (mode != FareMode.safeDriving)
            Text(
              description,
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
    final colors = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final isStandard = _meter.mode == FareMode.standard;
    final nightMultiplier =
        isStandard ? StandardFareMeter.lateNightMultiplier(DateTime.now()) : 1.0;
    final isNight = nightMultiplier > 1.0;
    final hasGpsWarning = _meter.gpsStatusMessage != null;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            // Keep the GPS line and the "운행 중" pill aligned to the same
            // top line regardless of the speed-limit sign's height below
            // it; without this the Row centers the GPS line against the
            // taller [pill + sign] column instead.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasGpsWarning ? Icons.gps_off : Icons.gps_fixed,
                      size: 15,
                      color: hasGpsWarning ? colors.error : colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        hasGpsWarning ? _meter.gpsStatusMessage! : 'GPS 신호',
                        style: TextStyle(
                          fontSize: 13,
                          color: hasGpsWarning ? colors.error : colors.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '운행 중',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SpeedLimitSign(
                    roadMatchService: widget.roadMatchService,
                    currentSpeedKmh: _meter.currentSpeedKmh,
                  ),
                ],
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: _meter.mode == FareMode.safeDriving
                  ? _safeDrivingBody(context)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '현재 요금',
                          style: TextStyle(
                              fontSize: 13, color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 6),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            formatWon(_meter.fareWon),
                            key: ValueKey(_meter.fareWon),
                            style: fareTextStyle(context, fontSize: 54),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            if (isNight)
                              _badge(
                                '심야 +${((nightMultiplier - 1) * 100).round()}%',
                                semantic.nightSurcharge,
                              ),
                            if (_meter.mode == FareMode.carpool)
                              _badge('카풀', semantic.secondaryAccent),
                            if (_meter.suburbanSurchargeActive)
                              _badge(
                                '시외 +${((StandardFareMeter.suburbanSurchargeMultiplier - 1) * 100).round()}%',
                                semantic.secondaryAccent,
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _statGrid(context),
                      ],
                    ),
            ),
          ),
          Row(
            children: [
              if (isStandard) ...[
                Expanded(flex: 5, child: _surchargeToggleButton(context, semantic)),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: isStandard ? 7 : 1,
                child: SizedBox(
                  height: 64,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: semantic.endAction,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _meter.stopTrip(),
                    child: const Text('운행 종료', style: TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _surchargeToggleButton(BuildContext context, AppSemanticColors semantic) {
    final active = _meter.suburbanSurchargeActive;
    return SizedBox(
      height: 64,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(alignment: Alignment.center),
        onPressed: () => _meter.setSuburbanSurcharge(!active),
        child: Text.rich(
          TextSpan(
            text: '시외 할증 ',
            style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.onSurface),
            children: [
              TextSpan(
                text: active ? 'ON' : 'OFF',
                style: TextStyle(
                  color: active
                      ? semantic.secondaryAccent
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _statGrid(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          _statCell(context, '거리', formatDistanceKm(_meter.distanceMeters)),
          _statCell(context, '시간', formatDuration(_meter.elapsed)),
          _statCell(
            context,
            '속도',
            formatSpeedKmh(_meter.currentSpeedKmh),
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _safeDrivingBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListenableBuilder(
          listenable: widget.roadMatchService,
          builder: (context, _) => SpeedGauge(
            currentSpeedKmh: _meter.currentSpeedKmh,
            limitKmh: widget.roadMatchService.current?.maxSpeedKmh,
          ),
        ),
        const SizedBox(height: 24),
        _safeDrivingStatGrid(context),
      ],
    );
  }

  Widget _safeDrivingStatGrid(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          _statCell(context, '주행시간', formatDuration(_meter.elapsed)),
          _statCell(context, '표정속도', formatSpeedKmh(_meter.averageSpeedKmh)),
          _statCell(
            context,
            '최고속도',
            formatSpeedKmh(_meter.maxSpeedKmh),
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _statCell(
    BuildContext context,
    String label,
    String value, {
    bool showDivider = true,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          border: showDivider
              ? Border(right: BorderSide(color: Theme.of(context).dividerColor))
              : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  Widget _buildFinished(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mode = _meter.mode ?? FareMode.standard;
    final amountPerPerson = _meter.amountPerPersonWon;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          if (_meter.recoveredFromCrash)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '앱이 예기치 않게 종료되어 이전 운행 기록을 복구했습니다. 정산을 완료해주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSecondaryContainer),
              ),
            ),
          Text('최종 요금', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            formatWon(_meter.fareWon),
            style: fareTextStyle(context, fontSize: 56),
          ),
          const SizedBox(height: 16),
          Text(mode.label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          _statRow(context, Icons.timer, formatDuration(_meter.elapsed)),
          const SizedBox(height: 8),
          _statRow(context, Icons.route, formatDistanceKm(_meter.distanceMeters)),
          const SizedBox(height: 8),
          _statRow(context, Icons.speed, formatSpeedKmh(_meter.maxSpeedKmh, decimals: 1)),
          if (mode == FareMode.carpool) ...[
            const SizedBox(height: 24),
            _fareBreakdownCard(context),
          ],
          const SizedBox(height: 24),
          _riderSplitCard(context, amountPerPerson),
          const SizedBox(height: 24),
          Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(56, 56),
                  ),
                  onPressed: () => _shareSettlement(context, amountPerPerson),
                  // ios_share (arrow out of a box) renders symmetrically at
                  // this size; Icons.share's glyph ink isn't centered in its
                  // own 24x24 box, so it visibly leans right even though the
                  // button/layout around it is perfectly centered.
                  child: const Icon(Icons.ios_share),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => _meter.completeSettlement(),
                    child: const Text('정산 완료', style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fareBreakdownCard(BuildContext context) {
    final fuelCostWon = _meter.fareWon - CarpoolFareMeter.baseFareWon;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _breakdownRow('주행 거리', formatDistanceKm(_meter.distanceMeters)),
            _breakdownRow('연료비', formatWon(fuelCostWon)),
            _breakdownRow('기본요금', formatWon(CarpoolFareMeter.baseFareWon)),
            const Divider(height: 20),
            _breakdownRow('합계', formatWon(_meter.fareWon), emphasize: true),
          ],
        ),
      ),
    );
  }

  Widget _breakdownRow(String label, String value, {bool emphasize = false}) {
    final style = TextStyle(
      fontWeight: emphasize ? FontWeight.w600 : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _riderSplitCard(BuildContext context, int amountPerPerson) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('인원수'),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _meter.setRiderCount(_meter.riderCount - 1),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${_meter.riderCount}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _meter.setRiderCount(_meter.riderCount + 1),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),
            Text('1인당', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              formatWon(amountPerPerson),
              style: fareTextStyle(context, fontSize: 34),
            ),
            if (_meter.riderCount > 1) ...[
              const SizedBox(height: 4),
              Text(
                '100원 단위 올림',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _shareSettlement(BuildContext context, int amountPerPerson) {
    final mode = _meter.mode ?? FareMode.standard;
    final summary = _meter.riderCount > 1
        ? '${formatDistanceKm(_meter.distanceMeters)} · ${mode.label} · '
            '총 ${formatWon(_meter.fareWon)} · ${_meter.riderCount}인 분할 · '
            '1인당 ${formatWon(amountPerPerson)}'
        : '${formatDistanceKm(_meter.distanceMeters)} · ${mode.label} · '
            '${formatWon(_meter.fareWon)}';
    Clipboard.setData(ClipboardData(text: summary));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('정산 내역이 복사되었습니다.')),
    );
  }

  Widget _statRow(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 18)),
      ],
    );
  }
}
