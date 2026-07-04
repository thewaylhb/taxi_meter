import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/active_trip_snapshot.dart';

/// Local-only store for the single in-progress trip snapshot. Separate from
/// [TripRepository]'s settled trip log, and cleared as soon as a trip is
/// settled.
class ActiveTripRepository {
  static const _key = 'active_trip_snapshot';

  Future<void> save(ActiveTripSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(snapshot.toJson()));
  }

  Future<ActiveTripSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return ActiveTripSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
