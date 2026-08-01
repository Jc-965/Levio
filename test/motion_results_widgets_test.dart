import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/motion_coach/motion_progress_screen.dart';
import 'package:parkiwell/motion_coach/motion_routine_results_screen.dart';
import 'package:parkiwell/motion_coach/motion_session_history.dart';
import 'package:parkiwell/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<void> pump(WidgetTester tester, Widget home) =>
      tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme(), home: home));

  group('MotionRoutineResultsScreen', () {
    testWidgets('renders scores, evidence, and engine sentences', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        MotionRoutineResultsScreen(
          title: 'Seated foundation',
          record: _record(),
        ),
      );

      expect(find.text('Seated foundation'), findsOneWidget);
      // Overall and step score are legitimately both 82 here.
      expect(find.text('82'), findsWidgets);
      expect(find.text('Movement score out of 100'), findsOneWidget);
      expect(find.text('Both sides moved evenly.'), findsOneWidget);
      // Per-movement evidence chips and deterministic sentences.
      expect(find.text('Movement by movement'), findsOneWidget);
      expect(find.text('1 · 96%'), findsOneWidget);
      expect(find.text('3 · 72%'), findsOneWidget);
      expect(
        find.textContaining('median movement size measured 88%'),
        findsOneWidget,
      );
      expect(find.textContaining('75% of the first'), findsOneWidget);
      expect(find.text('Saved on this device'), findsOneWidget);
      expect(find.textContaining('not a diagnosis'), findsOneWidget);
    });

    testWidgets('says clearly when nothing could be saved', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        MotionRoutineResultsScreen(
          title: 'Seated foundation',
          record: _record(),
          saved: false,
        ),
      );

      expect(find.text('Not saved'), findsOneWidget);
      expect(
        find.textContaining('could not be written to your history'),
        findsOneWidget,
      );
    });

    testWidgets('shows the unscored state without inventing a number', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        MotionRoutineResultsScreen(
          title: 'Seated foundation',
          record: _record(score: null),
        ),
      );

      expect(
        find.text('Not enough was visible to score this session'),
        findsOneWidget,
      );
      expect(find.text('—'), findsOneWidget);
    });
  });

  group('MotionProgressScreen', () {
    testWidgets('shows the empty state before any session', (
      WidgetTester tester,
    ) async {
      final MotionSessionHistory history = MotionSessionHistory();
      await pump(tester, MotionProgressScreen(history: history));
      await tester.pumpAndSettle();

      expect(find.text('No sessions yet'), findsOneWidget);
    });

    testWidgets('summarizes saved sessions with streak and trends', (
      WidgetTester tester,
    ) async {
      final MotionSessionHistory history = MotionSessionHistory();
      await history.add(_record());
      await pump(tester, MotionProgressScreen(history: history));
      await tester.pumpAndSettle();

      // Appears as both the stat label and the list heading.
      expect(find.text('Sessions'), findsWidgets);
      expect(find.text('Day streak'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Seated foundation routine'), findsWidgets);
      // Drill-down opens the full report for the stored session.
      await tester.ensureVisible(find.text('Seated foundation routine').last);
      await tester.tap(
        find.text('Seated foundation routine').last,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Movement by movement'), findsOneWidget);
    });
  });
}

MotionSessionRecord _record({double? score = 82}) =>
    MotionSessionRecord.fromEvaluation(<String, Object?>{
      'schema_version': 'session-evaluation.v1',
      'engine_version': '0.3.0',
      'routine': <String, Object?>{
        'routine_id': 'seated_foundation',
        'routine_version': 1,
        'display_name': 'Seated foundation routine',
      },
      'steps': <Object?>[
        <String, Object?>{
          'step_index': 0,
          'exercise_id': 'seated_bilateral_lateral_arm_raise',
          'template_version': 1,
          'target_repetitions': 3,
          'completed_repetitions': 3,
          'assessed': true,
          'coverage': 0.97,
          'reason_codes': <Object?>[],
          'score': <String, Object?>{
            'overall': 82.0,
            'range': 78.0,
            'tempo': 91.0,
            'smoothness': 100.0,
            'symmetry': 94.0,
          },
          'repetitions': <Object?>[
            for (final (int index, double rom) in <(int, double)>[
              (1, 96.0),
              (2, 88.0),
              (3, 72.0),
            ])
              <String, Object?>{
                'index': index,
                'side': 'both',
                'rom_deg': rom * 0.7,
                'rom_pct_of_reference': rom,
                'tempo_s': 3.1,
                'extra_reversals': 0,
                'left_rom_deg': rom * 0.7,
                'right_rom_deg': rom * 0.68,
                'score': <String, Object?>{
                  'overall': 84.0,
                  'range': 80.0,
                  'tempo': 95.0,
                  'smoothness': 100.0,
                  'symmetry': 92.0,
                },
              },
          ],
          'cues': <Object?>[],
        },
      ],
      'overall': <String, Object?>{
        'score': score,
        'assessed_steps': 1,
        'total_steps': 1,
        'reason_codes': <Object?>[],
      },
      'summary': <String, Object?>{
        'strengths': <Object?>['Both sides moved evenly.'],
        'focus_areas': <Object?>[],
      },
    }, completedAt: DateTime.now());
