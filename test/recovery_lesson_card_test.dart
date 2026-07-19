import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/theme/app_theme.dart';
import 'package:parkiwell/widgets/recovery_lesson_card.dart';

void main() {
  testWidgets('shows an accessible optional capability badge', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        home: Scaffold(
          body: RecoveryLessonCard(
            title: "Sit 'n' Fit Workout",
            description: 'Chair-based movement.',
            duration: '14:05',
            source: "Parkinson's Foundation",
            thumbnailUrl: '',
            typeLabel: 'Physical exercise',
            badgeLabel: 'Motion check',
            typeIcon: Icons.fitness_center_rounded,
            accent: Colors.teal,
            sessionCount: 0,
            onStart: () {},
            onLog: () async {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Motion check'), findsOneWidget);
    final node = tester.getSemantics(find.text('Motion check'));
    expect(node.label, contains('Motion check'));
    expect('Motion check'.allMatches(node.label), hasLength(1));
    semantics.dispose();
  });
}
