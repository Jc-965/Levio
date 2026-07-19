import 'dart:math' as math;

import 'features.dart';
import 'filtering.dart';
import 'models.dart';

enum ConfidenceLevel {
  high,
  partial,
  insufficient;

  String get serialized => name;
}

enum ReasonCode {
  lowRequiredLandmarkCoverage('low_required_landmark_coverage'),
  noFrames('no_frames'),
  noCompleteReps('no_complete_reps'),
  singleRep('single_rep'),
  partialSideFeatureCoverage('partial_side_feature_coverage'),
  noValidSideFeatures('no_valid_side_features'),
  lowSamplingRate('low_sampling_rate'),
  incompleteSessionTracking('incomplete_session_tracking'),
  bilateralMovementRequired('bilateral_movement_required'),
  poseDiscontinuity('pose_discontinuity');

  const ReasonCode(this.serialized);

  final String serialized;
}

final class CoverageAssessment {
  const CoverageAssessment({
    required this.level,
    required this.coverage,
    required this.validFrames,
    required this.totalFrames,
    required this.reasons,
  });

  final ConfidenceLevel level;
  final double coverage;
  final int validFrames;
  final int totalFrames;
  final List<ReasonCode> reasons;

  CoverageAssessment copyWith({
    ConfidenceLevel? level,
    List<ReasonCode>? reasons,
  }) =>
      CoverageAssessment(
        level: level ?? this.level,
        coverage: coverage,
        validFrames: validFrames,
        totalFrames: totalFrames,
        reasons: reasons ?? this.reasons,
      );
}

final class PoseDiscontinuityAssessment {
  const PoseDiscontinuityAssessment({
    required this.frameIndices,
    required this.maximumNormalizedSpeed,
  });

  final List<int> frameIndices;
  final double maximumNormalizedSpeed;
}

CoverageAssessment assessTrackingCoverage(
  PoseStream stream,
  List<int> requiredLandmarks, {
  double visibilityThreshold = 0.5,
  double minimumCoverage = 0.8,
}) {
  if (requiredLandmarks.isEmpty) {
    throw ArgumentError('at least one required landmark is needed');
  }
  final int totalFrames = stream.frames.length;
  if (totalFrames == 0) {
    return const CoverageAssessment(
      level: ConfidenceLevel.insufficient,
      coverage: 0,
      validFrames: 0,
      totalFrames: 0,
      reasons: <ReasonCode>[ReasonCode.noFrames],
    );
  }
  int validFrames = 0;
  for (final PoseFrame frame in stream.frames) {
    final List<PoseLandmark>? points = frame.landmarks;
    final bool valid = points != null &&
        requiredLandmarks.every((int index) {
          final PoseLandmark landmark = points[index];
          return landmark.position?.isFinite == true &&
              landmark.visibility.isFinite &&
              landmark.visibility >= visibilityThreshold;
        });
    if (valid) {
      validFrames += 1;
    }
  }
  final double coverage = validFrames / totalFrames;
  if (coverage < minimumCoverage) {
    return CoverageAssessment(
      level: ConfidenceLevel.insufficient,
      coverage: coverage,
      validFrames: validFrames,
      totalFrames: totalFrames,
      reasons: const <ReasonCode>[ReasonCode.lowRequiredLandmarkCoverage],
    );
  }
  return CoverageAssessment(
    level: ConfidenceLevel.high,
    coverage: coverage,
    validFrames: validFrames,
    totalFrames: totalFrames,
    reasons: const <ReasonCode>[],
  );
}

PoseDiscontinuityAssessment assessPoseDiscontinuities(
  PoseStream stream,
  List<int> requiredLandmarks, {
  double maximumNormalizedSpeed = 8,
  double maximumIntervalRatio = 2.5,
}) {
  if (requiredLandmarks.isEmpty) {
    throw ArgumentError('at least one required landmark is needed');
  }
  if (stream.frames.length < 2) {
    return const PoseDiscontinuityAssessment(
      frameIndices: <int>[],
      maximumNormalizedSpeed: 0,
    );
  }
  final List<int> timestamps =
      stream.frames.map((PoseFrame frame) => frame.timestampMs).toList();
  final double nominalInterval = 1000 / estimateSamplingHz(timestamps);
  final List<List<Vector3>?> normalized = stream.frames
      .map(
        (PoseFrame frame) => _normalizeRequired(
          frame.landmarks,
          requiredLandmarks,
        ),
      )
      .toList(growable: false);
  final List<int> detected = <int>[];
  double observedMaximum = 0;
  for (int frameIndex = 1; frameIndex < stream.frames.length; frameIndex += 1) {
    final double interval =
        (timestamps[frameIndex] - timestamps[frameIndex - 1]).toDouble();
    final List<Vector3>? previous = normalized[frameIndex - 1];
    final List<Vector3>? current = normalized[frameIndex];
    if (previous == null ||
        current == null ||
        interval > maximumIntervalRatio * nominalInterval) {
      continue;
    }
    final List<double> displacement = <double>[
      for (int index = 0; index < previous.length; index += 1)
        _norm(current[index] - previous[index]),
    ];
    final double speed = median(displacement) / (interval / 1000);
    observedMaximum = math.max(observedMaximum, speed);
    if (speed > maximumNormalizedSpeed) {
      detected.add(frameIndex);
    }
  }
  return PoseDiscontinuityAssessment(
    frameIndices: detected,
    maximumNormalizedSpeed: observedMaximum,
  );
}

List<Vector3>? _normalizeRequired(
  List<PoseLandmark>? landmarks,
  List<int> required,
) {
  if (landmarks == null) {
    return null;
  }
  final Vector3? leftHip = landmarks[landmarkIndex['left_hip']!].position;
  final Vector3? rightHip = landmarks[landmarkIndex['right_hip']!].position;
  final Vector3? leftShoulder =
      landmarks[landmarkIndex['left_shoulder']!].position;
  final Vector3? rightShoulder =
      landmarks[landmarkIndex['right_shoulder']!].position;
  if (leftHip == null ||
      rightHip == null ||
      leftShoulder == null ||
      rightShoulder == null) {
    return null;
  }
  final Vector3 midHip = (leftHip + rightHip) / 2;
  final Vector3 midShoulder = (leftShoulder + rightShoulder) / 2;
  final double torsoScale = _norm(midShoulder - midHip);
  if (!torsoScale.isFinite || torsoScale <= 1e-8) {
    return null;
  }
  final List<Vector3> normalized = <Vector3>[];
  for (final int index in required) {
    final Vector3? position = landmarks[index].position;
    if (position == null || !position.isFinite) {
      return null;
    }
    normalized.add((position - midHip) / torsoScale);
  }
  return normalized;
}

double _norm(Vector3 value) =>
    math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z);
