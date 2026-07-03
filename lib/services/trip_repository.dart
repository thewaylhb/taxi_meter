import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_record.dart';

/// Local-only trip log. Every settled trip is appended here; nothing ever
/// leaves the device.
class TripRepository {
  static const _key = 'trip_records';

  Future<List<TripRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    final records = raw
        .map((s) => TripRecord.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    records.sort((a, b) => b.startTime.compareTo(a.startTime));
    return records;
  }

  Future<void> add(TripRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    final updated = [...raw, jsonEncode(record.toJson())];
    await prefs.setStringList(_key, updated);
  }
}
