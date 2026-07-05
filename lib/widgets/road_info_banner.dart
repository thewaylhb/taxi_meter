import 'package:flutter/material.dart';

import '../services/road_match_service.dart';

/// Slim, always-visible bar showing the road currently being driven on and
/// its speed limit, matched from GPS against the bundled ITS 표준노드링크
/// data. Sits above the tab content in [RootScreen] so it's visible no
/// matter which tab (미터기/운행 기록/설정) is active.
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
                if (match != null && match.maxSpeedKmh > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '제한 ${match.maxSpeedKmh}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
