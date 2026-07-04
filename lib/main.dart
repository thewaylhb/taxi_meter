import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/history_screen.dart';
import 'screens/meter_screen.dart';
import 'screens/settings_screen.dart';
import 'services/settings_controller.dart';
import 'services/trip_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  runApp(const TaxiMeterApp());
}

class TaxiMeterApp extends StatelessWidget {
  const TaxiMeterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
        useMaterial3: true,
      ),
      home: const RootScreen(),
    );
  }
}

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  final SettingsController _settingsController = SettingsController();
  final TripRepository _tripRepository = TripRepository();
  int _tabIndex = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _settingsController.load().then((_) {
      setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final screens = [
      MeterScreen(
        settingsController: _settingsController,
        tripRepository: _tripRepository,
      ),
      HistoryScreen(tripRepository: _tripRepository),
      SettingsScreen(settingsController: _settingsController),
    ];

    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.local_taxi), label: '미터기'),
          NavigationDestination(icon: Icon(Icons.history), label: '운행 기록'),
          NavigationDestination(icon: Icon(Icons.settings), label: '설정'),
        ],
      ),
    );
  }
}
