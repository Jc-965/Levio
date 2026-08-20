import 'dart:async';

import 'package:flutter/material.dart';
import 'package:motion_engine/motion_engine.dart';

import '../services/app_logger.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_card.dart';
import 'motion_demo_video_view.dart';
import 'motion_demonstration_view.dart';
import 'motion_exercise_catalog.dart';
import 'motion_reference_library.dart';
import 'motion_routine_catalog.dart';

/// Pre-session intro: watch the movement, read the setup, then start.
///
/// The coach's flow is deliberately demonstration-first. Someone should see
/// what the movement looks like and how to place the phone before the
/// camera opens, not discover both mid-session; this sheet is that step.
/// Returns true when the person chooses to start.
Future<bool> showMotionSessionIntro(
  BuildContext context, {
  required MotionRoutineDescription description,
  required RoutineDefinition routine,
  required MotionReferenceLibrary library,
}) async {
  final bool? start = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => _MotionSessionIntroSheet(
      description: description,
      routine: routine,
      library: library,
    ),
  );
  return start ?? false;
}

class _MotionSessionIntroSheet extends StatefulWidget {
  _MotionSessionIntroSheet({
    required this.description,
    required this.routine,
    required this.library,
  }) : exercises = <MotionExerciseDefinition>[
         for (final RoutineStepDefinition step in routine.steps)
           motionExerciseById(step.exerciseId),
       ];

  final MotionRoutineDescription description;
  final RoutineDefinition routine;
  final List<MotionExerciseDefinition> exercises;
  final MotionReferenceLibrary library;

  @override
  State<_MotionSessionIntroSheet> createState() =>
      _MotionSessionIntroSheetState();
}

class _MotionSessionIntroSheetState extends State<_MotionSessionIntroSheet> {
  MotionDemonstrationLoop? _loop;
  int _previewIndex = 0;

  /// Exercises whose bundled clip failed to decode on this device; they
  /// fall back to the animated guide for the rest of this sheet's life.
  final Set<String> _videoUnavailable = <String>{};

  bool _showsVideo(MotionExerciseDefinition exercise) =>
      exercise.demoVideoAsset != null &&
      !_videoUnavailable.contains(exercise.exerciseId);

  @override
  void initState() {
    super.initState();
    unawaited(_loadPreview(0));
  }

  Future<void> _loadPreview(int index) async {
    _previewIndex = index;
    try {
      final MotionDemonstrationLoop loop = await widget.library
          .loadDemonstration(widget.exercises[index].exerciseId);
      if (!mounted || _previewIndex != index) return;
      setState(() => _loop = loop);
    } on Object catch (error, stackTrace) {
      // The written instructions below remain the fallback.
      AppLogger().warning('Intro demonstration failed', error, stackTrace);
      if (!mounted || _previewIndex != index) return;
      setState(() => _loop = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final MotionExerciseDefinition previewed =
        widget.exercises[_previewIndex.clamp(0, widget.exercises.length - 1)];
    final MotionDemonstrationLoop? loop = _loop;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  children: <Widget>[
                    Text(
                      widget.description.title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.description.summary,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ModernCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: <Widget>[
                          SizedBox(
                            height: 190,
                            child: _showsVideo(previewed)
                                ? MotionDemoVideoView(
                                    key: ValueKey<String>(
                                      previewed.demoVideoAsset!,
                                    ),
                                    assetPath: previewed.demoVideoAsset!,
                                    onUnavailable: () {
                                      if (!mounted) return;
                                      setState(() {
                                        _videoUnavailable.add(
                                          previewed.exerciseId,
                                        );
                                      });
                                    },
                                  )
                                : loop == null
                                ? Center(
                                    child: Icon(
                                      Icons.accessibility_new_rounded,
                                      size: 56,
                                      color: colors.textSecondary,
                                    ),
                                  )
                                : MotionDemonstrationView(
                                    key: ValueKey<String>(loop.exerciseId),
                                    loop: loop,
                                    color: colors.primary,
                                  ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            previewed.title,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            _showsVideo(previewed)
                                ? demoVideoCreditLine
                                : 'Reference movement, repeated on a loop',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.exercises.length == 1
                          ? 'The movement'
                          : 'The movements, in order',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (
                      int index = 0;
                      index < widget.exercises.length;
                      index += 1
                    )
                      _ExerciseIntroRow(
                        index: index,
                        exercise: widget.exercises[index],
                        targetRepetitions:
                            widget.routine.steps[index].targetRepetitions,
                        selected: index == _previewIndex,
                        onTap: () => unawaited(_loadPreview(index)),
                      ),
                    const SizedBox(height: 12),
                    ModernCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(14),
                      backgroundColor: colors.primary.withValues(alpha: 0.08),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            Icons.lightbulb_outline_rounded,
                            size: 20,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Move at a comfortable pace and stay within a '
                              'range that feels safe. You can stop at any '
                              'time. Nothing is recorded; the camera only '
                              'measures your movement on this phone.',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(height: 1.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.videocam_rounded),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  label: const Text('Open camera and begin'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExerciseIntroRow extends StatelessWidget {
  const _ExerciseIntroRow({
    required this.index,
    required this.exercise,
    required this.targetRepetitions,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final MotionExerciseDefinition exercise;
  final int targetRepetitions;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ModernCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      backgroundColor: selected ? colors.primary.withValues(alpha: 0.08) : null,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${exercise.title} · ${exercise.postureLabel} · '
                  '$targetRepetitions movements',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  exercise.setupHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.play_circle_outline_rounded, color: colors.primary),
        ],
      ),
    );
  }
}
