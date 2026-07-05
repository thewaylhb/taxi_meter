import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/history_screen.dart';
import 'screens/meter_screen.dart';
import 'screens/settings_screen.dart';
import 'services/settings_controller.dart';
import 'services/trip_repository.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  runApp(const TaxiMeterApp());
}

class TaxiMeterApp extends StatefulWidget {
  const TaxiMeterApp({super.key});

  @override
  State<TaxiMeterApp> createState() => _TaxiMeterAppState();
}

class _TaxiMeterAppState extends State<TaxiMeterApp> {
  final SettingsController _settingsController = SettingsController();
  final TripRepository _tripRepository = TripRepository();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _settingsController.addListener(_onSettingsChanged);
    _settingsController.load().then((_) {
      setState(() => _loaded = true);
    });
  }

  void _onSettingsChanged() => setState(() {});

  @override
  void dispose() {
    _settingsController.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meter',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _settingsController.themeMode,
      home: _loaded
          ? RootScreen(
              settingsController: _settingsController,
              tripRepository: _tripRepository,
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class RootScreen extends StatefulWidget {
  final SettingsController settingsController;
  final TripRepository tripRepository;

  const RootScreen({
    super.key,
    required this.settingsController,
    required this.tripRepository,
  });

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      MeterScreen(
        settingsController: widget.settingsController,
        tripRepository: widget.tripRepository,
      ),
      HistoryScreen(tripRepository: widget.tripRepository),
      SettingsScreen(settingsController: widget.settingsController),
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
