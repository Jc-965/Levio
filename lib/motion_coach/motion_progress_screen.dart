import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/modern_card.dart';
import 'motion_exercise_catalog.dart';
import 'motion_routine_results_screen.dart';
import 'motion_session_history.dart';

/// Trends across saved routine sessions.
///
/// Everything shown is a score the engine already produced; this screen only
/// orders and averages them. It also owns the delete control, because a
/// local record the person cannot remove is not really local-only.
class MotionProgressScreen extends StatefulWidget {
  const MotionProgressScreen({super.key, required this.history});

  final MotionSessionHistory history;

  @override
  State<MotionProgressScreen> createState() => _MotionProgressScreenState();
}

class _MotionProgressScreenState extends State<MotionProgressScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await widget.history.load();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _confirmClear() async {
    final bool? clear = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete movement history?'),
        content: const Text(
          'Every saved score on this device will be removed. This cannot be '
          'undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (clear != true) return;
    HapticUtils.mediumImpact();
    await widget.history.clear();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final List<MotionSessionRecord> entries = widget.history.entries;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Movement progress'),
        actions: <Widget>[
          if (entries.isNotEmpty)
            IconButton(
              tooltip: 'Delete history',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => unawaited(_confirmClear()),
            ),
        ],
      ),
      body: LiquidBackground(
        child: SafeArea(
          top: false,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : entries.isEmpty
              ? _buildEmpty(context)
              : _buildContent(context, entries),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.timeline_rounded, size: 48, color: colors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No sessions yet',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Finish a guided routine and your scores will appear here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<MotionSessionRecord> entries,
  ) {
    final colors = context.colors;
    final double? recent = widget.history.recentAverageScore();
    final Set<String> practised = <String>{
      for (final MotionSessionRecord entry in entries)
        for (final MotionSessionStep step in entry.steps)
          if (step.overallScore != null) step.exerciseId,
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ModernCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(20),
            backgroundColor: colors.primary.withValues(alpha: 0.1),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _Statistic(
                    label: 'Sessions',
                    value: '${entries.length}',
                  ),
                ),
                Expanded(
                  child: _Statistic(
                    label: 'Recent average',
                    value: recent == null ? '—' : '${recent.round()}',
                  ),
                ),
                Expanded(
                  child: _Statistic(
                    label: 'Day streak',
                    value: '${widget.history.currentStreakDays()}',
                  ),
                ),
                Expanded(
                  child: _Statistic(
                    label: 'This week',
                    value: '${widget.history.sessionsInLastWeek()}',
                  ),
                ),
              ],
            ),
          ),
          if (practised.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionHeading(
              title: 'By exercise',
              description: 'Most recent score first.',
            ),
            const SizedBox(height: 12),
            for (final String exerciseId in practised)
              _ExerciseTrendCard(
                exerciseId: exerciseId,
                scores: widget.history.scoreTrendFor(exerciseId),
              ),
          ],
          const SizedBox(height: 20),
          const SectionHeading(title: 'Sessions'),
          const SizedBox(height: 12),
          for (final MotionSessionRecord entry in entries)
            _SessionCard(
              entry: entry,
              onTap: () {
                HapticUtils.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MotionRoutineResultsScreen(
                      title: entry.routineName,
                      record: entry,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _Statistic extends StatelessWidget {
  const _Statistic({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: <Widget>[
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _ExerciseTrendCard extends StatelessWidget {
  const _ExerciseTrendCard({required this.exerciseId, required this.scores});

  final String exerciseId;
  final List<double> scores;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (scores.isEmpty) return const SizedBox.shrink();
    final double latest = scores.first;
    final double? previous = scores.length > 1 ? scores[1] : null;
    final double? change = previous == null ? null : latest - previous;

    String title;
    try {
      title = motionExerciseById(exerciseId).title;
    } on ArgumentError {
      title = exerciseId;
    }

    return ModernCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${scores.length} scored '
                  '${scores.length == 1 ? 'session' : 'sessions'}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${latest.round()}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primary,
            ),
          ),
          if (change != null && change.abs() >= 1) ...[
            const SizedBox(width: 8),
            Icon(
              change > 0
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              size: 20,
              color: change > 0 ? colors.success : colors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.entry, required this.onTap});

  final MotionSessionRecord entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ModernCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.routineName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatDate(entry.completedAt)} · '
                  '${entry.completedRepetitions} movements · '
                  '${entry.assessedSteps}/${entry.totalSteps} steps measured',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            entry.overallScore == null ? '—' : '${entry.overallScore!.round()}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: entry.overallScore == null
                  ? colors.textSecondary
                  : colors.primary,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) {
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }
}
