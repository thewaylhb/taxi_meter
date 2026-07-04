import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_record.dart';

/// Local-only trip log. Every settled trip is appended here; nothing ever
/// leaves the device. Notifies listeners whenever the log changes, so
/// screens showing it can refresh without a manual pull-to-refresh.
class TripRepository extends ChangeNotifier {
  static const _key = 'trip_records';

  /// Serializes mutations onto a single chain so concurrent add/delete/
  /// clearAll calls can't race each other's read-modify-write cycle against
  /// SharedPreferences and silently drop one side's change.
  Future<void> _writeQueue = Future.value();

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _writeQueue.then((_) => operation());
    _writeQueue = result.catchError((_) {});
    return result;
  }

  Future<List<TripRecord>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    final records = raw
        .map((s) => TripRecord.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    records.sort((a, b) => b.startTime.compareTo(a.startTime));
    return records;
  }

  /// Adds [record], replacing any existing entry with the same id. Upsert
  /// semantics make this safe to call twice for the same trip (e.g. if a
  /// crash-recovered trip gets settled again after an interrupted previous
  /// settlement) without producing a duplicate history entry.
  Future<void> add(TripRecord record) => _enqueue(() async {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getStringList(_key) ?? const [];
        final withoutSameId = raw.where((s) {
          final json = jsonDecode(s) as Map<String, dynamic>;
          return json['id'] != record.id;
        });
        final updated = [...withoutSameId, jsonEncode(record.toJson())];
        await prefs.setStringList(_key, updated);
        notifyListeners();
      });

  Future<void> delete(String id) => _enqueue(() async {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getStringList(_key) ?? const [];
        final updated = raw.where((s) {
          final json = jsonDecode(s) as Map<String, dynamic>;
          return json['id'] != id;
        }).toList();
        await prefs.setStringList(_key, updated);
        notifyListeners();
      });

  Future<void> clearAll() => _enqueue(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_key);
        notifyListeners();
      });
}
