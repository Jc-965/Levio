import 'package:flutter/material.dart';
import 'package:parkiwell/singleton.dart';

import 'recovery_library_screen.dart';

class SpeechScreen extends StatelessWidget {
  const SpeechScreen({super.key});

  static const _config = RecoveryLibraryConfig(
    appBarTitle: 'Speech sessions',
    headline: 'Practice with intention',
    intro:
        'Choose one guided session. Starting opens the video; logging is a separate action for sessions you have completed.',
    sectionDescription: 'Voice strength, articulation, pace, and clarity.',
    guideIcon: Icons.record_voice_over_rounded,
    guideTitle: 'Speech practice guide',
    guideBody:
        'Practice in a comfortable voice, pause when you need to, and repeat sections at your own pace. Start a video for guidance, then log it once after you finish.',
    typeLabel: 'Speech practice',
    typeIcon: Icons.record_voice_over_rounded,
    logTypeLabel: 'Speech',
    logIcon: Icons.graphic_eq_rounded,
    startRoute: '/speechAudio',
  );

  @override
  Widget build(BuildContext context) {
    final singleton = Singleton();
    return RecoveryLibraryScreen(
      config: _config,
      catalog: singleton.speeches,
      accentOf: (colors) => colors.primary,
      sessionCountForVideo: singleton.speechSessionCountForVideo,
      recordSession: (videoId, completedAt) => singleton
          .recordSpeechExerciseSession(videoId, completedAt: completedAt),
    );
  }
}
