import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';

/// Compact, task-first recovery library row shared by speech and movement.
class RecoveryLessonCard extends StatefulWidget {
  final String title;
  final String description;
  final String duration;
  final String source;
  final String thumbnailUrl;
  final String typeLabel;
  final String? badgeLabel;
  final IconData typeIcon;
  final Color accent;
  final int sessionCount;
  final VoidCallback onStart;
  final Future<void> Function() onLog;

  const RecoveryLessonCard({
    super.key,
    required this.title,
    required this.description,
    required this.duration,
    required this.source,
    required this.thumbnailUrl,
    required this.typeLabel,
    this.badgeLabel,
    required this.typeIcon,
    required this.accent,
    required this.sessionCount,
    required this.onStart,
    required this.onLog,
  });

  @override
  State<RecoveryLessonCard> createState() => _RecoveryLessonCardState();
}

class _RecoveryLessonCardState extends State<RecoveryLessonCard> {
  bool _isLogging = false;

  Future<void> _log() async {
    if (_isLogging) return;
    HapticUtils.mediumImpact();
    setState(() => _isLogging = true);
    try {
      await widget.onLog();
    } finally {
      if (mounted) setState(() => _isLogging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: 'Open ${widget.title}',
            child: InkWell(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
              onTap: widget.onStart,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 108,
                        height: 84,
                        child: Image.network(
                          widget.thumbnailUrl,
                          fit: BoxFit.cover,
                          cacheWidth: 360,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                                  ? child
                                  : ColoredBox(color: colors.surfaceVariant),
                          errorBuilder: (context, error, stackTrace) =>
                              ColoredBox(
                            color: colors.surfaceVariant,
                            child: Icon(
                              widget.typeIcon,
                              color: colors.textTertiary,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                widget.typeIcon,
                                color: widget.accent,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.typeLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: widget.accent,
                                        fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (widget.badgeLabel != null) ...[
                                const SizedBox(width: 8),
                                Semantics(
                                  label: widget.badgeLabel,
                                  excludeSemantics: true,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: widget.accent.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: widget.accent.withValues(
                                          alpha: 0.24,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      widget.badgeLabel!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: widget.accent,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            [
                              if (widget.duration.isNotEmpty) widget.duration,
                              widget.sessionCount == 0
                                  ? 'Not logged'
                                  : '${widget.sessionCount}× completed',
                            ].join(' · '),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colors.textTertiary,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(height: 1, color: colors.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isLogging ? null : _log,
                    child: _isLogging
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Log completed'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.onStart,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.textPrimary,
                      foregroundColor: colors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 19),
                    label: const Text('Start'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
