import 'package:flutter/material.dart';
import 'package:parkiwell/motion_coach/motion_analysis.dart';
import 'package:parkiwell/motion_coach/motion_exercise_catalog.dart';
import 'package:parkiwell/singleton.dart';

import '../services/tutorial_targets.dart';
import 'recovery_library_screen.dart';

class ExerciseScreen extends StatelessWidget {
  const ExerciseScreen({super.key});

  static const _config = RecoveryLibraryConfig(
    appBarTitle: 'Physical sessions',
    headline: 'Move with confidence',
    intro:
        'Choose one guided session. Starting opens the video; logging is a separate action for exercises you have completed.',
    sectionDescription: 'Mobility, strength, balance, and daily movement.',
    guideIcon: Icons.fitness_center_rounded,
    guideTitle: 'Exercise guide',
    guideBody:
        'Move at a comfortable pace and stop if you feel pain, dizziness, or shortness of breath. Start a video when you want guidance, then log it once after you finish.',
    typeLabel: 'Physical exercise',
    typeIcon: Icons.fitness_center_rounded,
    logTypeLabel: 'Movement',
    logIcon: Icons.accessibility_new_rounded,
    startRoute: '/exerciseVideoScreen',
  );

  @override
  Widget build(BuildContext context) {
    final singleton = Singleton();
    return RecoveryLibraryScreen(
      config: _config,
      catalog: singleton.exercises,
      accentOf: (colors) => colors.secondary,
      sessionCountForVideo: singleton.exerciseSessionCountForVideo,
      recordSession: (videoId, completedAt) => singleton
          .recordPhysicalExerciseSession(videoId, completedAt: completedAt),
      badgeLabelForVideo: (videoId) =>
          motionCoachAvailable && motionExerciseForVideo(videoId) != null
          ? 'Motion check'
          : null,
      firstCardKey: TutorialTargets.firstExerciseCardKey,
    );
  }
}
