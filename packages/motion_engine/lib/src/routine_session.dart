/// Multi-step routine sessions: step loop, rest, and the final evaluation.
///
/// Dart port of `motion_coach_cv.routine`. The state machine is driven
/// entirely by frame timestamps — it never reads a wall clock — and the
/// emitted evaluation mirrors the `session-evaluation.v1` contract field for
/// field. Cross-language behavior is pinned by the routine parity fixture.
library;

import 'dart:math' as math;

import 'exercise_specs.dart';
import 'live_exercise_coach.dart';
import 'models.dart';

const String reasonNoCompleteReps = 'no_complete_reps';
const String reasonLowCoverage = 'low_coverage';
const String reasonNoAssessedSteps = 'no_assessed_steps';

/// The complete allowlist of summary sentences. The evaluation never
/// contains user-visible text from any other source.
const Map<String, String> strengthTexts = <String, String>{
  'range': 'Movement size stayed close to the reference.',
  'tempo': 'Pacing stayed close to the reference tempo.',
  'smoothness': 'Movements were smooth and controlled.',
  'symmetry': 'Both sides moved evenly.',
};
const Map<String, String> focusTexts = <String, String>{
  'range': 'Focus on making each movement a little larger, within comfort.',
  'tempo': 'Focus on keeping a steady, comfortable pace.',
  'smoothness': 'Focus on keeping each movement smooth and continuous.',
  'symmetry': 'Focus on moving both sides evenly.',
};
const String focusVisibility =
    'Some steps could not be assessed; keep your whole body visible to the '
    'camera.';
const List<String> _componentOrder = <String>[
  'range',
  'tempo',
  'smoothness',
  'symmetry',
];

final class RoutineStepDefinition {
  RoutineStepDefinition({
    required this.exerciseId,
    required this.targetRepetitions,
    required this.maximumDurationS,
    required this.restDurationS,
  }) {
    if (exerciseId.isEmpty) {
      throw ArgumentError('exercise_id must not be empty');
    }
    if (targetRepetitions < 1) {
      throw ArgumentError('target_repetitions must be at least 1');
    }
    if (maximumDurationS <= 0) {
      throw ArgumentError('maximum_duration_s must be positive');
    }
    if (restDurationS < 0) {
      throw ArgumentError('rest_duration_s must not be negative');
    }
  }

  final String exerciseId;
  final int targetRepetitions;
  final double maximumDurationS;
  final double restDurationS;
}

final class RoutineDefinition {
  RoutineDefinition({
    required this.routineId,
    required this.routineVersion,
    required this.displayName,
    required this.steps,
  }) {
    if (routineId.isEmpty) {
      throw ArgumentError('routine_id must not be empty');
    }
    if (routineVersion < 1) {
      throw ArgumentError('routine_version must be at least 1');
    }
    if (steps.isEmpty) {
      throw ArgumentError('routine must contain at least one step');
    }
  }

  /// Build a routine from a raw `routine.v1` document, verifying every
  /// referenced exercise is registered.
  factory RoutineDefinition.fromJson(Map<String, Object?> document) {
    if (document['schema_version'] != 'routine.v1') {
      throw const FormatException('unsupported routine schema');
    }
    final List<Object?> steps = document['steps']! as List<Object?>;
    final RoutineDefinition routine = RoutineDefinition(
      routineId: document['routine_id']! as String,
      routineVersion: document['routine_version']! as int,
      displayName: document['display_name']! as String,
      steps: steps.map((Object? value) {
        final Map<String, Object?> step = value! as Map<String, Object?>;
        return RoutineStepDefinition(
          exerciseId: step['exercise_id']! as String,
          targetRepetitions: step['target_repetitions']! as int,
          maximumDurationS: (step['maximum_duration_s']! as num).toDouble(),
          restDurationS: (step['rest_duration_s']! as num).toDouble(),
        );
      }).toList(growable: false),
    );
    for (final RoutineStepDefinition step in routine.steps) {
      exerciseSpecById(step.exerciseId);
    }
    return routine;
  }

  final String routineId;
  final int routineVersion;
  final String displayName;
  final List<RoutineStepDefinition> steps;
}

enum RoutineSessionPhase { ready, active, rest, complete }

sealed class RoutineSessionEvent {
  const RoutineSessionEvent();
}

final class RoutineStepStarted extends RoutineSessionEvent {
  const RoutineStepStarted({
    required this.stepIndex,
    required this.exerciseId,
    required this.instruction,
  });

  final int stepIndex;
  final String exerciseId;
  final String instruction;
}

final class RoutineRepetitionScored extends RoutineSessionEvent {
  const RoutineRepetitionScored({
    required this.stepIndex,
    required this.repetition,
    required this.cue,
  });

  final int stepIndex;
  final LiveExerciseRepetition repetition;
  final LiveExerciseCue? cue;
}

final class RoutineRestStarted extends RoutineSessionEvent {
  const RoutineRestStarted({
    required this.completedStepIndex,
    required this.restDurationS,
  });

  final int completedStepIndex;
  final double restDurationS;
}

final class RoutineStepCompleted extends RoutineSessionEvent {
  const RoutineStepCompleted({required this.stepIndex, required this.result});

  final int stepIndex;
  final Map<String, Object?> result;
}

final class RoutineSessionCompleted extends RoutineSessionEvent {
  const RoutineSessionCompleted({required this.evaluation});

  final Map<String, Object?> evaluation;
}

/// Drive one user through every step of a routine, frame by frame.
final class RoutineSession {
  RoutineSession(
    this.routine, {
    required String engineVersion,
    required Map<String, Object?> Function(String exerciseId) templateLoader,
  }) : _engineVersion = engineVersion {
    for (final RoutineStepDefinition step in routine.steps) {
      final ExerciseSpec spec = exerciseSpecById(step.exerciseId);
      final Map<String, Object?> template = templateLoader(step.exerciseId);
      _specs.add(spec);
      _templates.add(template);
      _coaches.add(
        LiveExerciseCoach(
          spec,
          LiveExerciseCoachConfig.fromTemplateJson(template),
        ),
      );
      _stepCues.add(<String, int>{});
    }
  }

  final RoutineDefinition routine;
  final String _engineVersion;
  final List<ExerciseSpec> _specs = <ExerciseSpec>[];
  final List<Map<String, Object?>> _templates = <Map<String, Object?>>[];
  final List<LiveExerciseCoach> _coaches = <LiveExerciseCoach>[];
  final List<Map<String, int>> _stepCues = <Map<String, int>>[];
  final List<Map<String, Object?>> _stepResults = <Map<String, Object?>>[];

  RoutineSessionPhase _phase = RoutineSessionPhase.ready;
  int _stepIndex = 0;
  int? _stepStartedMs;
  int? _restUntilMs;
  Map<String, Object?>? _evaluation;

  RoutineSessionPhase get phase => _phase;
  int get currentStepIndex => _stepIndex;
  ExerciseSpec get currentSpec => _specs[_stepIndex];
  LiveExerciseCoach get currentCoach => _coaches[_stepIndex];
  RoutineStepDefinition get currentStep => routine.steps[_stepIndex];
  Map<String, Object?>? get evaluation => _evaluation;

  double restRemainingAt(int timestampMs) {
    final int? restUntil = _restUntilMs;
    if (_phase != RoutineSessionPhase.rest || restUntil == null) {
      return 0.0;
    }
    return math.max(0.0, (restUntil - timestampMs) / 1000);
  }

  /// Begin the first step at [timestampMs].
  List<RoutineSessionEvent> start(int timestampMs) {
    if (_phase != RoutineSessionPhase.ready) {
      throw StateError('session already started');
    }
    _phase = RoutineSessionPhase.active;
    _stepStartedMs = timestampMs;
    return <RoutineSessionEvent>[_stepStartedEvent()];
  }

  /// Advance the session with one camera frame.
  List<RoutineSessionEvent> addFrame(PoseFrame frame) {
    if (_phase == RoutineSessionPhase.ready) {
      throw StateError('call start() before addFrame()');
    }
    if (_phase == RoutineSessionPhase.complete) {
      return const <RoutineSessionEvent>[];
    }

    final List<RoutineSessionEvent> events = <RoutineSessionEvent>[];
    if (_phase == RoutineSessionPhase.rest) {
      final int restUntil = _restUntilMs!;
      if (frame.timestampMs < restUntil) {
        return const <RoutineSessionEvent>[];
      }
      _stepIndex += 1;
      _phase = RoutineSessionPhase.active;
      _stepStartedMs = frame.timestampMs;
      _restUntilMs = null;
      events.add(_stepStartedEvent());
    }

    final LiveExerciseCoach coach = _coaches[_stepIndex];
    final LiveExerciseDecision? decision = coach.addFrame(frame);
    if (decision != null) {
      _recordCue(decision);
      events.add(
        RoutineRepetitionScored(
          stepIndex: _stepIndex,
          repetition: decision.repetition,
          cue: decision.cue,
        ),
      );
    }

    final RoutineStepDefinition step = routine.steps[_stepIndex];
    final double elapsedS = (frame.timestampMs - _stepStartedMs!) / 1000;
    final bool repsDone =
        coach.completedRepetitions.length >= step.targetRepetitions;
    if (repsDone || elapsedS >= step.maximumDurationS) {
      events.addAll(_finishStep(frame.timestampMs));
    }
    return events;
  }

  /// End the active step now, keeping whatever was measured so far.
  ///
  /// A person who cannot do one exercise today should not have to abandon
  /// the whole routine or wait out the step's maximum duration. The step
  /// result is built by the exact rules a timeout uses: completed
  /// repetitions still count, and a step with none is simply not assessed.
  /// Mirrors the Python engine's `skip_step`.
  List<RoutineSessionEvent> skipStep(int timestampMs) {
    if (_phase != RoutineSessionPhase.active) {
      throw StateError('skipStep() requires an active step');
    }
    return _finishStep(timestampMs);
  }

  RoutineStepStarted _stepStartedEvent() {
    final ExerciseSpec spec = _specs[_stepIndex];
    return RoutineStepStarted(
      stepIndex: _stepIndex,
      exerciseId: spec.exerciseId,
      instruction: spec.instruction,
    );
  }

  void _recordCue(LiveExerciseDecision decision) {
    final LiveExerciseCue? cue = decision.cue;
    if (cue == null) {
      return;
    }
    final Map<String, int> counts = _stepCues[_stepIndex];
    counts[cue.kind.code] = (counts[cue.kind.code] ?? 0) + 1;
  }

  List<RoutineSessionEvent> _finishStep(int timestampMs) {
    final Map<String, Object?> result = _buildStepResult();
    _stepResults.add(result);
    final List<RoutineSessionEvent> events = <RoutineSessionEvent>[
      RoutineStepCompleted(stepIndex: _stepIndex, result: result),
    ];
    final bool isLast = _stepIndex + 1 >= routine.steps.length;
    if (isLast) {
      _phase = RoutineSessionPhase.complete;
      _evaluation = _buildEvaluation();
      events.add(RoutineSessionCompleted(evaluation: _evaluation!));
      return events;
    }
    final double restS = routine.steps[_stepIndex].restDurationS;
    if (restS > 0) {
      _phase = RoutineSessionPhase.rest;
      _restUntilMs = timestampMs + (restS * 1000).toInt();
      events.add(
        RoutineRestStarted(
          completedStepIndex: _stepIndex,
          restDurationS: restS,
        ),
      );
    } else {
      _stepIndex += 1;
      _stepStartedMs = timestampMs;
      events.add(_stepStartedEvent());
    }
    return events;
  }

  Map<String, Object?> _buildStepResult() {
    final RoutineStepDefinition step = routine.steps[_stepIndex];
    final ExerciseSpec spec = _specs[_stepIndex];
    final Map<String, Object?> template = _templates[_stepIndex];
    final LiveExerciseCoach coach = _coaches[_stepIndex];
    final List<LiveExerciseRepetition> repetitions = coach.completedRepetitions;
    final double coverage = coach.coverage;
    final double minimumCoverage = ((template['confidence_policy']!
            as Map<String, Object?>)['minimum_session_coverage']! as num)
        .toDouble();

    final List<String> reasonCodes = <String>[];
    if (repetitions.isEmpty) {
      reasonCodes.add(reasonNoCompleteReps);
    }
    if (coverage < minimumCoverage) {
      reasonCodes.add(reasonLowCoverage);
    }
    final bool assessed = reasonCodes.isEmpty;

    Map<String, Object?>? score;
    if (assessed) {
      final double rangeScore = _mean(
        repetitions.map((LiveExerciseRepetition rep) => rep.score.rangeScore),
      );
      final double tempoScore = _mean(
        repetitions.map((LiveExerciseRepetition rep) => rep.score.tempoScore),
      );
      final double smoothnessScore = _mean(
        repetitions
            .map((LiveExerciseRepetition rep) => rep.score.smoothnessScore),
      );
      final double? symmetryScore = _stepSymmetry(spec, repetitions);
      final double completion =
          math.min(1.0, repetitions.length / step.targetRepetitions);
      final double overall = completion *
          combineScores(rangeScore, tempoScore, smoothnessScore, symmetryScore);
      score = <String, Object?>{
        'overall': overall,
        'range': rangeScore,
        'tempo': tempoScore,
        'smoothness': smoothnessScore,
        'symmetry': symmetryScore,
      };
    }

    return <String, Object?>{
      'step_index': _stepIndex,
      'exercise_id': spec.exerciseId,
      'template_version': template['template_version']! as int,
      'target_repetitions': step.targetRepetitions,
      'completed_repetitions': repetitions.length,
      'assessed': assessed,
      'coverage': coverage,
      'reason_codes': reasonCodes,
      'score': score,
      'repetitions': repetitions
          .map(
            (LiveExerciseRepetition rep) => <String, Object?>{
              'index': rep.index,
              'side': rep.side,
              'rom_deg': rep.romDeg,
              'rom_pct_of_reference': rep.romPctOfReference,
              'tempo_s': rep.tempoS,
              'extra_reversals': rep.extraReversals,
              'left_rom_deg': rep.leftRomDeg,
              'right_rom_deg': rep.rightRomDeg,
              'score': <String, Object?>{
                'overall': rep.score.overall,
                'range': rep.score.rangeScore,
                'tempo': rep.score.tempoScore,
                'smoothness': rep.score.smoothnessScore,
                'symmetry': rep.score.symmetryScore,
              },
            },
          )
          .toList(growable: false),
      'cues': (_stepCues[_stepIndex].keys.toList()..sort())
          .map(
            (String code) => <String, Object?>{
              'code': code,
              'count': _stepCues[_stepIndex][code],
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, Object?> _buildEvaluation() {
    final List<Map<String, Object?>> assessed = _stepResults
        .where((Map<String, Object?> result) => result['assessed']! as bool)
        .toList(growable: false);
    double? overallScore;
    final List<String> overallReasons = <String>[];
    if (assessed.isNotEmpty) {
      double weightedSum = 0;
      int weightTotal = 0;
      for (final Map<String, Object?> result in assessed) {
        final int weight = result['target_repetitions']! as int;
        final Map<String, Object?> score =
            result['score']! as Map<String, Object?>;
        weightedSum += weight * (score['overall']! as double);
        weightTotal += weight;
      }
      overallScore = weightedSum / weightTotal;
    } else {
      overallReasons.add(reasonNoAssessedSteps);
    }

    final List<String> strengths = <String>[];
    final List<String> focusAreas = <String>[];
    for (final String component in _componentOrder) {
      final List<double> values = <double>[];
      for (final Map<String, Object?> result in assessed) {
        final Map<String, Object?> score =
            result['score']! as Map<String, Object?>;
        final Object? value = score[component];
        if (value != null) {
          values.add(value as double);
        }
      }
      if (values.isEmpty) {
        continue;
      }
      final double meanValue =
          values.reduce((double a, double b) => a + b) / values.length;
      if (meanValue >= 85 && strengths.length < 3) {
        strengths.add(strengthTexts[component]!);
      } else if (meanValue < 60 && focusAreas.length < 3) {
        focusAreas.add(focusTexts[component]!);
      }
    }
    if (assessed.length < _stepResults.length && focusAreas.length < 3) {
      focusAreas.add(focusVisibility);
    }

    return <String, Object?>{
      'schema_version': 'session-evaluation.v1',
      'engine_version': _engineVersion,
      'routine': <String, Object?>{
        'routine_id': routine.routineId,
        'routine_version': routine.routineVersion,
        'display_name': routine.displayName,
      },
      'steps': _stepResults,
      'overall': <String, Object?>{
        'score': overallScore,
        'assessed_steps': assessed.length,
        'total_steps': _stepResults.length,
        'reason_codes': overallReasons,
      },
      'summary': <String, Object?>{
        'strengths': strengths,
        'focus_areas': focusAreas,
      },
    };
  }
}

/// Session-level symmetry: per-rep for bilateral, across reps for
/// alternating.
double? _stepSymmetry(
  ExerciseSpec spec,
  List<LiveExerciseRepetition> repetitions,
) {
  if (spec.laterality == ExerciseLaterality.bilateralSync) {
    final List<double> values = <double>[
      for (final LiveExerciseRepetition rep in repetitions)
        if (rep.score.symmetryScore != null) rep.score.symmetryScore!,
    ];
    return values.isEmpty ? null : _mean(values);
  }
  if (spec.laterality == ExerciseLaterality.alternating) {
    final List<double> left = <double>[
      for (final LiveExerciseRepetition rep in repetitions)
        if (rep.side == 'left') rep.romDeg,
    ];
    final List<double> right = <double>[
      for (final LiveExerciseRepetition rep in repetitions)
        if (rep.side == 'right') rep.romDeg,
    ];
    if (left.isEmpty || right.isEmpty) {
      return null;
    }
    final double leftMean = _mean(left);
    final double rightMean = _mean(right);
    final double larger = math.max(leftMean, rightMean);
    if (larger <= 0) {
      return null;
    }
    return scoreSymmetry(math.min(leftMean, rightMean) / larger);
  }
  return null;
}

double _mean(Iterable<double> values) {
  final List<double> items = values.toList(growable: false);
  return items.reduce((double a, double b) => a + b) / items.length;
}
