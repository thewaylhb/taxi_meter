import 'package:flutter/material.dart';

import '../models/trip_record.dart';
import '../services/trip_repository.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'trip_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  final TripRepository tripRepository;

  const HistoryScreen({super.key, required this.tripRepository});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<TripRecord>? _records;

  @override
  void initState() {
    super.initState();
    _load();
    widget.tripRepository.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.tripRepository.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => _load();

  Future<void> _load() async {
    final records = await widget.tripRepository.loadAll();
    if (!mounted) return;
    setState(() => _records = records);
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('전체 삭제'),
        content: const Text('모든 운행 기록을 삭제할까요? 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.tripRepository.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return Scaffold(
      appBar: AppBar(
        title: const Text('운행 기록'),
        actions: [
          IconButton(
            onPressed: _confirmClearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: '전체 삭제',
          ),
        ],
      ),
      body: records == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _monthlyStatsCard(context, records),
                Expanded(
                  child: records.isEmpty
                      ? RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(child: Text('운행 기록이 없습니다.')),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(8),
                            itemCount: records.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final r = records[index];
                              return Dismissible(
                                key: ValueKey(r.id),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  color: Theme.of(context).colorScheme.error,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.symmetric(horizontal: 20),
                                  child: Icon(
                                    Icons.delete,
                                    color: Theme.of(context).colorScheme.onError,
                                  ),
                                ),
                                onDismissed: (_) {
                                  // Remove from the local list synchronously so the
                                  // widget tree matches what Dismissible expects on
                                  // this same frame; the actual persistence happens
                                  // in the background.
                                  setState(() {
                                    _records = List.of(records)..removeAt(index);
                                  });
                                  widget.tripRepository.delete(r.id);
                                },
                                child: ListTile(
                                  leading: Icon(
                                    r.mode.name == 'carpool' ? Icons.people : Icons.local_taxi,
                                  ),
                                  title: Text(
                                    formatWon(r.fareWon),
                                    style: fareTextStyle(context, fontSize: 16),
                                  ),
                                  subtitle: Text(
                                    '${formatDateTime(r.startTime)} · ${formatDistanceKm(r.distanceMeters)} · ${formatDuration(r.duration)} · ${formatSpeedKmh(r.averageSpeedKmh, decimals: 1)} · ${r.mode.label}'
                                    '${r.riderCount > 1 ? ' · ${r.riderCount}인 분할' : ''}',
                                  ),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => TripDetailScreen(record: r),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _monthlyStatsCard(BuildContext context, List<TripRecord> records) {
    final now = DateTime.now();
    final thisMonth = records.where(
      (r) => r.startTime.year == now.year && r.startTime.month == now.month,
    );
    final tripCount = thisMonth.length;
    final totalDistanceMeters =
        thisMonth.fold<double>(0, (sum, r) => sum + r.distanceMeters);
    final totalFareWon = thisMonth.fold<int>(0, (sum, r) => sum + r.fareWon);

    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            _statTile(context, '이번 달', '$tripCount회'),
            _statTile(context, '거리', formatDistanceKm(totalDistanceMeters)),
            _statTile(
              context,
              '예상 수입',
              formatWon(totalFareWon),
              accent: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(
    BuildContext context,
    String label,
    String value, {
    bool accent = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: accent
                ? fareTextStyle(context, fontSize: 16)
                : const TextStyle(
                    fontSize: 16,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
          ),
        ],
      ),
    );
  }
}
