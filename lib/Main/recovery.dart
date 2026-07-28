import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../Recovery/exercise.dart';
import '../Recovery/speech.dart';
import '../singleton.dart';
import '../theme/app_theme.dart';
import '../utils/app_routes.dart';
import '../utils/haptic_utils.dart';
import '../widgets/recovery_log_sheet.dart';

enum _RecoverySection { plan, history }

class _RecoverySession {
  final String videoId;
  final String type;
  final String title;
  final String description;
  final String duration;
  final String source;

  const _RecoverySession({
    required this.videoId,
    required this.type,
    required this.title,
    required this.description,
    required this.duration,
    required this.source,
  });

  bool get isPhysical => type == Singleton.recoveryTypePhysical;
  String get typeLabel => isPhysical ? 'Movement' : 'Speech';
  IconData get icon =>
      isPhysical ? Icons.accessibility_new_rounded : Icons.graphic_eq_rounded;
  String get thumbnailUrl =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
}

class RecoveryScreen extends StatefulWidget {
  final GlobalKey? exerciseCardKey;

  const RecoveryScreen({super.key, this.exerciseCardKey});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final singleton = Singleton();
  _RecoverySection _section = _RecoverySection.plan;
  late final List<_RecoverySession> _weekPlan;

  @override
  void initState() {
    super.initState();
    _weekPlan = _buildWeekPlan();
    singleton.addListener(_onSingletonUpdate);
  }

  @override
  void dispose() {
    singleton.removeListener(_onSingletonUpdate);
    super.dispose();
  }

  void _onSingletonUpdate() {
    if (mounted) setState(() {});
  }

  List<_RecoverySession> _buildWeekPlan() {
    final physical = singleton.recommendedPhysicalExerciseIds(limit: 2);
    final speech = singleton.recommendedSpeechExerciseIds(limit: 1);
    final ordered = <({String id, String type})>[
      if (physical.isNotEmpty)
        (id: physical.first, type: Singleton.recoveryTypePhysical),
      if (speech.isNotEmpty)
        (id: speech.first, type: Singleton.recoveryTypeSpeech),
      if (physical.length > 1)
        (id: physical[1], type: Singleton.recoveryTypePhysical),
    ];

    return ordered
        .map((item) {
          final data = item.type == Singleton.recoveryTypePhysical
              ? singleton.exercises[item.id]
              : singleton.speeches[item.id];
          return _RecoverySession(
            videoId: item.id,
            type: item.type,
            title: data?.elementAtOrNull(0) ?? 'Guided session',
            description: data?.elementAtOrNull(1) ?? '',
            duration: data?.elementAtOrNull(2) ?? '',
            source: data?.elementAtOrNull(3) ?? '',
          );
        })
        .toList(growable: false);
  }

  Color _accentFor(_RecoverySession session, AppColors colors) {
    return session.isPhysical ? colors.secondary : colors.primary;
  }

  int _countFor(_RecoverySession session) {
    return singleton.recoverySessionCountForVideo(
      session.type,
      session.videoId,
    );
  }

  void _startSession(_RecoverySession session) {
    HapticUtils.lightImpact();
    singleton.setCurrentUrl(session.videoId);
    Navigator.pushNamed(
      context,
      session.isPhysical ? '/exerciseVideoScreen' : '/speechAudio',
    );
  }

  Future<void> _logSession(_RecoverySession session) async {
    final count = await showRecoveryLogSheet(
      context: context,
      title: session.title,
      typeLabel: session.typeLabel,
      duration: session.duration,
      icon: session.icon,
      accent: _accentFor(session, context.colors),
      onSave: (completedAt) {
        if (session.isPhysical) {
          return singleton.recordPhysicalExerciseSession(
            session.videoId,
            completedAt: completedAt,
          );
        }
        return singleton.recordSpeechExerciseSession(
          session.videoId,
          completedAt: completedAt,
        );
      },
    );

    if (!mounted || count == null) return;
    HapticUtils.success();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${session.title} added to History · $count ${count == 1 ? 'time' : 'times'} completed',
          ),
          action: SnackBarAction(
            label: 'View',
            onPressed: () =>
                setState(() => _section = _RecoverySection.history),
          ),
        ),
      );
  }

  Future<void> _editGoals() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GoalEditorSheet(
        speechGoal: singleton.weeklySpeechExerciseGoal,
        physicalGoal: singleton.weeklyPhysicalExerciseGoal,
        onSave: (speech, physical) {
          singleton.setTherapyGoals(
            weeklySpeech: speech,
            weeklyPhysical: physical,
          );
        },
      ),
    );
  }

  Future<void> _deleteSession(Map<String, dynamic> session) async {
    final colors = context.colors;
    final title = session['title']?.toString().trim().isNotEmpty == true
        ? session['title'].toString()
        : 'this session';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from history?'),
        content: Text(
          'This removes “$title” from your recovery history and weekly progress.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: colors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final deleted = await singleton.deleteRecoverySessionById(
      session['id']?.toString() ?? '',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deleted
                ? 'Session removed from History.'
                : 'Unable to remove session.',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Material(
      color: colors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RecoveryTabs(
                  section: _section,
                  onChanged: (section) {
                    if (section == _section) return;
                    HapticUtils.selectionClick();
                    setState(() => _section = section);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.015, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _section == _RecoverySection.plan
                  ? _PlanView(
                      key: const ValueKey('recovery-plan'),
                      singleton: singleton,
                      sessions: _weekPlan,
                      accentFor: (session) => _accentFor(session, colors),
                      countFor: _countFor,
                      onEditGoals: _editGoals,
                      onStart: _startSession,
                      onLog: _logSession,
                      exerciseCardKey: widget.exerciseCardKey,
                    )
                  : _HistoryView(
                      key: const ValueKey('recovery-history'),
                      singleton: singleton,
                      onDelete: _deleteSession,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecoveryTabs extends StatelessWidget {
  final _RecoverySection section;
  final ValueChanged<_RecoverySection> onChanged;

  const _RecoveryTabs({required this.section, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      container: true,
      label: 'Recovery view',
      child: Row(
        children: _RecoverySection.values
            .map((item) {
              final selected = item == section;
              final label = item == _RecoverySection.plan ? 'Plan' : 'History';
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: '$label tab',
                  child: InkWell(
                    onTap: () => onChanged(item),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 44,
                          child: Center(
                            child: Text(
                              label,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: selected
                                        ? colors.textPrimary
                                        : colors.textTertiary,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutCubic,
                          height: 2,
                          color: selected ? colors.textPrimary : colors.divider,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _PlanView extends StatelessWidget {
  final Singleton singleton;
  final List<_RecoverySession> sessions;
  final Color Function(_RecoverySession session) accentFor;
  final int Function(_RecoverySession session) countFor;
  final VoidCallback onEditGoals;
  final ValueChanged<_RecoverySession> onStart;
  final ValueChanged<_RecoverySession> onLog;
  final GlobalKey? exerciseCardKey;

  const _PlanView({
    super.key,
    required this.singleton,
    required this.sessions,
    required this.accentFor,
    required this.countFor,
    required this.onEditGoals,
    required this.onStart,
    required this.onLog,
    this.exerciseCardKey,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return CustomScrollView(
      key: const PageStorageKey('recovery-plan-scroll'),
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 34),
          sliver: SliverList.list(
            children: [
              _WeeklyPlanPanel(singleton: singleton, onEditGoals: onEditGoals),
              const SizedBox(height: 28),
              _SectionTitle(
                title: 'Up next',
                detail: sessions.isEmpty
                    ? 'Choose a session from the library.'
                    : 'One focused session for your next practice.',
              ),
              const SizedBox(height: 12),
              if (sessions.isEmpty)
                _RecoverySurface(
                  child: Text(
                    'No guided sessions are available right now.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                _NextSessionCard(
                  session: sessions.first,
                  accent: accentFor(sessions.first),
                  sessionCount: countFor(sessions.first),
                  onStart: () => onStart(sessions.first),
                  onLog: () => onLog(sessions.first),
                ),
              if (sessions.length > 1) ...[
                const SizedBox(height: 28),
                const _SectionTitle(
                  title: 'Later this week',
                  detail: 'A short queue you can complete in any order.',
                ),
                const SizedBox(height: 8),
                _RecoverySurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: List<Widget>.generate(
                      (sessions.length - 1) * 2 - 1,
                      (index) {
                        if (index.isOdd) {
                          return Divider(
                            height: 1,
                            indent: 18,
                            endIndent: 18,
                            color: colors.divider,
                          );
                        }
                        final session = sessions[(index ~/ 2) + 1];
                        return _QueuedSessionRow(
                          session: session,
                          accent: accentFor(session),
                          sessionCount: countFor(session),
                          onStart: () => onStart(session),
                          onLog: () => onLog(session),
                        );
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              const _SectionTitle(
                title: 'Browse sessions',
                detail: 'Find a different practice when your needs change.',
              ),
              const SizedBox(height: 8),
              _RecoverySurface(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _LibraryRow(
                      icon: Icons.graphic_eq_rounded,
                      title: 'Speech sessions',
                      detail: 'Voice, clarity, breath, and pace',
                      color: colors.primary,
                      onTap: () {
                        HapticUtils.lightImpact();
                        Navigator.of(context).push(
                          buildSubtleFadeRoute(page: const SpeechScreen()),
                        );
                      },
                    ),
                    Divider(
                      height: 1,
                      indent: 18,
                      endIndent: 18,
                      color: colors.divider,
                    ),
                    _LibraryRow(
                      key: exerciseCardKey,
                      icon: Icons.accessibility_new_rounded,
                      title: 'Physical sessions',
                      detail: 'Mobility, balance, and strength',
                      color: colors.secondary,
                      onTap: () {
                        HapticUtils.lightImpact();
                        Navigator.of(context).push(
                          buildSubtleFadeRoute(page: const ExerciseScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeeklyPlanPanel extends StatelessWidget {
  final Singleton singleton;
  final VoidCallback onEditGoals;

  const _WeeklyPlanPanel({required this.singleton, required this.onEditGoals});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final speechGoal = singleton.weeklySpeechExerciseGoal;
    final physicalGoal = singleton.weeklyPhysicalExerciseGoal;
    final speechDone = singleton.weeklySpeechExerciseSessions;
    final physicalDone = singleton.weeklyPhysicalExerciseSessions;
    final goal = speechGoal + physicalGoal;
    final done = speechDone + physicalDone;
    final progress = goal == 0 ? 0.0 : (done / goal).clamp(0, 1).toDouble();
    final percent = (progress * 100).round();
    final remaining = math.max(0, goal - done);
    final progressLabel = goal == 0
        ? 'No weekly goal'
        : done >= goal
        ? 'Weekly goal complete'
        : done == 0
        ? '$goal sessions planned'
        : '$done complete · $remaining left';
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return _RecoverySurface(
      elevated: true,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'This week',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: onEditGoals,
                child: const Text('Edit goal'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label: '$percent percent of weekly recovery goal',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: Text(
                    '$percent%',
                    key: ValueKey(percent),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      height: 0.95,
                      letterSpacing: -1.8,
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    progressLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: progress),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => LinearProgressIndicator(
                minHeight: 7,
                value: value,
                backgroundColor: colors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation(colors.textPrimary),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _PracticeCount(
                  icon: Icons.graphic_eq_rounded,
                  label: 'Speech',
                  completed: speechDone,
                  goal: speechGoal,
                  color: colors.primary,
                ),
              ),
              SizedBox(
                height: 38,
                child: VerticalDivider(width: 32, color: colors.divider),
              ),
              Expanded(
                child: _PracticeCount(
                  icon: Icons.accessibility_new_rounded,
                  label: 'Movement',
                  completed: physicalDone,
                  goal: physicalGoal,
                  color: colors.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PracticeCount extends StatelessWidget {
  final IconData icon;
  final String label;
  final int completed;
  final int goal;
  final Color color;

  const _PracticeCount({
    required this.icon,
    required this.label,
    required this.completed,
    required this.goal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                goal == 0 ? '$completed logged' : '$completed / $goal',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NextSessionCard extends StatelessWidget {
  final _RecoverySession session;
  final Color accent;
  final int sessionCount;
  final VoidCallback onStart;
  final VoidCallback onLog;

  const _NextSessionCard({
    required this.session,
    required this.accent,
    required this.sessionCount,
    required this.onStart,
    required this.onLog,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _RecoverySurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: AspectRatio(
              aspectRatio: 16 / 7.4,
              child: Image.network(
                session.thumbnailUrl,
                fit: BoxFit.cover,
                cacheWidth: 720,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : ColoredBox(color: colors.surfaceVariant),
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: colors.surfaceVariant,
                  child: Icon(
                    session.icon,
                    size: 32,
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(session.icon, size: 17, color: accent),
                    const SizedBox(width: 7),
                    Text(
                      session.typeLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (session.duration.isNotEmpty) ...[
                      Text(
                        '  ·  ',
                        style: TextStyle(color: colors.textTertiary),
                      ),
                      Text(
                        session.duration,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: colors.textTertiary),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      sessionCount == 0 ? 'Not logged' : '$sessionCount× done',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: sessionCount == 0
                            ? colors.textTertiary
                            : colors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  session.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                  ),
                ),
                if (session.description.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    session.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: onStart,
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.textPrimary,
                      foregroundColor: colors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Start session'),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: TextButton.icon(
                    onPressed: onLog,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Log a completed session'),
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

class _QueuedSessionRow extends StatelessWidget {
  final _RecoverySession session;
  final Color accent;
  final int sessionCount;
  final VoidCallback onStart;
  final VoidCallback onLog;

  const _QueuedSessionRow({
    required this.session,
    required this.accent,
    required this.sessionCount,
    required this.onStart,
    required this.onLog,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 15, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(session.icon, color: accent, size: 20),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${session.typeLabel}${session.duration.isEmpty ? '' : ' · ${session.duration}'}${sessionCount == 0 ? '' : ' · $sessionCount× done'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onLog, child: const Text('Log done')),
              const SizedBox(width: 2),
              TextButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Start'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LibraryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Color color;
  final VoidCallback onTap;

  const _LibraryRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: '$title. $detail',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 15, 12, 15),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.textTertiary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryView extends StatelessWidget {
  final Singleton singleton;
  final Future<void> Function(Map<String, dynamic> session) onDelete;

  const _HistoryView({
    super.key,
    required this.singleton,
    required this.onDelete,
  });

  DateTime _sessionDate(Map<String, dynamic> session) {
    return DateTime.tryParse(
          session['completed_at']?.toString() ?? '',
        )?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sessions =
        singleton.recoverySessions
            .map((session) => Map<String, dynamic>.from(session))
            .toList()
          ..sort((a, b) => _sessionDate(b).compareTo(_sessionDate(a)));

    return CustomScrollView(
      key: const PageStorageKey('recovery-history-scroll'),
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          sliver: SliverList.list(
            children: [
              _WeeklyActivity(singleton: singleton),
              const SizedBox(height: 28),
              _SectionTitle(
                title: 'Session history',
                detail: sessions.isEmpty
                    ? 'Completed sessions will appear here.'
                    : '${sessions.length} completed ${sessions.length == 1 ? 'session' : 'sessions'}',
              ),
              const SizedBox(height: 8),
              if (sessions.isEmpty)
                _RecoverySurface(
                  child: Text(
                    'Nothing logged yet. Return to Plan when you are ready to practice.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (sessions.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 34),
            sliver: SliverList.separated(
              itemCount: sessions.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: colors.divider),
              itemBuilder: (context, index) => _HistoryRow(
                session: sessions[index],
                onDelete: () => onDelete(sessions[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _WeeklyActivity extends StatelessWidget {
  final Singleton singleton;

  const _WeeklyActivity({required this.singleton});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final today = DateUtils.dateOnly(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final values = List<int>.filled(7, 0);

    for (final session in singleton.recoverySessions) {
      final date = DateTime.tryParse(
        session['completed_at']?.toString() ?? '',
      )?.toLocal();
      if (date == null) continue;
      final day = DateUtils.dateOnly(date);
      final index = day.difference(monday).inDays;
      if (index >= 0 && index < values.length) values[index] += 1;
    }

    final total = values.fold<int>(0, (sum, value) => sum + value);
    final maximum = math.max(1, values.reduce(math.max));
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return _RecoverySurface(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity this week',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            total == 0
                ? 'No sessions logged yet'
                : '$total ${total == 1 ? 'session' : 'sessions'} completed',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List<Widget>.generate(7, (index) {
                final ratio = values[index] / maximum;
                final isToday = index == today.difference(monday).inDays;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: ratio),
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) => Container(
                              width: 7,
                              height: math.max(3, 58 * value),
                              decoration: BoxDecoration(
                                color: values[index] == 0
                                    ? colors.divider
                                    : colors.textPrimary,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        labels[index],
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: isToday
                              ? colors.textPrimary
                              : colors.textTertiary,
                          fontWeight: isToday
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback onDelete;

  const _HistoryRow({required this.session, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isPhysical =
        session['type']?.toString() == Singleton.recoveryTypePhysical;
    final accent = isPhysical ? colors.secondary : colors.primary;
    final icon = isPhysical
        ? Icons.accessibility_new_rounded
        : Icons.graphic_eq_rounded;
    final date = DateTime.tryParse(
      session['completed_at']?.toString() ?? '',
    )?.toLocal();
    final title = session['title']?.toString().trim().isNotEmpty == true
        ? session['title'].toString()
        : isPhysical
        ? 'Movement session'
        : 'Speech session';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 21),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  date == null ? 'Date unavailable' : _formatHistoryDate(date),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove $title from history',
            onPressed: onDelete,
            icon: Icon(
              Icons.delete_outline_rounded,
              color: colors.textTertiary,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String detail;

  const _SectionTitle({required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          detail,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _RecoverySurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool elevated;

  const _RecoverySurface({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _GoalEditorSheet extends StatefulWidget {
  final int speechGoal;
  final int physicalGoal;
  final void Function(int speech, int physical) onSave;

  const _GoalEditorSheet({
    required this.speechGoal,
    required this.physicalGoal,
    required this.onSave,
  });

  @override
  State<_GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends State<_GoalEditorSheet> {
  late int _speech = widget.speechGoal;
  late int _physical = widget.physicalGoal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Weekly goal',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a target that feels realistic. You can change it at any time.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            _GoalEditorRow(
              icon: Icons.graphic_eq_rounded,
              label: 'Speech sessions',
              value: _speech,
              color: colors.primary,
              onDecrease: () {
                if (_speech == 0) return;
                HapticUtils.selectionClick();
                setState(() => _speech -= 1);
              },
              onIncrease: () {
                if (_speech == 14) return;
                HapticUtils.selectionClick();
                setState(() => _speech += 1);
              },
            ),
            Divider(height: 1, color: colors.divider),
            _GoalEditorRow(
              icon: Icons.accessibility_new_rounded,
              label: 'Movement sessions',
              value: _physical,
              color: colors.secondary,
              onDecrease: () {
                if (_physical == 0) return;
                HapticUtils.selectionClick();
                setState(() => _physical -= 1);
              },
              onIncrease: () {
                if (_physical == 14) return;
                HapticUtils.selectionClick();
                setState(() => _physical += 1);
              },
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () {
                  widget.onSave(_speech, _physical);
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colors.textPrimary,
                  foregroundColor: colors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text('Save ${_speech + _physical}-session goal'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalEditorRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  const _GoalEditorRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onDecrease,
    required this.onIncrease,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Decrease $label goal',
            onPressed: value == 0 ? null : onDecrease,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Increase $label goal',
            onPressed: value == 14 ? null : onIncrease,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}

String _formatHistoryDate(DateTime date) {
  final day = formatRecoveryDate(date);
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '$day · $hour:$minute $period';
}

extension _SafeListAccess<T> on List<T> {
  T? elementAtOrNull(int index) {
    if (index < 0 || index >= length) return null;
    return this[index];
  }
}
