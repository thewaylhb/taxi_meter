import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fare_mode.dart';
import '../models/fare_settings.dart';

/// Holds the app's fare settings in memory and mirrors them to local
/// on-device storage. No login, no server — everything lives in
/// SharedPreferences.
class SettingsController extends ChangeNotifier {
  static const _keyMode = 'fare_mode';
  static const _keyFuelEfficiency = 'fuel_efficiency_km_per_liter';
  static const _keyFuelPrice = 'fuel_price_per_liter_won';

  FareSettings _settings = FareSettings();
  FareSettings get settings => _settings;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString(_keyMode);
    final efficiency = prefs.getDouble(_keyFuelEfficiency);
    final fuelPrice = prefs.getDouble(_keyFuelPrice);
    _settings = FareSettings(
      mode: FareMode.values.firstWhere(
        (e) => e.name == modeName,
        orElse: () => FareMode.standard,
      ),
      fuelEfficiencyKmPerLiter: efficiency ?? 12.0,
      fuelPricePerLiterWon: fuelPrice ?? 2000.0,
    );
    notifyListeners();
  }

  Future<void> setMode(FareMode mode) async {
    _settings = _settings.copyWith(mode: mode);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, mode.name);
  }

  Future<void> setFuelEfficiency(double kmPerLiter) async {
    _settings = _settings.copyWith(fuelEfficiencyKmPerLiter: kmPerLiter);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFuelEfficiency, kmPerLiter);
  }

  Future<void> setFuelPrice(double wonPerLiter) async {
    _settings = _settings.copyWith(fuelPricePerLiterWon: wonPerLiter);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFuelPrice, wonPerLiter);
  }
}
