import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_logger.dart';

/// On-device history of completed motion routines.
///
/// Only derived numbers are kept — scores, repetition counts, and the
/// allowlisted summary sentences the engine already produced. No video, no
/// pose landmarks, and nothing that leaves the device: this store is
/// deliberately local-only, and cloud sync stays out of scope until the
/// export/deletion/RLS work is done. [clear] exists so the record is always
/// removable from inside the app.
class MotionSessionHistory {
  MotionSessionHistory({SharedPreferences? preferences})
    : _preferences = preferences;

  static const String storageKey = 'parkiwell_motion_session_history_v1';

  /// Older entries are dropped once this many are stored. Trend views only
  /// ever look at recent sessions, and an unbounded list in preferences is a
  /// startup cost nobody asked for.
  static const int maximumEntries = 60;

  SharedPreferences? _preferences;
  List<MotionSessionRecord> _entries = const <MotionSessionRecord>[];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Newest first.
  List<MotionSessionRecord> get entries => _entries;

  Future<List<MotionSessionRecord>> load() async {
    final SharedPreferences preferences = await _resolve();
    final String? raw = preferences.getString(storageKey);
    _entries = raw == null ? const <MotionSessionRecord>[] : _decode(raw);
    _loaded = true;
    return _entries;
  }

  /// Persist a completed `session-evaluation.v1` document.
  Future<MotionSessionRecord> record(
    Map<String, Object?> evaluation, {
    required DateTime completedAt,
  }) async {
    final MotionSessionRecord entry = MotionSessionRecord.fromEvaluation(
      evaluation,
      completedAt: completedAt,
    );
    await add(entry);
    return entry;
  }

  /// Persist an already-parsed record.
  Future<void> add(MotionSessionRecord entry) async {
    if (!_loaded) await load();
    final List<MotionSessionRecord> next = <MotionSessionRecord>[
      entry,
      ..._entries,
    ];
    _entries = next.length > maximumEntries
        ? next.sublist(0, maximumEntries)
        : next;
    await _write();
  }

  Future<void> clear() async {
    _entries = const <MotionSessionRecord>[];
    _loaded = true;
    final SharedPreferences preferences = await _resolve();
    await preferences.remove(storageKey);
  }

  /// Most recent score for each exercise, newest first, for a trend view.
  List<double> scoreTrendFor(String exerciseId) {
    final List<double> scores = <double>[];
    for (final MotionSessionRecord entry in _entries) {
      for (final MotionSessionStep step in entry.steps) {
        if (step.exerciseId == exerciseId && step.overallScore != null) {
          scores.add(step.overallScore!);
        }
      }
    }
    return scores;
  }

  /// Consecutive calendar days with at least one completed session, ending
  /// today or yesterday. A streak survives until a full day is missed, so
  /// this morning's not-yet-done session does not read as a broken streak.
  int currentStreakDays({DateTime? now}) {
    if (_entries.isEmpty) return 0;
    final Set<DateTime> days = <DateTime>{
      for (final MotionSessionRecord entry in _entries)
        DateTime(
          entry.completedAt.toLocal().year,
          entry.completedAt.toLocal().month,
          entry.completedAt.toLocal().day,
        ),
    };
    final DateTime local = (now ?? DateTime.now()).toLocal();
    // Calendar-safe decrement: the constructor normalizes day 0 to the last
    // day of the previous month and always lands on that day's real local
    // midnight. Subtracting a flat 24 hours would drift across daylight
    // saving transitions and read an unbroken streak as ended.
    DateTime previousDay(DateTime day) =>
        DateTime(day.year, day.month, day.day - 1);
    DateTime cursor = DateTime(local.year, local.month, local.day);
    if (!days.contains(cursor)) {
      cursor = previousDay(cursor);
      if (!days.contains(cursor)) return 0;
    }
    int streak = 0;
    while (days.contains(cursor)) {
      streak += 1;
      cursor = previousDay(cursor);
    }
    return streak;
  }

  /// Sessions completed in the seven days ending [now], inclusive.
  int sessionsInLastWeek({DateTime? now}) {
    final DateTime end = (now ?? DateTime.now()).toLocal();
    final DateTime start = end.subtract(const Duration(days: 7));
    return _entries.where((MotionSessionRecord entry) {
      final DateTime completed = entry.completedAt.toLocal();
      return completed.isAfter(start) && !completed.isAfter(end);
    }).length;
  }

  /// Mean overall score across the [count] most recent scored sessions.
  double? recentAverageScore({int count = 5}) {
    final List<double> scores = <double>[
      for (final MotionSessionRecord entry in _entries)
        if (entry.overallScore != null) entry.overallScore!,
    ];
    if (scores.isEmpty) return null;
    final List<double> window = scores.take(count).toList(growable: false);
    return window.reduce((double a, double b) => a + b) / window.length;
  }

  Future<void> _write() async {
    final SharedPreferences preferences = await _resolve();
    await preferences.setString(
      storageKey,
      jsonEncode(<Object?>[
        for (final MotionSessionRecord entry in _entries) entry.toJson(),
      ]),
    );
  }

  Future<SharedPreferences> _resolve() async =>
      _preferences ??= await SharedPreferences.getInstance();

  static List<MotionSessionRecord> _decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const <MotionSessionRecord>[];
    }
    if (decoded is! List<Object?>) return const <MotionSessionRecord>[];
    // Entries are decoded one at a time: a single record written by a future
    // or corrupted build must cost that one entry, never the whole history.
    final List<MotionSessionRecord> entries = <MotionSessionRecord>[];
    for (final Object? value in decoded) {
      try {
        entries.add(
          MotionSessionRecord.fromJson(value! as Map<String, Object?>),
        );
      } on Object catch (error, stackTrace) {
        AppLogger().warning(
          'Dropped one unreadable motion session record',
          error,
          stackTrace,
        );
        continue;
      }
    }
    return List<MotionSessionRecord>.unmodifiable(entries);
  }
}

class MotionSessionRecord {
  const MotionSessionRecord({
    required this.completedAt,
    required this.routineId,
    required this.routineName,
    required this.engineVersion,
    required this.overallScore,
    required this.assessedSteps,
    required this.totalSteps,
    required this.strengths,
    required this.focusAreas,
    required this.steps,
  });

  factory MotionSessionRecord.fromEvaluation(
    Map<String, Object?> evaluation, {
    required DateTime completedAt,
  }) {
    if (evaluation['schema_version'] != 'session-evaluation.v1') {
      throw const FormatException('unsupported evaluation schema');
    }
    final Map<String, Object?> routine =
        evaluation['routine']! as Map<String, Object?>;
    final Map<String, Object?> overall =
        evaluation['overall']! as Map<String, Object?>;
    final Map<String, Object?> summary =
        evaluation['summary']! as Map<String, Object?>;
    return MotionSessionRecord(
      completedAt: completedAt,
      routineId: routine['routine_id']! as String,
      routineName: routine['display_name']! as String,
      engineVersion: evaluation['engine_version']! as String,
      overallScore: (overall['score'] as num?)?.toDouble(),
      assessedSteps: (overall['assessed_steps']! as num).toInt(),
      totalSteps: (overall['total_steps']! as num).toInt(),
      strengths: List<String>.from(summary['strengths']! as List<Object?>),
      focusAreas: List<String>.from(summary['focus_areas']! as List<Object?>),
      steps: (evaluation['steps']! as List<Object?>)
          .map(
            (Object? value) => MotionSessionStep.fromEvaluation(
              value! as Map<String, Object?>,
            ),
          )
          .toList(growable: false),
    );
  }

  factory MotionSessionRecord.fromJson(Map<String, Object?> json) =>
      MotionSessionRecord(
        completedAt: DateTime.parse(json['completed_at']! as String),
        routineId: json['routine_id']! as String,
        routineName: json['routine_name']! as String,
        engineVersion: json['engine_version']! as String,
        overallScore: (json['overall_score'] as num?)?.toDouble(),
        assessedSteps: (json['assessed_steps']! as num).toInt(),
        totalSteps: (json['total_steps']! as num).toInt(),
        strengths: List<String>.from(json['strengths']! as List<Object?>),
        focusAreas: List<String>.from(json['focus_areas']! as List<Object?>),
        steps: (json['steps']! as List<Object?>)
            .map(
              (Object? value) =>
                  MotionSessionStep.fromJson(value! as Map<String, Object?>),
            )
            .toList(growable: false),
      );

  final DateTime completedAt;
  final String routineId;
  final String routineName;
  final String engineVersion;
  final double? overallScore;
  final int assessedSteps;
  final int totalSteps;
  final List<String> strengths;
  final List<String> focusAreas;
  final List<MotionSessionStep> steps;

  int get completedRepetitions => steps.fold<int>(
    0,
    (int total, MotionSessionStep step) => total + step.completedRepetitions,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'completed_at': completedAt.toIso8601String(),
    'routine_id': routineId,
    'routine_name': routineName,
    'engine_version': engineVersion,
    'overall_score': overallScore,
    'assessed_steps': assessedSteps,
    'total_steps': totalSteps,
    'strengths': strengths,
    'focus_areas': focusAreas,
    'steps': <Object?>[
      for (final MotionSessionStep step in steps) step.toJson(),
    ],
  };
}

class MotionSessionStep {
  const MotionSessionStep({
    required this.exerciseId,
    required this.assessed,
    required this.completedRepetitions,
    required this.targetRepetitions,
    required this.overallScore,
    required this.rangeScore,
    required this.tempoScore,
    required this.smoothnessScore,
    required this.symmetryScore,
    this.repetitions = const <MotionSessionRep>[],
  });

  factory MotionSessionStep.fromEvaluation(Map<String, Object?> step) {
    final Map<String, Object?>? score = step['score'] as Map<String, Object?>?;
    return MotionSessionStep(
      exerciseId: step['exercise_id']! as String,
      assessed: step['assessed']! as bool,
      completedRepetitions: (step['completed_repetitions']! as num).toInt(),
      targetRepetitions: (step['target_repetitions']! as num).toInt(),
      overallScore: (score?['overall'] as num?)?.toDouble(),
      rangeScore: (score?['range'] as num?)?.toDouble(),
      tempoScore: (score?['tempo'] as num?)?.toDouble(),
      smoothnessScore: (score?['smoothness'] as num?)?.toDouble(),
      symmetryScore: (score?['symmetry'] as num?)?.toDouble(),
      repetitions: (step['repetitions'] as List<Object?>? ?? const <Object?>[])
          .map(
            (Object? value) =>
                MotionSessionRep.fromEvaluation(value! as Map<String, Object?>),
          )
          .toList(growable: false),
    );
  }

  factory MotionSessionStep.fromJson(
    Map<String, Object?> json,
  ) => MotionSessionStep(
    exerciseId: json['exercise_id']! as String,
    assessed: json['assessed']! as bool,
    completedRepetitions: (json['completed_repetitions']! as num).toInt(),
    targetRepetitions: (json['target_repetitions']! as num).toInt(),
    overallScore: (json['overall_score'] as num?)?.toDouble(),
    rangeScore: (json['range_score'] as num?)?.toDouble(),
    tempoScore: (json['tempo_score'] as num?)?.toDouble(),
    smoothnessScore: (json['smoothness_score'] as num?)?.toDouble(),
    symmetryScore: (json['symmetry_score'] as num?)?.toDouble(),
    // Absent in records written before per-rep evidence was stored.
    repetitions: (json['repetitions'] as List<Object?>? ?? const <Object?>[])
        .map(
          (Object? value) =>
              MotionSessionRep.fromJson(value! as Map<String, Object?>),
        )
        .toList(growable: false),
  );

  final String exerciseId;
  final bool assessed;
  final int completedRepetitions;
  final int targetRepetitions;
  final double? overallScore;
  final double? rangeScore;
  final double? tempoScore;
  final double? smoothnessScore;
  final double? symmetryScore;

  /// Per-repetition engine evidence, oldest first. This is what makes the
  /// post-session report evidence-based rather than a bare score: observed
  /// movement size against the reference and whether amplitude held up
  /// across the set are only visible at this granularity.
  final List<MotionSessionRep> repetitions;

  /// Last complete repetition's amplitude as a fraction of the first's, or
  /// null with fewer than three reps (mirroring the engine's own rule that
  /// a sequence needs at least three points to be worth reading).
  double? get amplitudeLastFirstRatio {
    if (repetitions.length < 3) return null;
    final double first = repetitions.first.romPctOfReference;
    if (first <= 0) return null;
    return repetitions.last.romPctOfReference / first;
  }

  /// Median observed movement size across reps, as percent of the exercise
  /// reference; null with no reps.
  double? get medianRomPctOfReference => _median(<double>[
    for (final MotionSessionRep rep in repetitions) rep.romPctOfReference,
  ]);

  /// Median complete-movement duration in seconds; null with no reps.
  double? get medianTempoSeconds => _median(<double>[
    for (final MotionSessionRep rep in repetitions) rep.tempoSeconds,
  ]);

  /// Deterministic evidence sentences built only from engine measurements.
  /// Wording stays neutral and observational; nothing here scores, praises,
  /// or diagnoses, matching the engine's allowlisted-copy policy.
  List<String> get evidenceStatements {
    final List<String> statements = <String>[];
    final double? rom = medianRomPctOfReference;
    if (rom != null) {
      statements.add(
        'Across ${repetitions.length} complete '
        '${repetitions.length == 1 ? 'movement' : 'movements'}, the median '
        'movement size measured ${rom.round()}% of the exercise reference.',
      );
    }
    final double? tempo = medianTempoSeconds;
    if (tempo != null) {
      statements.add(
        'A complete movement took a median of '
        '${tempo.toStringAsFixed(1)} seconds.',
      );
    }
    final double? ratio = amplitudeLastFirstRatio;
    if (ratio != null) {
      statements.add(
        'The first movement measured '
        '${repetitions.first.romPctOfReference.round()}% of the reference '
        'and the last measured '
        '${repetitions.last.romPctOfReference.round()}% '
        '(${(ratio * 100).round()}% of the first).',
      );
    }
    return statements;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'exercise_id': exerciseId,
    'assessed': assessed,
    'completed_repetitions': completedRepetitions,
    'target_repetitions': targetRepetitions,
    'overall_score': overallScore,
    'range_score': rangeScore,
    'tempo_score': tempoScore,
    'smoothness_score': smoothnessScore,
    'symmetry_score': symmetryScore,
    'repetitions': <Object?>[
      for (final MotionSessionRep rep in repetitions) rep.toJson(),
    ],
  };
}

/// One completed repetition's engine measurements.
class MotionSessionRep {
  const MotionSessionRep({
    required this.index,
    required this.side,
    required this.romDeg,
    required this.romPctOfReference,
    required this.tempoSeconds,
    required this.overallScore,
  });

  factory MotionSessionRep.fromEvaluation(Map<String, Object?> rep) =>
      MotionSessionRep(
        index: (rep['index']! as num).toInt(),
        side: rep['side']! as String,
        romDeg: (rep['rom_deg']! as num).toDouble(),
        romPctOfReference: (rep['rom_pct_of_reference']! as num).toDouble(),
        tempoSeconds: (rep['tempo_s']! as num).toDouble(),
        overallScore:
            ((rep['score']! as Map<String, Object?>)['overall']! as num)
                .toDouble(),
      );

  factory MotionSessionRep.fromJson(Map<String, Object?> json) =>
      MotionSessionRep(
        index: (json['index']! as num).toInt(),
        side: json['side']! as String,
        romDeg: (json['rom_deg']! as num).toDouble(),
        romPctOfReference: (json['rom_pct']! as num).toDouble(),
        tempoSeconds: (json['tempo_s']! as num).toDouble(),
        overallScore: (json['score']! as num).toDouble(),
      );

  final int index;

  /// 'both' for bilateral exercises, 'left'/'right' for alternating ones.
  final String side;
  final double romDeg;
  final double romPctOfReference;
  final double tempoSeconds;
  final double overallScore;

  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'side': side,
    'rom_deg': romDeg,
    'rom_pct': romPctOfReference,
    'tempo_s': tempoSeconds,
    'score': overallScore,
  };
}

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final List<double> sorted = List<double>.of(values)..sort();
  final int middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}
