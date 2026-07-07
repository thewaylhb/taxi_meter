import 'package:flutter/material.dart';

import '../models/fare_mode.dart';
import '../models/fare_settings.dart';
import '../services/settings_controller.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsController settingsController;

  const SettingsScreen({super.key, required this.settingsController});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseFareController;
  late final TextEditingController _baseDistanceController;
  late final TextEditingController _distancePulseMetersController;
  late final TextEditingController _distancePulseWonController;
  late final TextEditingController _slowSpeedThresholdController;
  late final TextEditingController _timePulseSecondsController;
  late final TextEditingController _carpoolBaseFareController;
  late final TextEditingController _efficiencyController;
  late final TextEditingController _fuelPriceController;

  @override
  void initState() {
    super.initState();
    widget.settingsController.addListener(_onChange);
    final settings = widget.settingsController.settings;
    _baseFareController = TextEditingController(
      text: settings.standardBaseFareWon.toStringAsFixed(0),
    );
    _baseDistanceController = TextEditingController(
      text: settings.standardBaseDistanceMeters.toStringAsFixed(0),
    );
    _distancePulseMetersController = TextEditingController(
      text: settings.standardDistancePulseMeters.toStringAsFixed(0),
    );
    _distancePulseWonController = TextEditingController(
      text: settings.standardDistancePulseWon.toStringAsFixed(0),
    );
    _slowSpeedThresholdController = TextEditingController(
      text: settings.standardSlowSpeedThresholdKmh.toStringAsFixed(1),
    );
    _timePulseSecondsController = TextEditingController(
      text: settings.standardTimePulseSeconds.toStringAsFixed(0),
    );
    _carpoolBaseFareController = TextEditingController(
      text: settings.carpoolBaseFareWon.toStringAsFixed(0),
    );
    _efficiencyController = TextEditingController(
      text: settings.fuelEfficiencyKmPerLiter.toStringAsFixed(1),
    );
    _fuelPriceController = TextEditingController(
      text: settings.fuelPricePerLiterWon.toStringAsFixed(0),
    );
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    widget.settingsController.removeListener(_onChange);
    _baseFareController.dispose();
    _baseDistanceController.dispose();
    _distancePulseMetersController.dispose();
    _distancePulseWonController.dispose();
    _slowSpeedThresholdController.dispose();
    _timePulseSecondsController.dispose();
    _carpoolBaseFareController.dispose();
    _efficiencyController.dispose();
    _fuelPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settingsController.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('요금제 설정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('화면 모드', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          RadioGroup<ThemeMode>(
            groupValue: widget.settingsController.themeMode,
            onChanged: (value) {
              if (value != null) widget.settingsController.setThemeMode(value);
            },
            child: const Column(
              children: [
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  title: Text('주간 모드'),
                  subtitle: Text('밝은 화면'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  title: Text('야간 모드'),
                  subtitle: Text('눈부심 감소 및 배터리 절약'),
                ),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  title: Text('시스템 설정에 따름'),
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          Text('요금 모드', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          RadioGroup<FareMode>(
            groupValue: settings.mode,
            onChanged: (value) {
              if (value != null) widget.settingsController.setMode(value);
            },
            child: Column(
              children: [
                for (final mode in FareMode.values)
                  RadioListTile<FareMode>(
                    value: mode,
                    title: Text(mode.label),
                    subtitle: switch (dynamicFareModeDescription(mode, settings)) {
                      final desc? => Text(desc),
                      null => null,
                    },
                  ),
              ],
            ),
          ),
          if (settings.mode == FareMode.standard) ...[
            const Divider(height: 32),
            Text('미터기 요금제', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            RadioGroup<bool>(
              groupValue: settings.useCustomStandardRates,
              onChanged: (value) {
                if (value != null) {
                  widget.settingsController.setUseCustomStandardRates(value);
                }
              },
              child: Column(
                children: [
                  RadioListTile<bool>(
                    value: false,
                    title: const Text('서울시 요금제'),
                    subtitle: const Text('서울시 중형택시 기준 요금(고정값) 사용'),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    title: const Text('사용자 설정 요금제'),
                    subtitle: const Text('아래 기본 요금 항목을 직접 입력한 값으로 계산'),
                  ),
                ],
              ),
            ),
            if (settings.useCustomStandardRates) ...[
              const Divider(height: 32),
              _rateField(
                title: '기본요금',
                controller: _baseFareController,
                labelText: '기본요금',
                suffixText: '원',
                onSave: (value) => _saveNumberField(
                  value: value,
                  errorMessage: '올바른 기본요금 값을 입력하세요.',
                  onValid: widget.settingsController.setStandardBaseFareWon,
                ),
              ),
              const Divider(height: 32),
              _rateField(
                title: '기본거리',
                controller: _baseDistanceController,
                labelText: '기본거리',
                suffixText: 'm',
                onSave: (value) => _saveNumberField(
                  value: value,
                  errorMessage: '올바른 기본거리 값을 입력하세요.',
                  onValid:
                      widget.settingsController.setStandardBaseDistanceMeters,
                ),
              ),
              const Divider(height: 32),
              _rateField(
                title: '추가요금 거리 단위',
                controller: _distancePulseMetersController,
                labelText: '추가요금 거리 단위',
                suffixText: 'm',
                onSave: (value) => _saveNumberField(
                  value: value,
                  errorMessage: '올바른 거리 단위 값을 입력하세요.',
                  onValid: widget
                      .settingsController.setStandardDistancePulseMeters,
                ),
              ),
              const Divider(height: 32),
              _rateField(
                title: '추가요금',
                controller: _distancePulseWonController,
                labelText: '추가요금',
                suffixText: '원',
                onSave: (value) => _saveNumberField(
                  value: value,
                  errorMessage: '올바른 추가요금 값을 입력하세요.',
                  onValid:
                      widget.settingsController.setStandardDistancePulseWon,
                ),
              ),
              const Divider(height: 32),
              _rateField(
                title: '저속 기준 속도',
                controller: _slowSpeedThresholdController,
                labelText: '저속 기준 속도',
                suffixText: 'km/h',
                onSave: (value) => _saveNumberField(
                  value: value,
                  errorMessage: '올바른 저속 기준 속도 값을 입력하세요.',
                  onValid: widget
                      .settingsController.setStandardSlowSpeedThresholdKmh,
                ),
              ),
              const Divider(height: 32),
              _rateField(
                title: '저속 추가요금 시간 단위',
                controller: _timePulseSecondsController,
                labelText: '저속 추가요금 시간 단위',
                suffixText: '초',
                onSave: (value) => _saveNumberField(
                  value: value,
                  errorMessage: '올바른 시간 단위 값을 입력하세요.',
                  onValid:
                      widget.settingsController.setStandardTimePulseSeconds,
                ),
              ),
            ],
          ],
          if (settings.mode == FareMode.carpool) ...[
            const Divider(height: 32),
            _rateField(
              title: '기본요금 설정',
              controller: _carpoolBaseFareController,
              labelText: '기본요금',
              suffixText: '원',
              onSave: (value) => _saveNumberField(
                value: value,
                errorMessage: '올바른 기본요금 값을 입력하세요.',
                onValid: widget.settingsController.setCarpoolBaseFareWon,
              ),
            ),
            const Divider(height: 32),
            _rateField(
              title: '차량 연비 설정',
              controller: _efficiencyController,
              labelText: '연비 (km/L)',
              suffixText: 'km/L',
              onSave: (value) => _saveNumberField(
                value: value,
                errorMessage: '올바른 연비 값을 입력하세요.',
                onValid: widget.settingsController.setFuelEfficiency,
              ),
            ),
            const Divider(height: 32),
            _rateField(
              title: '유가 설정',
              controller: _fuelPriceController,
              labelText: '유가 (원/L)',
              suffixText: '원/L',
              onSave: (value) => _saveNumberField(
                value: value,
                errorMessage: '올바른 유가 값을 입력하세요.',
                onValid: widget.settingsController.setFuelPrice,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rateField({
    required String title,
    required TextEditingController controller,
    required String labelText,
    required String suffixText,
    required ValueChanged<String> onSave,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: labelText,
            border: const OutlineInputBorder(),
            suffixText: suffixText,
          ),
          onSubmitted: onSave,
          onEditingComplete: () => onSave(controller.text),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => onSave(controller.text),
            child: const Text('저장'),
          ),
        ),
      ],
    );
  }

  void _saveNumberField({
    required String value,
    required String errorMessage,
    required Future<void> Function(double) onValid,
  }) {
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      return;
    }
    onValid(parsed);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('설정이 저장되었습니다.')),
    );
  }
}
