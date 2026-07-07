// Verifies the bundled nodelink.bin asset decodes correctly and that a
// known real coordinate from the ITS 표준노드링크 dataset matches back to
// its actual road name and speed limit (술이홀로, 파주시, MAX_SPD=60 —
// cross-checked against the raw MOCT_LINK.dbf/.shp during preprocessing).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:meter/services/road_match_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// RoadMatchService extracts the bundled asset to the app-support directory
/// on first use; there's no real platform channel in `flutter test`, so
/// point it at a temp directory instead.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String _path = Directory.systemTemp
      .createTempSync('roadmatch_test')
      .path;

  @override
  Future<String?> getApplicationSupportPath() async => _path;
}

void main() {
  // Not a widget test, but rootBundle.load still needs the services binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PathProviderPlatform.instance = _FakePathProviderPlatform();
  });

  test('matches a known coordinate to its road name and speed limit',
      () async {
    final service = RoadMatchService();
    final match =
        await service.debugMatchAt(37.91029540615018, 126.89398575063647);

    expect(match, isNotNull);
    expect(match!.roadName, '술이홀로');
    expect(match.maxSpeedKmh, 60);
  });

  test('a point far offshore finds no nearby road', () async {
    final service = RoadMatchService();
    // East Sea, well beyond the mainland and any island.
    final match = await service.debugMatchAt(36.0, 131.5);

    expect(match, isNull);
  });

  test(
      'concurrent fixes on a freshly-created service do not race the '
      'initial load (regression: used to throw LateInitializationError)',
      () async {
    final service = RoadMatchService();
    // Fire several lookups back-to-back, mimicking GPS fixes arriving while
    // the first one is still loading/extracting the asset.
    final results = await Future.wait([
      service.debugMatchAt(37.91029540615018, 126.89398575063647),
      service.debugMatchAt(37.91029540615018, 126.89398575063647),
      service.debugMatchAt(36.0, 131.5),
    ]);

    expect(results[0]!.roadName, '술이홀로');
    expect(results[1]!.roadName, '술이홀로');
    expect(results[2], isNull);
  });
}
