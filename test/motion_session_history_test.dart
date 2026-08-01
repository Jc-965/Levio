import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/motion_coach/motion_session_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('MotionSessionHistory', () {
    test('records a session evaluation and reloads it verbatim', () async {
      final MotionSessionHistory history = MotionSessionHistory();
      await history.record(
        _evaluation(score: 82),
        completedAt: DateTime.utc(2026, 7, 30, 9, 15),
      );

      final MotionSessionHistory reloaded = MotionSessionHistory();
      final List<MotionSessionRecord> entries = await reloaded.load();

      expect(entries, hasLength(1));
      final MotionSessionRecord entry = entries.single;
      expect(entry.routineId, 'seated_foundation');
      expect(entry.routineName, 'Seated foundation routine');
      expect(entry.overallScore, 82);
      expect(entry.assessedSteps, 1);
      expect(entry.totalSteps, 2);
      expect(entry.completedRepetitions, 3);
      expect(entry.completedAt, DateTime.utc(2026, 7, 30, 9, 15));
      expect(entry.strengths, <String>['Both sides moved evenly.']);
      expect(entry.steps.first.rangeScore, 78);
      expect(entry.steps.last.assessed, isFalse);
      expect(entry.steps.last.overallScore, isNull);
    });

    test('round-trips per-repetition evidence', () async {
      final MotionSessionHistory history = MotionSessionHistory();
      await history.record(
        _evaluation(score: 82),
        completedAt: DateTime.utc(2026, 7, 30),
      );

      final MotionSessionStep step =
          (await MotionSessionHistory().load()).single.steps.first;

      expect(step.repetitions, hasLength(3));
      expect(step.repetitions.first.romPctOfReference, 96);
      expect(step.repetitions.last.romPctOfReference, 72);
      expect(step.repetitions.first.side, 'both');
      expect(step.repetitions.first.tempoSeconds, 3.1);
      expect(step.repetitions.first.overallScore, 84);
      expect(step.amplitudeLastFirstRatio, closeTo(0.75, 1e-9));
      // The unassessed step has no reps and therefore no sequence reading.
      expect(
        (await MotionSessionHistory().load())
            .single
            .steps
            .last
            .amplitudeLastFirstRatio,
        isNull,
      );
    });

    test('states evidence deterministically from engine numbers', () async {
      final MotionSessionHistory history = MotionSessionHistory();
      await history.record(
        _evaluation(score: 82),
        completedAt: DateTime.utc(2026, 7, 30),
      );
      final MotionSessionStep step = history.entries.single.steps.first;

      expect(step.medianRomPctOfReference, 88);
      expect(step.medianTempoSeconds, closeTo(3.1, 1e-9));
      final List<String> statements = step.evidenceStatements;
      expect(statements, hasLength(3));
      expect(
        statements[0],
        'Across 3 complete movements, the median movement size measured '
        '88% of the exercise reference.',
      );
      expect(
        statements[1],
        'A complete movement took a median of 3.1 seconds.',
      );
      expect(
        statements[2],
        'The first movement measured 96% of the reference and the last '
        'measured 72% (75% of the first).',
      );
      // No reps means no invented evidence.
      expect(history.entries.single.steps.last.evidenceStatements, isEmpty);
    });

    test('keeps the newest sessions first', () async {
      final MotionSessionHistory history = MotionSessionHistory();
      await history.record(
        _evaluation(score: 60),
        completedAt: DateTime.utc(2026, 7, 29),
      );
      await history.record(
        _evaluation(score: 90),
        completedAt: DateTime.utc(2026, 7, 30),
      );

      expect(
        history.entries.map((MotionSessionRecord e) => e.overallScore),
        <double>[90, 60],
      );
    });

    test('caps stored history', () async {
      final MotionSessionHistory history = MotionSessionHistory();
      for (
        int index = 0;
        index < MotionSessionHistory.maximumEntries + 5;
        index += 1
      ) {
        await history.record(
          _evaluation(score: index.toDouble()),
          completedAt: DateTime.utc(2026, 1, 1).add(Duration(days: index)),
        );
      }

      expect(history.entries, hasLength(MotionSessionHistory.maximumEntries));
      // The oldest entries are the ones dropped.
      expect(history.entries.last.overallScore, 5);
    });

    test('averages only scored sessions', () async {
      final MotionSessionHistory history = MotionSessionHistory();
      await history.record(
        _evaluation(score: 80),
        completedAt: DateTime.utc(2026, 7, 28),
      );
      await history.record(
        _evaluation(score: null),
        completedAt: DateTime.utc(2026, 7, 29),
      );
      await history.record(
        _evaluation(score: 60),
        completedAt: DateTime.utc(2026, 7, 30),
      );

      expect(history.recentAverageScore(), 70);
      expect(history.recentAverageScore(count: 1), 60);
    });

    test('builds a per-exercise trend, newest first', () async {
      final MotionSessionHistory history = MotionSessionHistory();
      await history.record(
        _evaluation(score: 70, stepScore: 65),
        completedAt: DateTime.utc(2026, 7, 29),
      );
      await history.record(
        _evaluation(score: 90, stepScore: 88),
        completedAt: DateTime.utc(2026, 7, 30),
      );

      expect(
        history.scoreTrendFor('seated_bilateral_lateral_arm_raise'),
        <double>[88, 65],
      );
      expect(history.scoreTrendFor('sit_to_stand'), isEmpty);
    });

    test('clear removes every stored session', () async {
      final MotionSessionHistory history = MotionSessionHistory();
      await history.record(
        _evaluation(score: 80),
        completedAt: DateTime.utc(2026, 7, 30),
      );
      await history.clear();

      expect(history.entries, isEmpty);
      expect(await MotionSessionHistory().load(), isEmpty);
    });

    test('drops only the malformed entry, never the whole history', () async {
      final MotionSessionHistory writer = MotionSessionHistory();
      await writer.record(
        _evaluation(score: 80),
        completedAt: DateTime.utc(2026, 7, 29),
      );
      await writer.record(
        _evaluation(score: 90),
        completedAt: DateTime.utc(2026, 7, 30),
      );
      // Corrupt one stored entry the way a future schema change would:
      // remove a field today's parser requires.
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final List<Object?> stored =
          jsonDecode(preferences.getString(MotionSessionHistory.storageKey)!)
              as List<Object?>;
      (stored.first! as Map<String, Object?>).remove('routine_id');
      await preferences.setString(
        MotionSessionHistory.storageKey,
        jsonEncode(stored),
      );

      final List<MotionSessionRecord> entries = await MotionSessionHistory()
          .load();

      expect(entries, hasLength(1));
      expect(entries.single.overallScore, 80);
    });

    test('treats unreadable stored history as empty', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        MotionSessionHistory.storageKey: 'not json',
      });

      expect(await MotionSessionHistory().load(), isEmpty);
    });

    test('rejects a document that is not a session evaluation', () {
      expect(
        () => MotionSessionRecord.fromEvaluation(<String, Object?>{
          'schema_version': 'analysis-metrics.v1',
        }, completedAt: DateTime.utc(2026, 7, 30)),
        throwsFormatException,
      );
    });
  });
}

/// A `session-evaluation.v1` document with one assessed and one unassessed
/// step, matching what the engine emits.
Map<String, Object?> _evaluation({
  required double? score,
  double stepScore = 82,
}) => <String, Object?>{
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
        'overall': stepScore,
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
    <String, Object?>{
      'step_index': 1,
      'exercise_id': 'seated_bilateral_forward_reach',
      'template_version': 1,
      'target_repetitions': 3,
      'completed_repetitions': 0,
      'assessed': false,
      'coverage': 0.4,
      'reason_codes': <Object?>['no_complete_reps', 'low_coverage'],
      'score': null,
      'repetitions': <Object?>[],
      'cues': <Object?>[],
    },
  ],
  'overall': <String, Object?>{
    'score': score,
    'assessed_steps': 1,
    'total_steps': 2,
    'reason_codes': <Object?>[],
  },
  'summary': <String, Object?>{
    'strengths': <Object?>['Both sides moved evenly.'],
    'focus_areas': <Object?>[
      'Some steps could not be assessed; keep your whole body visible to the '
          'camera.',
    ],
  },
};
