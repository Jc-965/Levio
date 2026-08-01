import 'package:flutter/foundation.dart';
import 'package:motion_engine/motion_engine.dart';

import 'motion_analysis.dart';
import 'motion_coach_session.dart';
import 'motion_exercise_catalog.dart';
import 'motion_reference_library.dart';
import 'motion_skeleton_overlay.dart';

enum MotionRoutinePhase {
  /// Waiting for framing to settle before the routine may be started.
  framing,

  /// A step is running and repetitions are being scored.
  active,

  /// Between steps.
  rest,

  /// Every step finished; [MotionRoutineController.evaluation] is available.
  complete,
}

/// Drives a multi-exercise routine from the camera.
///
/// The engine's [RoutineSession] owns every decision — step advancement,
/// rest, scoring, and the final `session-evaluation.v1` document — and is
/// driven purely by frame timestamps, never a wall clock. This controller
/// only adapts camera samples into pose frames and republishes the resulting
/// state for the UI, so nothing user-visible is computed here.
class MotionRoutineController extends ChangeNotifier {
  MotionRoutineController({
    required this.routine,
    required MotionReferenceLibrary library,
    this.engineVersion = motionCoachEngineVersion,
  }) : _library = library;

  final RoutineDefinition routine;
  final MotionReferenceLibrary _library;
  final String engineVersion;

  /// Latest detected pose for the preview overlay. A separate listenable so
  /// per-frame pose updates repaint only the overlay canvas; this
  /// controller's own notifications stay gated on meaningful state changes.
  final ValueNotifier<MotionSkeletonFrame?> skeleton =
      ValueNotifier<MotionSkeletonFrame?>(null);

  RoutineSession? _session;
  bool _disposed = false;
  MotionFramingStatus _framingStatus = MotionFramingStatus.lookingForPerson;
  MotionRoutinePhase _phase = MotionRoutinePhase.framing;
  int _goodFramingFrames = 0;
  int _badFramingFrames = 0;
  bool _framingReady = false;
  int _lastTimestampMs = -1;
  int _lastSampleTimestampMs = 0;
  int _stepIndex = 0;
  int _completedReps = 0;
  int _repSerial = 0;
  int _cueSerial = 0;
  LiveExerciseCue? _cue;
  int? _cueTimestampMs;
  ExerciseRepScore? _lastRepScore;
  double _restRemainingSeconds = 0;
  Map<String, Object?>? _evaluation;

  MotionFramingStatus get framingStatus => _framingStatus;
  MotionRoutinePhase get phase => _phase;

  /// True once framing has been stable long enough to begin.
  bool get isFramingReady => _framingReady;

  bool get isStarted => _session != null;
  int get stepIndex => _stepIndex;
  int get stepCount => routine.steps.length;
  RoutineStepDefinition get currentStep => routine.steps[_stepIndex];

  MotionExerciseDefinition get currentExercise =>
      motionExerciseById(currentStep.exerciseId);

  /// The step after the current one, or null on the last step.
  RoutineStepDefinition? get nextStep => _stepIndex + 1 < routine.steps.length
      ? routine.steps[_stepIndex + 1]
      : null;

  /// During rest, the exercise the person should be setting up for.
  MotionExerciseDefinition? get upcomingExercise {
    if (_phase != MotionRoutinePhase.rest) return null;
    final RoutineStepDefinition? step = nextStep;
    return step == null ? null : motionExerciseById(step.exerciseId);
  }

  int get completedRepetitions => _completedReps;
  int get targetRepetitions => currentStep.targetRepetitions;
  int get repSerial => _repSerial;
  int get cueSerial => _cueSerial;
  LiveExerciseCue? get cue => _cue;
  ExerciseRepScore? get lastRepScore => _lastRepScore;
  double get restRemainingSeconds => _restRemainingSeconds;

  /// The `session-evaluation.v1` document, available once [phase] is
  /// [MotionRoutinePhase.complete].
  Map<String, Object?>? get evaluation => _evaluation;

  /// Fraction of the whole routine completed, for a progress indicator.
  double get progress {
    if (_phase == MotionRoutinePhase.complete) return 1;
    final int target = currentStep.targetRepetitions;
    final double withinStep = target == 0
        ? 0
        : (_completedReps / target).clamp(0.0, 1.0);
    return ((_stepIndex + withinStep) / stepCount).clamp(0.0, 1.0);
  }

  /// Begin the routine. Requires every step's template to be loaded, which
  /// [MotionReferenceLibrary.loadRoutine] guarantees.
  ///
  /// The first step starts at the most recent frame's timestamp rather than
  /// at zero: the camera clock has been running throughout framing, and
  /// seeding from zero would charge that setup time against the step's
  /// maximum duration — long enough setup would end the step before the
  /// person had moved at all.
  void start() {
    if (_session != null) return;
    final RoutineSession session = RoutineSession(
      routine,
      engineVersion: engineVersion,
      templateLoader: _library.template,
    );
    _session = session;
    _phase = MotionRoutinePhase.active;
    _stepIndex = 0;
    _completedReps = 0;
    _lastRepScore = null;
    _evaluation = null;
    _applyEvents(session.start(_lastSampleTimestampMs));
    notifyListeners();
  }

  /// Feed one camera sample.
  ///
  /// Listeners are notified only when something observable changed. Samples
  /// arrive at camera rate; notifying unconditionally would rebuild the
  /// whole session screen 15-30 times a second for no visible difference.
  void handleSample(MotionPoseSample sample) {
    if (_disposed) return;
    _lastSampleTimestampMs = sample.detection.timestampMs;
    skeleton.value = MotionSkeletonFrame.fromDetection(sample.detection);
    final Object before = _observableState();
    _updateFraming(sample);

    final RoutineSession? session = _session;
    if (session != null &&
        _phase != MotionRoutinePhase.complete &&
        sample.detection.timestampMs > _lastTimestampMs) {
      _lastTimestampMs = sample.detection.timestampMs;
      final PoseFrame frame = poseFrameFromDetection(sample.detection);
      _applyEvents(session.addFrame(frame));
      _restRemainingSeconds = session.restRemainingAt(
        sample.detection.timestampMs,
      );
      _expireCue(sample.detection.timestampMs);
    }
    if (_observableState() != before) {
      notifyListeners();
    }
  }

  /// Everything a listener can render, folded into one comparable value.
  /// Rest time is compared at the ceiled second, which is all the UI shows.
  Object _observableState() => Object.hash(
    _framingStatus,
    _framingReady,
    _phase,
    _stepIndex,
    _completedReps,
    _repSerial,
    _cueSerial,
    _cue,
    _restRemainingSeconds.ceil(),
  );

  /// Skip the active step, keeping the movements measured so far.
  /// No-op unless a step is actively running.
  void skipCurrentStep() {
    final RoutineSession? session = _session;
    if (_disposed || session == null || _phase != MotionRoutinePhase.active) {
      return;
    }
    _applyEvents(session.skipStep(_lastSampleTimestampMs));
    _restRemainingSeconds = session.restRemainingAt(_lastSampleTimestampMs);
    notifyListeners();
  }

  /// Abandon the run without an evaluation, e.g. the user backing out.
  void reset() {
    if (!_disposed) skeleton.value = null;
    _session = null;
    _phase = MotionRoutinePhase.framing;
    _framingStatus = MotionFramingStatus.lookingForPerson;
    _goodFramingFrames = 0;
    _badFramingFrames = 0;
    _framingReady = false;
    _lastTimestampMs = -1;
    _lastSampleTimestampMs = 0;
    _stepIndex = 0;
    _completedReps = 0;
    _repSerial = 0;
    _cueSerial = 0;
    _cue = null;
    _cueTimestampMs = null;
    _lastRepScore = null;
    _restRemainingSeconds = 0;
    _evaluation = null;
    notifyListeners();
  }

  void _updateFraming(MotionPoseSample sample) {
    _framingStatus = assessFraming(sample.detection);
    if (_framingStatus == MotionFramingStatus.ready) {
      _goodFramingFrames += 1;
      _badFramingFrames = 0;
      if (_goodFramingFrames >= 6) _framingReady = true;
    } else {
      _badFramingFrames += 1;
      _goodFramingFrames = 0;
      if (_badFramingFrames >= 3) _framingReady = false;
    }
  }

  void _applyEvents(List<RoutineSessionEvent> events) {
    for (final RoutineSessionEvent event in events) {
      switch (event) {
        case RoutineStepStarted(:final int stepIndex):
          _stepIndex = stepIndex;
          _completedReps = 0;
          _lastRepScore = null;
          _cue = null;
          _cueTimestampMs = null;
          _phase = MotionRoutinePhase.active;
        case RoutineRepetitionScored(
          :final LiveExerciseRepetition repetition,
          :final LiveExerciseCue? cue,
        ):
          _completedReps = repetition.index;
          _lastRepScore = repetition.score;
          _repSerial += 1;
          if (cue != null) {
            _cue = cue;
            _cueTimestampMs = repetition.endTimestampMs;
            _cueSerial += 1;
          }
        case RoutineRestStarted(:final double restDurationS):
          _phase = MotionRoutinePhase.rest;
          _restRemainingSeconds = restDurationS;
        case RoutineStepCompleted():
          break;
        case RoutineSessionCompleted(:final Map<String, Object?> evaluation):
          _phase = MotionRoutinePhase.complete;
          _evaluation = evaluation;
          _cue = null;
          _cueTimestampMs = null;
      }
    }
  }

  void _expireCue(int timestampMs) {
    final int? shownAt = _cueTimestampMs;
    if (shownAt != null && timestampMs - shownAt >= 4000) {
      _cue = null;
      _cueTimestampMs = null;
    }
  }

  /// The camera driver's frame callback is torn down asynchronously, so a
  /// straggler sample can arrive after the owning State has been disposed.
  /// The flag makes that a no-op instead of a notify-after-dispose error.
  @override
  void dispose() {
    _disposed = true;
    skeleton.dispose();
    super.dispose();
  }
}
