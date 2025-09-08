import 'package:parkinson/Main/editProfile.dart';
import 'package:parkinson/Manage/editLog.dart';
import 'package:parkinson/Manage/editSchedule.dart';
import 'package:parkinson/Manage/log.dart';
import 'package:parkinson/Manage/schedule.dart';
import 'package:parkinson/Recovery/exercise.dart';
import 'package:parkinson/Recovery/exerciseVideo.dart';
import 'package:parkinson/Recovery/games.dart';
import 'package:parkinson/Recovery/speech.dart';
import 'package:parkinson/Recovery/speechAudio.dart';
import 'package:parkinson/navbar.dart';
import 'package:parkinson/settings.dart';

var screenRoutes = {
  '/': (context) => const Navbar(),
  '/editLogScreen': (context) => const EditLogScreen(),
  '/editScheduleScreen': (context) => const EditScheduleScreen(),
  '/logScreen': (context) => const LogScreen(),
  '/scheduleScreen': (context) => const ScheduleScreen(),
  '/exerciseScreen': (context) => const ExerciseScreen(),
  '/exerciseVideoScreen': (context) => const ExerciseVideo(),
  '/speechAudio': (context) => const SpeechAudio(),
  '/gamesScreen': (context) => const GamesScreen(),
  '/speechScreen': (context) => const SpeechScreen(),
  '/settingsScreen': (context) => const SettingsScreen()
};

var editProfileRoutes = {
  '/': (context) => const EditProfileScreen(),
};
