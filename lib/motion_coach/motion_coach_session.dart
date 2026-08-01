import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:motion_engine/motion_engine.dart';

import 'motion_pose_bridge.dart';

const List<int> _framingLandmarks = <int>[0, 11, 12, 15, 16, 23, 24];

enum MotionFramingStatus {
  lookingForPerson,
  multiplePeople,
  showMoreBody,
  moveCloser,
  ready,
}

class MotionPoseSample {
  const MotionPoseSample({
    required this.detection,
    required this.frameWidth,
    required this.frameHeight,
  });

  final MotionPoseDetection detection;
  final int frameWidth;
  final int frameHeight;
}

/// Camera-facing state for one capture: framing readiness, the buffered pose
/// stream for offline analysis, and live coaching output.
///
/// Live coaching runs through the engine's spec-driven [LiveExerciseCoach],
/// so this class is exercise-agnostic — every threshold, cue string, and
/// score comes from the exercise's template rather than from the app.
class MotionCoachSession extends ChangeNotifier {
  MotionCoachSession({required LiveExerciseCoach liveCoach})
    : _liveCoach = liveCoach;

  final LiveExerciseCoach _liveCoach;
  final List<PoseFrame> _frames = <PoseFrame>[];
  bool _disposed = false;
  int _goodFramingFrames = 0;
  int _badFramingFrames = 0;
  int _lastTimestampMs = -1;
  bool _recording = false;
  bool _ready = false;
  int _frameWidth = 1;
  int _frameHeight = 1;
  MotionFramingStatus _framingStatus = MotionFramingStatus.lookingForPerson;
  LiveExerciseCue? _liveCue;
  int? _liveCueTimestampMs;
  int _liveRepCount = 0;
  int _liveRepSerial = 0;
  int _liveCueSerial = 0;
  ExerciseRepScore? _lastRepScore;
  int _lastDecisionMicros = 0;
  int _maximumDecisionMicros = 0;

  ExerciseSpec get exerciseSpec => _liveCoach.spec;
  bool get isRecording => _recording;
  bool get isReady => _ready;
  int get bufferedFrameCount => _frames.length;
  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;
  MotionFramingStatus get framingStatus => _framingStatus;
  LiveExerciseCue? get liveCue => _liveCue;
  int get liveRepCount => _liveRepCount;
  int get liveRepSerial => _liveRepSerial;
  int get liveCueSerial => _liveCueSerial;
  int get lastDecisionMicros => _lastDecisionMicros;
  int get maximumDecisionMicros => _maximumDecisionMicros;

  /// Score for the most recently completed repetition, or null before the
  /// first one completes.
  ExerciseRepScore? get lastRepScore => _lastRepScore;

  List<LiveExerciseRepetition> get completedRepetitions =>
      _liveCoach.completedRepetitions;

  /// Mean overall score across completed repetitions, or null when none has
  /// completed yet. Deliberately not shown while a rep is mid-flight.
  double? get averageRepScore {
    final List<LiveExerciseRepetition> reps = _liveCoach.completedRepetitions;
    if (reps.isEmpty) return null;
    double total = 0;
    for (final LiveExerciseRepetition rep in reps) {
      total += rep.score.overall;
    }
    return total / reps.length;
  }

  /// Fraction of processed frames the coach could actually measure.
  double get trackingCoverage => _liveCoach.coverage;

  /// Feed one camera sample.
  ///
  /// Listeners are notified only when something they can render changed, so
  /// the capture screen is not rebuilt at camera rate while nothing moves.
  void handleSample(MotionPoseSample sample) {
    if (_disposed) return;
    final Object before = _observableState();
    _frameWidth = math.max(1, sample.frameWidth);
    _frameHeight = math.max(1, sample.frameHeight);
    _framingStatus = assessFraming(sample.detection);
    if (_framingStatus == MotionFramingStatus.ready) {
      _goodFramingFrames += 1;
      _badFramingFrames = 0;
      if (_goodFramingFrames >= 6) {
        _ready = true;
      }
    } else {
      _badFramingFrames += 1;
      _goodFramingFrames = 0;
      if (_badFramingFrames >= 3) {
        _ready = false;
      }
    }

    if (_recording && sample.detection.timestampMs > _lastTimestampMs) {
      _lastTimestampMs = sample.detection.timestampMs;
      final PoseFrame frame = poseFrameFromDetection(sample.detection);
      _frames.add(frame);
      final Stopwatch decisionClock = Stopwatch()..start();
      final LiveExerciseDecision? decision = _liveCoach.addFrame(frame);
      decisionClock.stop();
      _lastDecisionMicros = decisionClock.elapsedMicroseconds;
      _maximumDecisionMicros = math.max(
        _maximumDecisionMicros,
        _lastDecisionMicros,
      );
      if (decision != null) {
        _liveRepCount = decision.repetition.index;
        _lastRepScore = decision.repetition.score;
        _liveRepSerial += 1;
        if (decision.cue case final LiveExerciseCue cue) {
          _liveCue = cue;
          _liveCueTimestampMs = sample.detection.timestampMs;
          _liveCueSerial += 1;
        }
      }
      // A cue is only meaningful between repetitions: drop it as soon as the
      // next rep starts or tracking is lost, so nothing stale is spoken.
      if (frame.landmarks == null ||
          _liveCoach.phase != LiveExercisePhase.idle) {
        _liveCue = null;
        _liveCueTimestampMs = null;
      }
      final int? cueTimestamp = _liveCueTimestampMs;
      if (cueTimestamp != null &&
          sample.detection.timestampMs - cueTimestamp >= 4000) {
        _liveCue = null;
        _liveCueTimestampMs = null;
      }
    }
    if (_observableState() != before) {
      notifyListeners();
    }
  }

  /// Everything the capture screen renders from this session, folded into
  /// one comparable value.
  Object _observableState() => Object.hash(
    _framingStatus,
    _ready,
    _recording,
    _liveRepCount,
    _liveRepSerial,
    _liveCueSerial,
    _liveCue,
    _frameWidth,
    _frameHeight,
  );

  void beginRecording() {
    _frames.clear();
    _lastTimestampMs = -1;
    _resetLiveCoach();
    _recording = true;
    notifyListeners();
  }

  List<PoseFrame> finishAndDrain() {
    _recording = false;
    final List<PoseFrame> result = List<PoseFrame>.unmodifiable(_frames);
    _frames.clear();
    _lastTimestampMs = -1;
    _liveCue = null;
    _liveCueTimestampMs = null;
    notifyListeners();
    return result;
  }

  void reset() {
    _frames.clear();
    _recording = false;
    _ready = false;
    _goodFramingFrames = 0;
    _badFramingFrames = 0;
    _lastTimestampMs = -1;
    _framingStatus = MotionFramingStatus.lookingForPerson;
    _resetLiveCoach();
    notifyListeners();
  }

  /// Camera teardown is asynchronous, so a straggler frame can arrive after
  /// the owning State has disposed this session. The flag turns that into a
  /// no-op instead of a notify-after-dispose error.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _resetLiveCoach() {
    _liveCoach.reset();
    _liveCue = null;
    _liveCueTimestampMs = null;
    _liveRepCount = 0;
    _liveRepSerial = 0;
    _liveCueSerial = 0;
    _lastRepScore = null;
    _lastDecisionMicros = 0;
    _maximumDecisionMicros = 0;
  }
}

/// Convert a platform detection into the engine's pose frame.
///
/// Anything short of exactly one complete pose becomes a landmark-less frame
/// rather than a partially populated one: the engine treats missing data as
/// missing and abstains, which is only sound if the adapter never
/// substitutes a plausible-looking value for an absent measurement.
PoseFrame poseFrameFromDetection(MotionPoseDetection detection) {
  if (detection.poseCount != 1 || !detection.hasCompletePose) {
    return PoseFrame(timestampMs: detection.timestampMs, landmarks: null);
  }
  final List<MotionPoseLandmark> normalized = detection.normalizedLandmarks!;
  final List<MotionPoseLandmark> world = detection.worldLandmarks!;
  return PoseFrame(
    timestampMs: detection.timestampMs,
    landmarks: List<PoseLandmark>.generate(
      33,
      (int index) => PoseLandmark(
        position: Vector3(world[index].x, world[index].y, world[index].z),
        visibility: math.min(
          normalized[index].visibility,
          normalized[index].presence,
        ),
      ),
      growable: false,
    ),
  );
}

MotionFramingStatus assessFraming(MotionPoseDetection detection) {
  if (detection.poseCount > 1) {
    return MotionFramingStatus.multiplePeople;
  }
  final List<MotionPoseLandmark>? landmarks = detection.normalizedLandmarks;
  if (landmarks == null || landmarks.length != 33) {
    return MotionFramingStatus.lookingForPerson;
  }
  for (final int index in _framingLandmarks) {
    final MotionPoseLandmark point = landmarks[index];
    if (!point.x.isFinite ||
        !point.y.isFinite ||
        point.visibility < 0.6 ||
        point.presence < 0.6 ||
        point.x < -0.05 ||
        point.x > 1.05 ||
        point.y < -0.05 ||
        point.y > 1.05) {
      return MotionFramingStatus.showMoreBody;
    }
  }
  final double shoulderSpan = (landmarks[11].x - landmarks[12].x).abs();
  final double shoulderY = (landmarks[11].y + landmarks[12].y) / 2;
  final double hipY = (landmarks[23].y + landmarks[24].y) / 2;
  if (shoulderSpan < 0.12 || (hipY - shoulderY).abs() < 0.12) {
    return MotionFramingStatus.moveCloser;
  }
  return MotionFramingStatus.ready;
}
