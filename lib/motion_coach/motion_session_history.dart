import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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
      } on Object {
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
    );
  }

  factory MotionSessionStep.fromJson(Map<String, Object?> json) =>
      MotionSessionStep(
        exerciseId: json['exercise_id']! as String,
        assessed: json['assessed']! as bool,
        completedRepetitions: (json['completed_repetitions']! as num).toInt(),
        targetRepetitions: (json['target_repetitions']! as num).toInt(),
        overallScore: (json['overall_score'] as num?)?.toDouble(),
        rangeScore: (json['range_score'] as num?)?.toDouble(),
        tempoScore: (json['tempo_score'] as num?)?.toDouble(),
        smoothnessScore: (json['smoothness_score'] as num?)?.toDouble(),
        symmetryScore: (json['symmetry_score'] as num?)?.toDouble(),
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
  };
}
