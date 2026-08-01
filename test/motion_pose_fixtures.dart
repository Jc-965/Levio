import 'dart:math' as math;

import 'package:parkiwell/motion_coach/motion_coach_session.dart';
import 'package:parkiwell/motion_coach/motion_pose_bridge.dart';

/// One rise-and-return cycle, sampled as a fraction of the peak.
const List<double> repPhase = <double>[
  0,
  0.25,
  0.5,
  0.75,
  1,
  0.75,
  0.5,
  0.25,
  0,
  0,
  0,
  0,
];

/// A fully visible, well-framed detection whose arms are raised to
/// [angleDegrees] from the trunk.
///
/// Built analytically rather than replayed from a recording so that a test's
/// expected range of motion is exact and independent of any device.
MotionPoseSample armRaiseSample(
  double angleDegrees,
  int timestampMs, {
  bool wellFramed = true,
}) {
  final List<MotionPoseLandmark> normalized = _framedNormalizedLandmarks();
  if (!wellFramed) {
    // A framing landmark below the visibility threshold classifies the
    // frame as showMoreBody without touching the world-space measurement.
    normalized[0] = const MotionPoseLandmark(
      x: 0.5,
      y: 0.18,
      z: 0,
      visibility: 0.2,
      presence: 0.2,
    );
  }
  final List<MotionPoseLandmark> world = List<MotionPoseLandmark>.generate(
    33,
    (_) =>
        const MotionPoseLandmark(x: 0, y: 0, z: 0, visibility: 1, presence: 1),
  );

  const MotionPoseLandmark leftShoulder = MotionPoseLandmark(
    x: -0.2,
    y: -0.5,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  const MotionPoseLandmark rightShoulder = MotionPoseLandmark(
    x: 0.2,
    y: -0.5,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  final double radians = angleDegrees * math.pi / 180;

  world[11] = leftShoulder;
  world[12] = rightShoulder;
  world[15] = MotionPoseLandmark(
    x: leftShoulder.x - math.sin(radians),
    y: leftShoulder.y + math.cos(radians),
    z: 0,
    visibility: 1,
    presence: 1,
  );
  world[16] = MotionPoseLandmark(
    x: rightShoulder.x + math.sin(radians),
    y: rightShoulder.y + math.cos(radians),
    z: 0,
    visibility: 1,
    presence: 1,
  );
  world[23] = const MotionPoseLandmark(
    x: -0.2,
    y: 0,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  world[24] = const MotionPoseLandmark(
    x: 0.2,
    y: 0,
    z: 0,
    visibility: 1,
    presence: 1,
  );

  return MotionPoseSample(
    detection: MotionPoseDetection(
      timestampMs: timestampMs,
      normalizedLandmarks: normalized,
      worldLandmarks: world,
      inferenceMs: 8,
    ),
    frameWidth: 480,
    frameHeight: 640,
  );
}

/// Normalized landmarks that satisfy the framing check: everything visible,
/// inside the frame, and far enough apart to read as close enough.
List<MotionPoseLandmark> _framedNormalizedLandmarks() {
  final List<MotionPoseLandmark> landmarks = List<MotionPoseLandmark>.generate(
    33,
    (_) => const MotionPoseLandmark(
      x: 0.5,
      y: 0.5,
      z: 0,
      visibility: 1,
      presence: 1,
    ),
  );
  landmarks[0] = const MotionPoseLandmark(
    x: 0.5,
    y: 0.18,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  landmarks[11] = const MotionPoseLandmark(
    x: 0.36,
    y: 0.34,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  landmarks[12] = const MotionPoseLandmark(
    x: 0.64,
    y: 0.34,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  landmarks[15] = const MotionPoseLandmark(
    x: 0.3,
    y: 0.6,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  landmarks[16] = const MotionPoseLandmark(
    x: 0.7,
    y: 0.6,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  landmarks[23] = const MotionPoseLandmark(
    x: 0.4,
    y: 0.62,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  landmarks[24] = const MotionPoseLandmark(
    x: 0.6,
    y: 0.62,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  return landmarks;
}
