import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fare_mode.dart';
import '../models/fare_settings.dart';

/// Holds the app's fare settings in memory and mirrors them to local
/// on-device storage. No login, no server — everything lives in
/// SharedPreferences.
class SettingsController extends ChangeNotifier {
  static const _keyMode = 'fare_mode';
  static const _keyThemeMode = 'theme_mode';
  static const _keyUseCustomStandardRates = 'use_custom_standard_rates';
  static const _keyStandardBaseFareWon = 'standard_base_fare_won';
  static const _keyStandardBaseDistanceMeters =
      'standard_base_distance_meters';
  static const _keyStandardDistancePulseMeters =
      'standard_distance_pulse_meters';
  static const _keyStandardDistancePulseWon = 'standard_distance_pulse_won';
  static const _keyStandardSlowSpeedThresholdKmh =
      'standard_slow_speed_threshold_kmh';
  static const _keyStandardTimePulseSeconds = 'standard_time_pulse_seconds';
  static const _keyCarpoolBaseFareWon = 'carpool_base_fare_won';
  static const _keyFuelEfficiency = 'fuel_efficiency_km_per_liter';
  static const _keyFuelPrice = 'fuel_price_per_liter_won';

  FareSettings _settings = FareSettings();
  FareSettings get settings => _settings;

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = FareSettings();
    final modeName = prefs.getString(_keyMode);
    _themeMode = ThemeMode.values.firstWhere(
      (e) => e.name == prefs.getString(_keyThemeMode),
      orElse: () => ThemeMode.light,
    );
    _settings = FareSettings(
      mode: FareMode.values.firstWhere(
        (e) => e.name == modeName,
        orElse: () => FareMode.standard,
      ),
      useCustomStandardRates:
          prefs.getBool(_keyUseCustomStandardRates) ?? false,
      standardBaseFareWon: prefs.getDouble(_keyStandardBaseFareWon) ??
          defaults.standardBaseFareWon,
      standardBaseDistanceMeters:
          prefs.getDouble(_keyStandardBaseDistanceMeters) ??
              defaults.standardBaseDistanceMeters,
      standardDistancePulseMeters:
          prefs.getDouble(_keyStandardDistancePulseMeters) ??
              defaults.standardDistancePulseMeters,
      standardDistancePulseWon:
          prefs.getDouble(_keyStandardDistancePulseWon) ??
              defaults.standardDistancePulseWon,
      standardSlowSpeedThresholdKmh:
          prefs.getDouble(_keyStandardSlowSpeedThresholdKmh) ??
              defaults.standardSlowSpeedThresholdKmh,
      standardTimePulseSeconds:
          prefs.getDouble(_keyStandardTimePulseSeconds) ??
              defaults.standardTimePulseSeconds,
      carpoolBaseFareWon:
          prefs.getDouble(_keyCarpoolBaseFareWon) ?? defaults.carpoolBaseFareWon,
      fuelEfficiencyKmPerLiter:
          prefs.getDouble(_keyFuelEfficiency) ?? defaults.fuelEfficiencyKmPerLiter,
      fuelPricePerLiterWon:
          prefs.getDouble(_keyFuelPrice) ?? defaults.fuelPricePerLiterWon,
    );
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, mode.name);
  }

  Future<void> setMode(FareMode mode) async {
    _settings = _settings.copyWith(mode: mode);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMode, mode.name);
  }

  Future<void> setUseCustomStandardRates(bool useCustom) async {
    _settings = _settings.copyWith(useCustomStandardRates: useCustom);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseCustomStandardRates, useCustom);
  }

  Future<void> setStandardBaseFareWon(double won) async {
    _settings = _settings.copyWith(standardBaseFareWon: won);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyStandardBaseFareWon, won);
  }

  Future<void> setStandardBaseDistanceMeters(double meters) async {
    _settings = _settings.copyWith(standardBaseDistanceMeters: meters);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyStandardBaseDistanceMeters, meters);
  }

  Future<void> setStandardDistancePulseMeters(double meters) async {
    _settings = _settings.copyWith(standardDistancePulseMeters: meters);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyStandardDistancePulseMeters, meters);
  }

  Future<void> setStandardDistancePulseWon(double won) async {
    _settings = _settings.copyWith(standardDistancePulseWon: won);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyStandardDistancePulseWon, won);
  }

  Future<void> setStandardSlowSpeedThresholdKmh(double kmh) async {
    _settings = _settings.copyWith(standardSlowSpeedThresholdKmh: kmh);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyStandardSlowSpeedThresholdKmh, kmh);
  }

  Future<void> setStandardTimePulseSeconds(double seconds) async {
    _settings = _settings.copyWith(standardTimePulseSeconds: seconds);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyStandardTimePulseSeconds, seconds);
  }

  Future<void> setCarpoolBaseFareWon(double won) async {
    _settings = _settings.copyWith(carpoolBaseFareWon: won);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyCarpoolBaseFareWon, won);
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
