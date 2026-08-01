import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/Manage/log.dart';
import 'package:parkiwell/Manage/schedule.dart';
import 'package:parkiwell/navbar.dart';
import 'package:parkiwell/routes.dart';
import 'package:parkiwell/singleton.dart';
import 'package:parkiwell/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Singleton singleton;

  setUpAll(() async {
    // Mark the tutorial as completed so its modal overlay does not cover
    // the UI under test.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'parkiwell_main_tutorial_completed_v1': true,
    });
    singleton = Singleton();
  });

  setUp(() {
    singleton.firstTime = false;
    singleton.name = 'Test User';
    singleton.page = 0;
  });

  Future<void> pumpNavbar(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        themeMode: ThemeMode.light,
        routes: namedRoutes,
        home: const Navbar(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('primary navigation meets tap target guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpNavbar(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('primary navigation tap targets are labeled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpNavbar(tester);

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('nav items expose selection state to screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpNavbar(tester);

    final homeNode = tester.getSemantics(find.bySemanticsLabel('Home').first);
    expect(homeNode.flagsCollection.isButton, isTrue);
    expect(homeNode.flagsCollection.isSelected, Tristate.isTrue);

    final manageNode = tester.getSemantics(
      find.bySemanticsLabel('Manage').first,
    );
    expect(manageNode.flagsCollection.isButton, isTrue);
    expect(manageNode.flagsCollection.isSelected, Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('light theme text meets contrast guideline on navbar', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpNavbar(tester);

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  testWidgets('primary navigation survives 2x text scale without overflow', (
    tester,
  ) async {
    // Overflow errors surface as test failures, so pumping at the largest
    // common accessibility scale pins layout resilience.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        themeMode: ThemeMode.light,
        routes: namedRoutes,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: const Navbar(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Home'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('health management screens', () {
    Future<void> pumpScreen(WidgetTester tester, Widget home) async {
      singleton.log
        ..clear()
        ..add(['08:00, 1 July 2026', 'Tremor', '3']);
      singleton.logIDs
        ..clear()
        ..add('log-1');
      singleton.schedule
        ..clear()
        ..add(['Levodopa', '100mg', 'Everyday']);
      singleton.scheduleIDs
        ..clear()
        ..add('sched-1');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme(),
          darkTheme: AppTheme.darkTheme(),
          themeMode: ThemeMode.light,
          routes: namedRoutes,
          home: home,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('symptom log screen meets tap target guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, const LogScreen());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('medication schedule screen meets tap target guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, const ScheduleScreen());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('symptom log screen meets contrast guideline', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, const LogScreen());

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });

  testWidgets('dark theme text meets contrast guideline on navbar', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        themeMode: ThemeMode.dark,
        routes: namedRoutes,
        home: const Navbar(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
