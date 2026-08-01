import 'dart:async';

import 'package:flutter/material.dart';
import 'package:motion_engine/motion_engine.dart';

import '../services/app_logger.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/modern_card.dart';
import 'motion_coach_preferences.dart';
import 'motion_exercise_catalog.dart';
import 'motion_progress_screen.dart';
import 'motion_reference_library.dart';
import 'motion_routine_catalog.dart';
import 'motion_routine_screen.dart';
import 'motion_session_history.dart';
import 'motion_session_intro_sheet.dart';

/// Entry point for guided, camera-coached movement.
///
/// Offers whole routines and single-exercise practice. Both run through the
/// same engine routine session — a single exercise is simply a one-step
/// routine — so there is one scoring path, one evaluation document, and one
/// history format regardless of what the person picks.
class MotionCoachHomeScreen extends StatefulWidget {
  const MotionCoachHomeScreen({super.key, this.library, this.history});

  final MotionReferenceLibrary? library;
  final MotionSessionHistory? history;

  @override
  State<MotionCoachHomeScreen> createState() => _MotionCoachHomeScreenState();
}

class _MotionCoachHomeScreenState extends State<MotionCoachHomeScreen> {
  final AppLogger _logger = AppLogger();
  late final MotionReferenceLibrary _library =
      widget.library ?? MotionReferenceLibrary.shared;
  late final MotionSessionHistory _history =
      widget.history ?? MotionSessionHistory();
  bool _opening = false;
  int _sessionCount = 0;
  double? _recentAverage;

  final MotionCoachPreferences _preferences = MotionCoachPreferences.shared;

  @override
  void initState() {
    super.initState();
    _preferences.addListener(_onPreferencesChanged);
    if (!_preferences.isLoaded) unawaited(_preferences.load());
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _preferences.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  void _onPreferencesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    await _history.load();
    if (!mounted) return;
    setState(() {
      _sessionCount = _history.entries.length;
      _recentAverage = _history.recentAverageScore();
    });
  }

  Future<void> _openRoutine(MotionRoutineDescription description) async {
    if (_opening) return;
    HapticUtils.mediumImpact();
    setState(() => _opening = true);
    try {
      final RoutineDefinition routine = await _library.loadRoutine(
        description.routineAssetId,
      );
      if (!mounted) return;
      final bool begin = await showMotionSessionIntro(
        context,
        description: description,
        exercises: <MotionExerciseDefinition>[
          for (final RoutineStepDefinition step in routine.steps)
            motionExerciseById(step.exerciseId),
        ],
        library: _library,
      );
      if (!begin || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MotionRoutineScreen(
            description: description,
            routine: routine,
            library: _library,
            history: _history,
          ),
        ),
      );
      await _loadHistory();
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Routine ${description.routineAssetId} failed to open',
        error,
        stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('That routine could not be opened.'),
          backgroundColor: context.colors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openSingleExercise(MotionExerciseDefinition exercise) async {
    if (_opening) return;
    HapticUtils.mediumImpact();
    setState(() => _opening = true);
    try {
      await _library.templateFor(exercise.exerciseId);
      if (!mounted) return;
      final bool begin = await showMotionSessionIntro(
        context,
        description: singleExerciseDescription(exercise),
        exercises: <MotionExerciseDefinition>[exercise],
        library: _library,
      );
      if (!begin || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MotionRoutineScreen(
            description: singleExerciseDescription(exercise),
            routine: singleExerciseRoutine(exercise),
            library: _library,
            history: _history,
          ),
        ),
      );
      await _loadHistory();
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Exercise ${exercise.exerciseId} failed to open',
        error,
        stackTrace,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('That exercise could not be opened.'),
          backgroundColor: context.colors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Motion coach'),
      ),
      body: LiquidBackground(
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ModernCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(20),
                  backgroundColor: colors.primary.withValues(alpha: 0.1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Movement with live guidance',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your phone camera counts and measures each movement '
                        'on the device itself. No video is recorded and '
                        'nothing is uploaded.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_sessionCount > 0) ...[
                  const SizedBox(height: 14),
                  ModernCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(18),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              MotionProgressScreen(history: _history),
                        ),
                      );
                      await _loadHistory();
                    },
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.insights_rounded, color: colors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Your progress',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                _recentAverage == null
                                    ? '$_sessionCount saved '
                                          '${_sessionCount == 1 ? 'session' : 'sessions'}'
                                    : '$_sessionCount saved '
                                          '${_sessionCount == 1 ? 'session' : 'sessions'} · '
                                          'recent average '
                                          '${_recentAverage!.round()}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const SectionHeading(
                  title: 'Guided routines',
                  description:
                      'A series of exercises with rests, scored as you go.',
                ),
                const SizedBox(height: 12),
                for (final MotionRoutineDescription routine
                    in motionRoutineCatalog)
                  _RoutineCard(
                    routine: routine,
                    enabled: !_opening,
                    onTap: () => unawaited(_openRoutine(routine)),
                  ),
                const SizedBox(height: 20),
                const SectionHeading(
                  title: 'Practise one exercise',
                  description:
                      'Work on a single movement with the same live coaching.',
                ),
                const SizedBox(height: 12),
                for (final MotionExerciseDefinition exercise
                    in motionExerciseCatalog)
                  _ExerciseTile(
                    exercise: exercise,
                    enabled: !_opening,
                    onTap: () => unawaited(_openSingleExercise(exercise)),
                  ),
                const SizedBox(height: 20),
                const SectionHeading(
                  title: 'Coaching preferences',
                  description:
                      'On-screen guidance always stays on; choose how else '
                      'cues are delivered.',
                ),
                const SizedBox(height: 12),
                ModernCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Column(
                    children: <Widget>[
                      SwitchListTile.adaptive(
                        value: _preferences.speechEnabled,
                        onChanged: (bool enabled) =>
                            unawaited(_preferences.setSpeechEnabled(enabled)),
                        title: const Text('Spoken cues'),
                        subtitle: const Text(
                          'Read short coaching cues aloud during a session.',
                        ),
                      ),
                      SwitchListTile.adaptive(
                        value: _preferences.hapticsEnabled,
                        onChanged: (bool enabled) =>
                            unawaited(_preferences.setHapticsEnabled(enabled)),
                        title: const Text('Vibration on each movement'),
                        subtitle: const Text(
                          'A light tap confirms every counted movement.',
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
    );
  }
}

/// A single-exercise practice session, expressed as a one-step routine so it
/// runs through exactly the same engine path as a full routine.
RoutineDefinition singleExerciseRoutine(MotionExerciseDefinition exercise) =>
    RoutineDefinition(
      routineId: 'single_${exercise.exerciseId}',
      routineVersion: 1,
      displayName: exercise.title,
      steps: <RoutineStepDefinition>[
        RoutineStepDefinition(
          exerciseId: exercise.exerciseId,
          targetRepetitions: exercise.maximumRecordingRepetitions,
          // Generous relative to the target: the step ends on the rep count
          // in practice, and a hard stop only protects against a session
          // that is not being tracked at all.
          maximumDurationS: 180,
          restDurationS: 0,
        ),
      ],
    );

MotionRoutineDescription singleExerciseDescription(
  MotionExerciseDefinition exercise,
) => MotionRoutineDescription(
  routineAssetId: 'single_${exercise.exerciseId}',
  title: exercise.title,
  summary: exercise.instructions,
  approximateMinutes: 2,
  icon: Icons.fitness_center_rounded,
  requiresStanding: exercise.posture == MotionExercisePosture.standing,
);

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.enabled,
    required this.onTap,
  });

  final MotionRoutineDescription routine;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      onTap: enabled ? onTap : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(routine.icon, color: colors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  routine.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  routine.summary,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.schedule_rounded,
                      size: 15,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      routine.durationLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    if (routine.requiresStanding) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: colors.warning,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'includes standing',
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: colors.warning),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({
    required this.exercise,
    required this.enabled,
    required this.onTap,
  });

  final MotionExerciseDefinition exercise;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ModernCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      onTap: enabled ? onTap : null,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  exercise.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${exercise.postureLabel} · '
                  '${exercise.recordingRepetitionLabel} movements',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
        ],
      ),
    );
  }
}
