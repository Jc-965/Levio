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

class MotionCoachSession extends ChangeNotifier {
  MotionCoachSession({LiveArmRaiseCoach? liveCoach})
    : _liveCoach =
          liveCoach ??
          LiveArmRaiseCoach(
            const LiveArmRaiseConfig(
              referenceRomDeg: 68,
              referenceTempoS: 0.964,
            ),
          );

  final LiveArmRaiseCoach _liveCoach;
  final List<PoseFrame> _frames = <PoseFrame>[];
  int _goodFramingFrames = 0;
  int _badFramingFrames = 0;
  int _lastTimestampMs = -1;
  bool _recording = false;
  bool _ready = false;
  int _frameWidth = 1;
  int _frameHeight = 1;
  MotionFramingStatus _framingStatus = MotionFramingStatus.lookingForPerson;
  LiveCueKind? _liveCue;
  int? _liveCueTimestampMs;
  int _liveRepCount = 0;
  int _liveRepSerial = 0;
  int _liveCueSerial = 0;
  int _lastDecisionMicros = 0;
  int _maximumDecisionMicros = 0;

  bool get isRecording => _recording;
  bool get isReady => _ready;
  int get bufferedFrameCount => _frames.length;
  int get frameWidth => _frameWidth;
  int get frameHeight => _frameHeight;
  MotionFramingStatus get framingStatus => _framingStatus;
  LiveCueKind? get liveCue => _liveCue;
  int get liveRepCount => _liveRepCount;
  int get liveRepSerial => _liveRepSerial;
  int get liveCueSerial => _liveCueSerial;
  int get lastDecisionMicros => _lastDecisionMicros;
  int get maximumDecisionMicros => _maximumDecisionMicros;

  void handleSample(MotionPoseSample sample) {
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
      final PoseFrame frame = _toPoseFrame(sample.detection);
      _frames.add(frame);
      final Stopwatch decisionClock = Stopwatch()..start();
      final LiveCoachDecision? decision = _liveCoach.addFrame(frame);
      decisionClock.stop();
      _lastDecisionMicros = decisionClock.elapsedMicroseconds;
      _maximumDecisionMicros = math.max(
        _maximumDecisionMicros,
        _lastDecisionMicros,
      );
      if (decision != null) {
        _liveRepCount = decision.repetition.index;
        _liveRepSerial += 1;
        if (decision.cue case final LiveCueKind cue) {
          _liveCue = cue;
          _liveCueTimestampMs = sample.detection.timestampMs;
          _liveCueSerial += 1;
        }
      }
      if (frame.landmarks == null ||
          _liveCoach.phase != LiveArmRaisePhase.idle) {
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
    notifyListeners();
  }

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

  void _resetLiveCoach() {
    _liveCoach.reset();
    _liveCue = null;
    _liveCueTimestampMs = null;
    _liveRepCount = 0;
    _liveRepSerial = 0;
    _liveCueSerial = 0;
    _lastDecisionMicros = 0;
    _maximumDecisionMicros = 0;
  }

  PoseFrame _toPoseFrame(MotionPoseDetection detection) {
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
