// Verifies the bundled nodelink.bin asset decodes correctly and that a
// known real coordinate from the ITS 표준노드링크 dataset matches back to
// its actual road name and speed limit (술이홀로, 파주시, MAX_SPD=60 —
// cross-checked against the raw MOCT_LINK.dbf/.shp during preprocessing).
import 'package:flutter_test/flutter_test.dart';
import 'package:meter/services/road_match_service.dart';

void main() {
  testWidgets('matches a known coordinate to its road name and speed limit',
      (WidgetTester tester) async {
    final service = RoadMatchService();
    final match =
        await service.debugMatchAt(37.91029540615018, 126.89398575063647);

    expect(match, isNotNull);
    expect(match!.roadName, '술이홀로');
    expect(match.maxSpeedKmh, 60);
  });

  testWidgets('a point far offshore finds no nearby road',
      (WidgetTester tester) async {
    final service = RoadMatchService();
    // East Sea, well beyond the mainland and any island.
    final match = await service.debugMatchAt(36.0, 131.5);

    expect(match, isNull);
  });
}
