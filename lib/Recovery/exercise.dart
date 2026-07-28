import 'package:flutter/material.dart';
import 'package:parkiwell/motion_coach/motion_analysis.dart';
import 'package:parkiwell/motion_coach/motion_exercise_catalog.dart';
import 'package:parkiwell/singleton.dart';

import '../services/tutorial_targets.dart';
import '../theme/app_theme.dart';
import '../utils/haptic_utils.dart';
import '../widgets/guide_dialog.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/recovery_log_sheet.dart';
import '../widgets/recovery_lesson_card.dart';
import '../widgets/tutorial_overlay.dart';

class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen>
    with SingleTickerProviderStateMixin {
  final singleton = Singleton();
  late final List<String> _videoIds;
  late final AnimationController _introController;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _videoIds = singleton.exercises.keys.toList(growable: false);
    singleton.addListener(_onSingletonUpdate);

    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    _introController = AnimationController(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      vsync: this,
    )..forward();
    _fade = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOutCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.018),
      end: Offset.zero,
    ).animate(_fade);
  }

  @override
  void dispose() {
    singleton.removeListener(_onSingletonUpdate);
    _introController.dispose();
    super.dispose();
  }

  void _onSingletonUpdate() {
    if (mounted) setState(() {});
  }

  void _showExerciseGuide() {
    showGuideDialog(
      context,
      icon: Icons.fitness_center_rounded,
      title: 'Exercise guide',
      body:
          'Move at a comfortable pace and stop if you feel pain, dizziness, or shortness of breath. Start a video when you want guidance, then log it once after you finish.',
      footnote: 'Sources are shown on each session card.',
    );
  }

  void _showLoggedSnack(String title, int count) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$title added to your log · $count ${count == 1 ? 'session' : 'sessions'} total',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return TutorialOverlay(
      steps: const [],
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: () {
              HapticUtils.lightImpact();
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Physical sessions'),
          actions: [
            IconButton(
              tooltip: 'Exercise guide',
              onPressed: _showExerciseGuide,
              icon: const Icon(Icons.info_outline_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: LiquidBackground(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Move with confidence',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            'Choose one guided session. Starting opens the video; logging is a separate action for exercises you have completed.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colors.textSecondary,
                                  height: 1.45,
                                ),
                          ),
                          const SizedBox(height: 22),
                          const SectionHeading(
                            title: 'Session library',
                            description:
                                'Mobility, strength, balance, and daily movement.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final videoId = _videoIds[index];
                          final data = singleton.exercises[videoId]!;
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: index == _videoIds.length - 1 ? 0 : 16,
                            ),
                            child: Container(
                              key: index == 0
                                  ? TutorialTargets.firstExerciseCardKey
                                  : null,
                              child: RecoveryLessonCard(
                                title: data[0],
                                description: data[1],
                                duration: data.length > 2 ? data[2] : '',
                                source: data.length > 3 ? data[3] : '',
                                thumbnailUrl:
                                    'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                                typeLabel: 'Physical exercise',
                                badgeLabel:
                                    motionCoachEnabled &&
                                        motionExerciseForVideo(videoId) != null
                                    ? 'Motion check'
                                    : null,
                                typeIcon: Icons.fitness_center_rounded,
                                accent: colors.secondary,
                                sessionCount: singleton
                                    .exerciseSessionCountForVideo(videoId),
                                onStart: () {
                                  HapticUtils.cardTap();
                                  singleton.setCurrentUrl(videoId);
                                  Navigator.pushNamed(
                                    context,
                                    '/exerciseVideoScreen',
                                  );
                                },
                                onLog: () async {
                                  final count = await showRecoveryLogSheet(
                                    context: context,
                                    title: data[0],
                                    typeLabel: 'Movement',
                                    duration: data.length > 2 ? data[2] : '',
                                    icon: Icons.accessibility_new_rounded,
                                    accent: colors.secondary,
                                    onSave: (completedAt) =>
                                        singleton.recordPhysicalExerciseSession(
                                          videoId,
                                          completedAt: completedAt,
                                        ),
                                  );
                                  if (count == null) return;
                                  if (!mounted) return;
                                  _showLoggedSnack(data[0], count);
                                },
                              ),
                            ),
                          );
                        },
                        childCount: _videoIds.length,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
