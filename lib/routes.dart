import 'package:flutter/material.dart';
import 'package:parkiwell/Manage/editLog.dart';
import 'package:parkiwell/Manage/editSchedule.dart';
import 'package:parkiwell/Manage/log.dart';
import 'package:parkiwell/Manage/schedule.dart';
import 'package:parkiwell/Recovery/exercise.dart';
import 'package:parkiwell/Recovery/exerciseVideo.dart';
import 'package:parkiwell/Recovery/games.dart';
import 'package:parkiwell/Recovery/speech.dart';
import 'package:parkiwell/Recovery/speechAudio.dart';
import 'package:parkiwell/settings.dart';

final Map<String, WidgetBuilder> _routeBuilders = {
  '/editLogScreen': (context) => const EditLogScreen(),
  '/editScheduleScreen': (context) => const EditScheduleScreen(),
  '/logScreen': (context) => const LogScreen(),
  '/scheduleScreen': (context) => const ScheduleScreen(),
  '/exerciseScreen': (context) => const ExerciseScreen(),
  '/exerciseVideoScreen': (context) => const ExerciseVideo(),
  '/speechAudio': (context) => const SpeechAudio(),
  '/gamesScreen': (context) => const GamesScreen(),
  '/speechScreen': (context) => const SpeechScreen(),
  '/settingsScreen': (context) => const SettingsScreen(),
};

Route<dynamic>? onGenerateAppRoute(RouteSettings settings) {
  final builder = _routeBuilders[settings.name];
  if (builder == null) return null;

  return PageRouteBuilder(
    settings: settings,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fadeIn = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      final slideUp = Tween<Offset>(
        begin: const Offset(0, 0.02),
        end: Offset.zero,
      ).animate(fadeIn);

      final fadeOut = Tween<double>(begin: 1.0, end: 0.94).animate(
        CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic),
      );

      return FadeTransition(
        opacity: fadeIn,
        child: SlideTransition(
          position: slideUp,
          child: FadeTransition(opacity: fadeOut, child: child),
        ),
      );
    },
  );
}

// Keep plain map for route name checks (e.g. tests that inspect route keys)
var namedRoutes = _routeBuilders;
