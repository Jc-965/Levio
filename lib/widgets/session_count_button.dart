import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Display-only count badge shown on a video thumbnail once at least one
/// session has been logged.
class SessionCountBadge extends StatelessWidget {
  final int count;
  final Color accent;

  const SessionCountBadge({
    super.key,
    required this.count,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.replay_rounded, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Text(
              '${count}x',
              key: ValueKey<int>(count),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Footer chip summarizing how many sessions of a video have been logged.
class SessionCountChip extends StatelessWidget {
  final int count;
  final Color accent;

  const SessionCountChip({
    super.key,
    required this.count,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (count == 0) {
      return Text(
        'Not logged yet',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colors.textTertiary,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.replay_rounded, size: 13, color: accent),
          const SizedBox(width: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Text(
              '${count}x logged',
              key: ValueKey<int>(count),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
