import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:parkiwell/navbar.dart';
import 'package:parkiwell/screens/onboarding_flow.dart';
import 'package:parkiwell/singleton.dart';
import 'package:parkiwell/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Captures App Store marketing screenshots with seeded demo data.
///
/// Run on a 6.9" simulator so the PNGs come out at the store-required
/// 1320x2868:
///   flutter drive --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/app_screenshots_test.dart \
///     -d "iPhone 17 Pro Max"
Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String storageTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$hour:$minute, $day ${months[value.month - 1]} ${value.year}';
  }

  /// Keeps seeded session timestamps inside the current week so the
  /// Recovery plan shows progress regardless of the day this runs.
  DateTime withinThisWeek(DateTime candidate) {
    final now = DateTime.now();
    final startOfWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - DateTime.monday));
    return candidate.isBefore(startOfWeek)
        ? startOfWeek.add(const Duration(hours: 9))
        : candidate;
  }

  testWidgets('capture marketing screenshots', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('parkiwell_main_tutorial_completed_v1', true);

    final singleton = Singleton();
    await singleton.initialize(isProduction: false);
    singleton.setFirstTime(false);
    singleton.setName('Janet');
    singleton.setTherapyGoals(weeklySpeech: 3, weeklyPhysical: 3);

    // Local-only demo seeding: writes the public lists directly since the
    // app itself only creates entries through the synced, ID-backed APIs.
    var seededEntries = 0;
    void seedLog(String time, String symptom, String severity) {
      singleton.log.add(<String>[time, symptom, severity]);
      singleton.logIDs.add('demo-log-${seededEntries++}');
    }

    void seedSchedule(String name, String details, String days) {
      singleton.schedule.add(<String>[name, details, days]);
      singleton.scheduleIDs.add('demo-schedule-${seededEntries++}');
    }

    final now = DateTime.now();
    seedLog(
      storageTime(now.subtract(const Duration(hours: 2))),
      'Tremor',
      'Mild',
    );
    seedLog(
      storageTime(now.subtract(const Duration(hours: 6))),
      'Stiffness',
      'Moderate',
    );
    seedLog(
      storageTime(now.subtract(const Duration(days: 1, hours: 3))),
      'Fatigue',
      'Mild',
    );
    seedLog(
      storageTime(now.subtract(const Duration(days: 1, hours: 9))),
      'Tremor',
      'Very Mild',
    );
    seedLog(
      storageTime(now.subtract(const Duration(days: 2, hours: 5))),
      'Balance',
      'Moderate',
    );
    seedLog(
      storageTime(now.subtract(const Duration(days: 3, hours: 4))),
      'Stiffness',
      'Mild',
    );

    seedSchedule(
      'Carbidopa-Levodopa',
      '25/100 mg — 1 tablet, three times daily',
      'Everyday',
    );
    seedSchedule('Ropinirole', '2 mg — evening dose', 'Everyday');
    seedSchedule('Vitamin D', '1000 IU — with breakfast', 'Everyday');
    singleton.sortTime();

    await singleton.recordSpeechExerciseSession(
      '0ndTdBnVwFY',
      completedAt: withinThisWeek(now.subtract(const Duration(days: 1))),
    );
    await singleton.recordSpeechExerciseSession(
      'fJXCDDZJLDg',
      completedAt: withinThisWeek(now.subtract(const Duration(hours: 5))),
    );
    await singleton.recordPhysicalExerciseSession(
      'QbWyxn8XE-I',
      completedAt: withinThisWeek(now.subtract(const Duration(days: 2))),
    );

    Widget app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: singleton.colorMode == 0 ? ThemeMode.light : ThemeMode.dark,
      home: home,
    );

    // Screenshot pixels come from the Flutter surface, so convert it once
    // before the first capture.
    await tester.pumpWidget(app(OnboardingFlowScreen(onComplete: () {})));
    await tester.pump(const Duration(milliseconds: 300));
    await binding.convertFlutterSurfaceToImage();

    // 1. Onboarding welcome, after its entrance animation finishes.
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 50));
    await binding.takeScreenshot('01-onboarding');

    // 2. Home dashboard with seeded trends.
    await tester.pumpWidget(app(const Navbar()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    await binding.takeScreenshot('02-home');

    // 3. Manage tab.
    await tester.tap(find.text('Manage'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
    await binding.takeScreenshot('03-manage');

    // 4. Recovery tab (allow network thumbnails a moment to arrive).
    await tester.tap(find.text('Recovery'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    await binding.takeScreenshot('04-recovery');

    // 5. Home in dark mode. The harness MaterialApp reads the theme once at
    // build time, so re-pump it after switching.
    singleton.switchColorTheme(true);
    await tester.pumpWidget(app(const Navbar()));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    await binding.takeScreenshot('05-home-dark');
  });
}
