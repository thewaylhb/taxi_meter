import 'package:flutter/material.dart';

import '../services/road_match_service.dart';

/// Slim, always-visible bar showing the road currently being driven on,
/// matched from GPS against the bundled ITS 표준노드링크 data. Sits above
/// the tab content in [RootScreen], visible only while a trip is running.
/// The speed limit itself is shown separately as a circular sign on the
/// meter screen (see [SpeedLimitSign]), closer to the driver's speed.
class RoadInfoBanner extends StatelessWidget {
  final RoadMatchService roadMatchService;

  const RoadInfoBanner({super.key, required this.roadMatchService});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: roadMatchService,
      builder: (context, _) {
        final match = roadMatchService.current;
        return Container(
          width: double.infinity,
          color: theme.colorScheme.surfaceContainerHigh,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                Icon(Icons.signpost_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    match?.roadName ?? '위치 확인 중',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
