import 'package:flutter/material.dart';

import '../models/trip_record.dart';
import '../services/trip_repository.dart';
import '../utils/formatters.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TripRepository _repository = TripRepository();
  late Future<List<TripRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.loadAll();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _repository.loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('운행 기록')),
      body: FutureBuilder<List<TripRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final records = snapshot.data!;
          if (records.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('운행 기록이 없습니다.')),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: records.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final r = records[index];
                return ListTile(
                  leading: Icon(
                    r.mode.name == 'carpool' ? Icons.people : Icons.local_taxi,
                  ),
                  title: Text(formatWon(r.fareWon)),
                  subtitle: Text(
                    '${formatDateTime(r.startTime)} · ${formatDistanceKm(r.distanceMeters)} · ${formatDuration(r.duration)} · ${r.mode.label}',
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
