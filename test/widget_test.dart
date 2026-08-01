import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/Main/manage.dart';
import 'package:parkiwell/Main/recovery.dart';
import 'package:parkiwell/Main/editProfile.dart';
import 'package:parkiwell/Manage/editLog.dart';
import 'package:parkiwell/Manage/schedule.dart';
import 'package:parkiwell/linechart.dart';
import 'package:parkiwell/main.dart';
import 'package:parkiwell/navbar.dart';
import 'package:parkiwell/routes.dart';
import 'package:parkiwell/screens/splash_screen.dart';
import 'package:parkiwell/screens/onboarding_flow.dart';
import 'package:parkiwell/singleton.dart';
import 'package:parkiwell/theme/app_theme.dart';
import 'package:parkiwell/widgets/parkiwell_mark.dart';
import 'package:parkiwell/widgets/modern_button.dart';
import 'package:parkiwell/widgets/password_update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Singleton singleton;

  Future<void> pumpTestApp(WidgetTester tester, {required Widget home}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        themeMode: ThemeMode.light,
        routes: namedRoutes,
        home: home,
      ),
    );
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    singleton = Singleton();
  });

  setUp(() {
    singleton.log.clear();
    singleton.logIDs.clear();
    singleton.schedule.clear();
    singleton.scheduleIDs.clear();
    singleton.medicationEvents.clear();
    singleton.name = '[Name]';
    singleton.email = '[Email]';
    singleton.firstTime = true;
    singleton.page = 0;
    singleton.currentURL = '';
    singleton.exerNum = 0;
    singleton.postNum = 0;
    singleton.recoverySessions.clear();
    singleton.weeklySpeechExerciseGoal = 4;
    singleton.weeklyPhysicalExerciseGoal = 4;
  });

  testWidgets('Enhanced splash renders branded UI elements', (tester) async {
    await pumpTestApp(tester, home: SplashScreen(onComplete: () {}));

    expect(find.text('ParkiWell'), findsOneWidget);
    expect(find.byType(ParkiWellMark), findsOneWidget);
    expect(find.text('Preparing your care workspace'), findsOneWidget);
    expect(
      find.text('Personalized Parkinson\'s care,\norganized every day.'),
      findsOneWidget,
    );

    // Flush the delayed start timer used by splash animation bootstrap.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('App boots through splash into landing for first-time users', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    // Splash is shown first.
    expect(find.text('Preparing your care workspace'), findsOneWidget);
    expect(find.text('Create my care plan'), findsNothing);

    // Advance through splash entry, exit, and the fade into the landing.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Create my care plan'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });

  testWidgets('Landing buttons lead directly to the auth screen', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    // Through splash.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 600));

    // Finish landing entrance, then tap Sign In.
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.tap(find.text('I already have an account'));

    // Landing exit fade + animated hand-off into the auth stage.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('Sign up walks through name, goals, then account stages', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    // Through splash.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(milliseconds: 600));

    // Finish landing entrance, then start the journey.
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.tap(find.text('Create my care plan'));

    // Landing exit fade + animated hand-off into the profile stage.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Set up your profile'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'First name'), 'Ada');
    await tester.enterText(
      find.widgetWithText(TextField, 'Last name'),
      'Lovelace',
    );
    await tester.tap(find.text('Continue to Goals'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Set therapy goals'), findsOneWidget);
    expect(find.text('Speech exercises'), findsOneWidget);
    expect(find.text('Physical exercises'), findsOneWidget);

    // Bump the speech goal once and continue.
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    await tester.tap(find.text('Continue to Account'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Create your account'), findsOneWidget);
    expect(singleton.weeklySpeechExerciseGoal, equals(5));
    expect(singleton.weeklyPhysicalExerciseGoal, equals(4));
  });

  testWidgets('Sign in validation stays attached to the relevant fields', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      home: EditProfileScreen(startInSignIn: true, onBack: () {}),
    );

    await tester.tap(find.text('Sign In with Email'));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Use at least 6 characters.'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('Sign in offers password recovery with email validation', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      home: EditProfileScreen(startInSignIn: true, onBack: () {}),
    );

    expect(find.text('Forgot password?'), findsOneWidget);
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();

    expect(
      find.text('Enter your email to reset your password.'),
      findsOneWidget,
    );
  });

  testWidgets('Password update dialog validates the new password', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showPasswordUpdateDialog(context),
          child: const Text('Open password update'),
        ),
      ),
    );

    await tester.tap(find.text('Open password update'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'short',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm new password'),
      'short',
    );
    await tester.tap(find.text('Update password'));
    await tester.pump();

    expect(find.text('Use at least 8 characters.'), findsOneWidget);
  });

  testWidgets('Dashboard icons are not wrapped in decorative tiles', (
    tester,
  ) async {
    await pumpTestApp(tester, home: const Scaffold(body: LineChartSample1()));
    await tester.pump(const Duration(milliseconds: 700));

    for (final icon in <IconData>[
      Icons.favorite_rounded,
      Icons.medication_rounded,
      Icons.show_chart_rounded,
      Icons.medication_outlined,
    ]) {
      Widget? immediateAncestor;
      tester.element(find.byIcon(icon).first).visitAncestorElements((element) {
        immediateAncestor = element.widget;
        return false;
      });

      expect(
        immediateAncestor,
        isA<Row>(),
        reason: '$icon should be rendered directly without an icon tile.',
      );
    }

    Widget? dropdownImmediateAncestor;
    tester.element(find.byType(DropdownButton<String>)).visitAncestorElements((
      element,
    ) {
      dropdownImmediateAncestor = element.widget;
      return false;
    });
    expect(
      dropdownImmediateAncestor,
      isA<DropdownButtonHideUnderline>(),
      reason: 'The time selector should not be wrapped in a filled pill.',
    );
  });

  testWidgets('Onboarding remains usable with larger text on a small phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: OnboardingFlowScreen(onComplete: () {}),
      ),
    );

    expect(
      find.text('A calmer way to manage Parkinson\'s care'),
      findsOneWidget,
    );
    expect(find.text('Create my care plan'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(Scrollable), findsNothing);

    final primaryAction = tester.getRect(
      find.widgetWithText(FilledButton, 'Create my care plan'),
    );
    final signInAction = tester.getRect(
      find.widgetWithText(OutlinedButton, 'I already have an account'),
    );
    expect(primaryAction.height, equals(50));
    expect(signInAction.height, equals(48));
    expect(primaryAction.top, greaterThan(600));
    expect(signInAction.bottom, lessThanOrEqualTo(812));
    expect(tester.takeException(), isNull);
  });

  test('Recovery catalog keeps valid YouTube IDs', () {
    final idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
    for (final id in singleton.exercises.keys) {
      expect(
        idPattern.hasMatch(id),
        isTrue,
        reason: 'Invalid exercise ID: $id',
      );
    }
    for (final id in singleton.speeches.keys) {
      expect(idPattern.hasMatch(id), isTrue, reason: 'Invalid speech ID: $id');
    }
  });

  test('Named routes contain all feature entry points', () {
    expect(
      namedRoutes.keys,
      containsAll(<String>{
        '/editLogScreen',
        '/editScheduleScreen',
        '/logScreen',
        '/scheduleScreen',
        '/exerciseScreen',
        '/exerciseVideoScreen',
        '/speechAudio',
        '/gamesScreen',
        '/speechScreen',
        '/settingsScreen',
      }),
    );
  });

  test('Log sorting keeps log IDs aligned with entries', () {
    singleton.log.addAll(<List<String>>[
      <String>['09:00, 01 January 2024', 'Tremor', 'Mild'],
      <String>['10:00, 05 January 2024', 'Balance', 'Moderate'],
    ]);
    singleton.logIDs.addAll(<String>['id-old', 'id-new']);

    singleton.sortTime(descending: true);

    expect(singleton.log.first[1], equals('Balance'));
    expect(singleton.logIDs.first, equals('id-new'));
    expect(singleton.log.last[1], equals('Tremor'));
    expect(singleton.logIDs.last, equals('id-old'));
  });

  test('Medication aggregation calculates daily totals', () {
    singleton.schedule.addAll(<List<String>>[
      <String>['Levodopa', '100mg', 'Everyday'],
      <String>['Carbidopa', '25mg', 'Every Monday, Wednesday, Friday'],
    ]);

    singleton.calcMeds();

    expect(singleton.medsPerDay['Monday'], equals(2));
    expect(singleton.medsPerDay['Tuesday'], equals(1));
    expect(singleton.medsPerDay['Wednesday'], equals(2));
    expect(singleton.medsPerDay['Friday'], equals(2));
    expect(singleton.medsPerDay['Sunday'], equals(1));
  });

  test('Recovery tracking counts repeated therapy sessions', () async {
    final exerciseId = singleton.exercises.keys.first;
    final speechId = singleton.speeches.keys.first;

    await singleton.recordPhysicalExerciseSession(exerciseId);
    await singleton.recordPhysicalExerciseSession(exerciseId);
    await singleton.recordSpeechExerciseSession(speechId);
    singleton.setTherapyGoals(weeklySpeech: 5, weeklyPhysical: 6);

    expect(singleton.exerciseSessionCountForVideo(exerciseId), equals(2));
    expect(singleton.speechSessionCountForVideo(speechId), equals(1));
    expect(singleton.weeklyPhysicalExerciseSessions, equals(2));
    expect(singleton.weeklySpeechExerciseSessions, equals(1));
    expect(singleton.weeklyPhysicalExerciseGoal, equals(6));
    expect(singleton.weeklySpeechExerciseGoal, equals(5));
    expect(singleton.exerNum, equals(3));

    final firstSessionId = singleton.recoverySessions.first['id'] as String;
    final deleted = await singleton.deleteRecoverySessionById(firstSessionId);

    expect(deleted, isTrue);
    expect(singleton.exerciseSessionCountForVideo(exerciseId), equals(1));
    expect(singleton.totalRecoverySessions, equals(2));
    expect(singleton.exerNum, equals(2));
  });

  test('Recovery sessions preserve a selected completion date', () async {
    final exerciseId = singleton.exercises.keys.first;
    final completedAt = DateTime.now().subtract(const Duration(days: 14));

    await singleton.recordPhysicalExerciseSession(
      exerciseId,
      completedAt: completedAt,
    );

    final saved = DateTime.parse(
      singleton.recoverySessions.single['completed_at'] as String,
    );
    expect(DateUtils.isSameDay(saved, completedAt), isTrue);
    expect(singleton.weeklyPhysicalExerciseSessions, equals(0));
  });

  test('Offline log save writes local state and marks pending sync', () async {
    final saved = await singleton.saveLog(
      '08:30, 12 February 2026',
      'Tremor',
      'Moderate',
    );

    expect(saved, isTrue);
    expect(singleton.log.length, equals(1));
    expect(singleton.log.first[1], equals('Tremor'));
    expect(singleton.lastSyncStatus.toLowerCase(), contains('pending'));
  });

  testWidgets('Medication action exposes and records an adherence event', (
    tester,
  ) async {
    singleton.schedule.add(<String>['Levodopa', '100mg', 'Everyday']);
    singleton.scheduleIDs.add('schedule-1');

    await pumpTestApp(tester, home: const ScheduleScreen());
    await tester.tap(find.text('Levodopa').first);
    await tester.pumpAndSettle();
    expect(find.text('Mark as Taken'), findsOneWidget);

    final takenButton = find.widgetWithText(ModernButton, 'Mark as Taken');
    await tester.ensureVisible(takenButton);
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(
      () => singleton.recordMedicationTaken(0),
    );

    expect(saved, isTrue);
    expect(singleton.medicationEvents, hasLength(1));
    expect(singleton.medicationEvents.single['status'], 'taken');
    expect(singleton.medicationEvents.single['schedule_id'], 'schedule-1');
  });

  test('Backup export and import round-trips core data', () async {
    singleton.name = 'Alex';
    singleton.email = 'alex@example.com';
    singleton.log.add(<String>['09:00, 10 February 2026', 'Fatigue', 'Mild']);
    singleton.logIDs.add('log-1');
    singleton.schedule.add(<String>['Levodopa', '100mg', 'Everyday']);
    singleton.scheduleIDs.add('schedule-1');

    final backup = singleton.exportBackupJson();

    singleton.name = '[Name]';
    singleton.email = '[Email]';
    singleton.log.clear();
    singleton.logIDs.clear();
    singleton.schedule.clear();
    singleton.scheduleIDs.clear();

    final imported = await singleton.importBackupJson(backup);

    expect(imported, isTrue);
    expect(singleton.name, equals('Alex'));
    expect(singleton.email, equals('alex@example.com'));
    expect(singleton.log.length, equals(1));
    expect(singleton.schedule.length, equals(1));
  });

  testWidgets('Manage and recovery screens expose core task flows', (
    tester,
  ) async {
    await pumpTestApp(tester, home: const ManageScreen());
    expect(find.text('Symptom Log'), findsOneWidget);
    expect(find.text('Medications'), findsOneWidget);
    final overview = tester.widget<Container>(
      find.byKey(const ValueKey('manage-overview-strip')),
    );
    expect(
      (overview.decoration as BoxDecoration).color,
      AppTheme.lightColors.cardBackground,
    );

    await pumpTestApp(tester, home: const RecoveryScreen());
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
  });

  testWidgets('Recovery logging confirms a date and History reflects saves', (
    tester,
  ) async {
    await pumpTestApp(tester, home: const RecoveryScreen());

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -560));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log a completed session'));
    await tester.pumpAndSettle();

    expect(find.text('Log completed session'), findsOneWidget);
    expect(find.text('Add to History'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);

    Navigator.of(tester.element(find.text('Log completed session'))).pop();
    await tester.pump(const Duration(milliseconds: 240));

    final exerciseId = singleton.exercises.keys.first;
    singleton.recoverySessions.add(<String, dynamic>{
      'id': 'history-preview',
      'type': Singleton.recoveryTypePhysical,
      'video_id': exerciseId,
      'title': singleton.exercises[exerciseId]!.first,
      'completed_at': DateTime.now().toIso8601String(),
    });
    await pumpTestApp(tester, home: const RecoveryScreen());

    expect(singleton.totalRecoverySessions, equals(1));
    expect(singleton.recoveryProgress, equals(0.125));

    await tester.tap(find.text('History').first);
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('Session history'), findsOneWidget);
    expect(find.textContaining('1 completed session'), findsOneWidget);
  });

  testWidgets('Symptom entry exposes historical date logging', (tester) async {
    await pumpTestApp(tester, home: const EditLogScreen());
    await tester.pumpAndSettle();

    expect(find.textContaining('2000 onward'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Select date'), findsOneWidget);
    expect(find.text('Earlier today'), findsNothing);
    expect(find.text('Yesterday'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);

    await tester.tap(find.text('Select date'));
    await tester.pumpAndSettle();
    expect(find.text('WHEN DID THIS HAPPEN?'), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Today').first);
    await tester.pump();
    await tester.tap(find.text('Time'));
    await tester.pumpAndSettle();

    expect(find.text('Choose time'), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.text('Set time'), findsOneWidget);
  });

  testWidgets('Navbar renders all primary tabs', (tester) async {
    singleton.firstTime = false;
    singleton.name = 'Test User';

    await pumpTestApp(tester, home: const Navbar());

    expect(find.text('Home'), findsWidgets);
    expect(find.text('Manage'), findsWidgets);
    expect(find.text('Recovery'), findsWidgets);
    expect(find.text('Community'), findsWidgets);
    expect(find.text('Profile'), findsWidgets);
  });
}
