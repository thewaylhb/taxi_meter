import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/history_screen.dart';
import 'screens/meter_screen.dart';
import 'screens/settings_screen.dart';
import 'services/meter_controller.dart';
import 'services/road_match_service.dart';
import 'services/settings_controller.dart';
import 'services/trip_repository.dart';
import 'theme/app_theme.dart';
import 'widgets/road_info_banner.dart';

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
  final RoadMatchService _roadMatchService = RoadMatchService();
  late final MeterController _meterController =
      MeterController(tripRepository: widget.tripRepository);
  MeterState _lastMeterState = MeterState.idle;

  @override
  void initState() {
    super.initState();
    _meterController.addListener(_onMeterChange);
    _meterController.recoverIfAny();
  }

  // Road matching (and the GPS it needs) only runs while a trip is actually
  // running: it's a courtesy display, not billing-critical, and there's no
  // legitimate reason to hold location while the meter is idle.
  void _onMeterChange() {
    final running = _meterController.state == MeterState.running;
    if (running && _lastMeterState != MeterState.running) {
      _roadMatchService.start();
    } else if (!running && _lastMeterState == MeterState.running) {
      _roadMatchService.stop();
    }
    _lastMeterState = _meterController.state;
    setState(() {});
  }

  @override
  void dispose() {
    _meterController.removeListener(_onMeterChange);
    _meterController.dispose();
    _roadMatchService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      MeterScreen(
        meterController: _meterController,
        settingsController: widget.settingsController,
        roadMatchService: _roadMatchService,
      ),
      HistoryScreen(tripRepository: widget.tripRepository),
      SettingsScreen(settingsController: widget.settingsController),
    ];

    final showRoadBanner = _meterController.state == MeterState.running;

    return Scaffold(
      body: Column(
        children: [
          if (showRoadBanner) RoadInfoBanner(roadMatchService: _roadMatchService),
          Expanded(
            // Each tab owns its own Scaffold+AppBar, which reserves the top
            // status-bar inset itself. When the banner is showing, it has
            // already consumed that inset above, so strip it here too or
            // the AppBar reserves it a second time, opening a gap between
            // the banner and the tab's app bar.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: showRoadBanner,
              child: IndexedStack(index: _tabIndex, children: screens),
            ),
          ),
        ],
      ),
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
