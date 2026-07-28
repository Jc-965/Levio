import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'pressable_scale.dart';

/// Compact filled/outlined action button used inside cards (Log, Start).
class CardActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final bool filled;
  final VoidCallback onTap;

  const CardActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = filled ? colors.textOnPrimary : accent;

    return PressableScale(
      pressedScale: 0.92,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? accent : colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: filled
              ? null
              : Border.all(color: colors.border.blend(accent, 0.55)),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
