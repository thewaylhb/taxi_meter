import 'package:flutter/material.dart';

import '../models/fare_mode.dart';
import '../services/settings_controller.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsController settingsController;

  const SettingsScreen({super.key, required this.settingsController});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _efficiencyController;

  @override
  void initState() {
    super.initState();
    widget.settingsController.addListener(_onChange);
    _efficiencyController = TextEditingController(
      text: widget.settingsController.settings.fuelEfficiencyKmPerLiter
          .toStringAsFixed(1),
    );
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    widget.settingsController.removeListener(_onChange);
    _efficiencyController.dispose();
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
                    subtitle: Text(mode.description),
                  ),
              ],
            ),
          ),
          if (settings.mode == FareMode.carpool) ...[
            const Divider(height: 32),
            Text('차량 연비 설정', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('연료 가격은 리터당 2,000원 고정으로 계산됩니다.'),
            const SizedBox(height: 12),
            TextField(
              controller: _efficiencyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '연비 (km/L)',
                border: OutlineInputBorder(),
                suffixText: 'km/L',
              ),
              onSubmitted: _saveEfficiency,
              onEditingComplete: () => _saveEfficiency(_efficiencyController.text),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _saveEfficiency(_efficiencyController.text),
                child: const Text('저장'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _saveEfficiency(String value) {
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 연비 값을 입력하세요.')),
      );
      return;
    }
    widget.settingsController.setFuelEfficiency(parsed);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('연비 설정이 저장되었습니다.')),
    );
  }
}
