// Verifies the bundled nodelink.bin asset decodes correctly and that a
// known real coordinate from the ITS 표준노드링크 dataset matches back to
// its actual road name and speed limit (술이홀로, 파주시, MAX_SPD=60 —
// cross-checked against the raw MOCT_LINK.dbf/.shp during preprocessing).
//
// Also covers the dwell-time/heading hysteresis that sits in front of the
// raw nearest-link match (see RoadMatchService._onPosition), using
// RoadMatchService.debugWithLookup to drive it with synthetic candidates
// instead of needing real interchange/ramp coordinates from the dataset.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
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

  group('hysteresis (dwell time + heading) in front of the raw match', () {
    // A road running east/west, and two "other roads" competing for nearest
    // match: one whose segment direction is perpendicular to the eastbound
    // heading simulated below (like a ramp forking away from the main
    // road), and one that happens to run the same direction (like a ramp
    // that briefly parallels the main road before diverging).
    const mainRoad = RoadMatchCandidate(
      roadName: '메인도로',
      maxSpeedKmh: 100,
      segDx: 1,
      segDy: 0,
    );
    const rampUnaligned = RoadMatchCandidate(
      roadName: '진출램프',
      maxSpeedKmh: 40,
      segDx: 0,
      segDy: 1,
    );
    // A shallow national-road-style fork: only 15° off the main road, well
    // under the old fixed 25° "aligned" threshold this used to compare
    // against directly (the bug the relative comparison below fixes).
    final shallowFork = RoadMatchCandidate(
      roadName: '완만한분기로',
      maxSpeedKmh: 40,
      segDx: cos(15 * pi / 180),
      segDy: sin(15 * pi / 180),
    );
    // The same fork, further down its own curve (40° off the main road) —
    // stands in for "the vehicle has actually followed the fork" in the
    // turn-confirmed test below.
    final turnedFork = RoadMatchCandidate(
      roadName: '완만한분기로',
      maxSpeedKmh: 40,
      segDx: cos(40 * pi / 180),
      segDy: sin(40 * pi / 180),
    );

    const baseLat = 37.5;
    const speedMetersPerSecond = 20.0; // ~72km/h, a plausible expressway speed
    final metersPerDegLon = 111320.0 * cos(baseLat * pi / 180);
    final base = DateTime(2026, 7, 4, 12, 0, 0);

    // Fixes moving steadily east so the heading estimator (last 3 fixes)
    // reads a stable eastbound direction, regardless of exact spacing.
    Position posAt(double seconds) => Position(
          latitude: baseLat,
          longitude: 127.0 + speedMetersPerSecond * seconds / metersPerDegLon,
          timestamp:
              base.add(Duration(milliseconds: (seconds * 1000).round())),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: speedMetersPerSecond,
          speedAccuracy: 0,
        );

    // Continues from posAt(2.5) but bearing angleFromEastDegrees instead of
    // due east — simulates the vehicle actually following a fork's curve
    // after passing the split.
    Position posTurnedAt(double seconds, double angleFromEastDegrees) {
      final elapsed = seconds - 2.5;
      final rad = angleFromEastDegrees * pi / 180;
      final east = speedMetersPerSecond * elapsed * cos(rad);
      final north = speedMetersPerSecond * elapsed * sin(rad);
      return Position(
        latitude: baseLat + north / 111320.0,
        longitude: 127.0 +
            speedMetersPerSecond * 2.5 / metersPerDegLon +
            east / metersPerDegLon,
        timestamp: base.add(Duration(milliseconds: (seconds * 1000).round())),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: speedMetersPerSecond,
        speedAccuracy: 0,
      );
    }

    // Feeds one candidate per debugOnPosition call (holding the last entry
    // once the script runs out), standing in for the real nearest-link
    // lookup so tests don't need real interchange/ramp coordinates.
    RoadMatchService serviceWithScript(List<RoadMatchCandidate?> script) {
      var i = 0;
      return RoadMatchService.debugWithLookup((lat, lon) async {
        final candidate = script[i];
        if (i < script.length - 1) i++;
        return candidate;
      });
    }

    test('adopts the first-ever fix immediately, no dwell needed', () async {
      final service = serviceWithScript([mainRoad]);
      await service.debugOnPosition(posAt(0));

      expect(service.current?.roadName, '메인도로');
      expect(service.current?.maxSpeedKmh, 100);
    });

    test(
        'a transient nearest-match flip that reverts before the dwell '
        'period elapses never reaches the display — this is the reported '
        'bug: a ramp momentarily closer than the main road near an '
        'interchange must not flicker the shown speed limit', () async {
      final service = serviceWithScript([
        mainRoad, mainRoad, mainRoad, // establish match + heading history
        rampUnaligned, // GPS noise briefly makes the ramp nearest
        mainRoad, // noise clears, main road nearest again
      ]);

      await service.debugOnPosition(posAt(0));
      await service.debugOnPosition(posAt(1));
      await service.debugOnPosition(posAt(2));

      await service.debugOnPosition(posAt(2.5));
      expect(service.current?.maxSpeedKmh, 100,
          reason: 'must not flicker to the ramp speed limit while pending');

      await service.debugOnPosition(posAt(3.0));
      expect(service.current?.roadName, '메인도로');
      expect(service.current?.maxSpeedKmh, 100);
    });

    test(
        'a candidate that stays nearest for the full 3s default dwell '
        'switches, even when its direction does not match the heading',
        () async {
      final service = serviceWithScript([
        mainRoad, mainRoad, mainRoad,
        rampUnaligned, rampUnaligned, rampUnaligned,
      ]);

      await service.debugOnPosition(posAt(0));
      await service.debugOnPosition(posAt(1));
      await service.debugOnPosition(posAt(2));

      await service.debugOnPosition(posAt(2.5)); // candidate becomes pending
      await service.debugOnPosition(posAt(3.0)); // elapsed 0.5s < 3s
      expect(service.current?.maxSpeedKmh, 100);

      await service.debugOnPosition(posAt(5.6)); // elapsed 3.1s >= 3s
      expect(service.current?.roadName, '진출램프');
      expect(service.current?.maxSpeedKmh, 40);
    });

    test(
        'a shallow-angle fork (15°, under the old fixed 25° threshold) does '
        'NOT get fast-tracked just because its own divergence angle is '
        'small — the vehicle is still heading straight down the main road, '
        'so there is no relative evidence of a turn', () async {
      final service = serviceWithScript([
        mainRoad, mainRoad, mainRoad, // establish match + heading (due east)
        shallowFork, shallowFork, shallowFork, shallowFork,
      ]);

      await service.debugOnPosition(posAt(0));
      await service.debugOnPosition(posAt(1));
      await service.debugOnPosition(posAt(2));

      await service.debugOnPosition(posAt(2.5)); // candidate becomes pending
      // Elapsed 1.5s here: past the 1s fast-track dwell (so this would have
      // already switched under a fixed-25°-absolute-threshold design, since
      // 15° <= 25°) but well under the 3s default — the key checkpoint that
      // actually distinguishes the relative comparison from the old bug.
      await service.debugOnPosition(posAt(4.0));
      expect(service.current?.maxSpeedKmh, 100,
          reason:
              'a 15° fork angle alone must not be mistaken for the vehicle '
              'having turned — heading is unchanged, still matches the '
              'main road far better than the fork');

      await service.debugOnPosition(posAt(5.6)); // elapsed 3.1s >= 3s: still
      // eventually switches once it's been the nearest match long enough on
      // its own merits (the default dwell, not the heading fast-track).
      expect(service.current?.roadName, '완만한분기로');
      expect(service.current?.maxSpeedKmh, 40);
    });

    test(
        'once the heading actually swings toward the fork (following its '
        'curve past the split), it fast-tracks after the shorter 1s dwell '
        '— even though the fork is the same shallow shape as above',
        () async {
      final service = serviceWithScript([
        mainRoad, mainRoad, mainRoad, // establish match + heading (due east)
        turnedFork, turnedFork, turnedFork, turnedFork,
      ]);

      await service.debugOnPosition(posAt(0));
      await service.debugOnPosition(posAt(1));
      await service.debugOnPosition(posAt(2));

      await service.debugOnPosition(posAt(2.5)); // candidate becomes pending
      // From here on the simulated GPS trace itself turns 40° off the
      // original heading, following the fork's curve past the split.
      await service.debugOnPosition(posTurnedAt(3.0, 40));
      expect(service.current?.maxSpeedKmh, 100,
          reason: 'elapsed 0.5s < 1s: too soon regardless of heading');

      await service.debugOnPosition(posTurnedAt(3.5, 40));
      // By now the last 3 recorded fixes are all on the turned trajectory,
      // so the heading estimate has rotated to ~40° — clearly closer to the
      // fork's own direction than to the main road's frozen (due-east)
      // direction, confirming the turn well within the 1s fast dwell.
      expect(service.current?.roadName, '완만한분기로');
      expect(service.current?.maxSpeedKmh, 40);
    });
  });
}
