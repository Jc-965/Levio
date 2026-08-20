import 'dart:math' as math;

import 'models.dart';

const Map<String, int> landmarkIndex = <String, int>{
  'nose': 0,
  'left_shoulder': 11,
  'right_shoulder': 12,
  'left_elbow': 13,
  'right_elbow': 14,
  'left_wrist': 15,
  'right_wrist': 16,
  'left_hip': 23,
  'right_hip': 24,
  'left_knee': 25,
  'right_knee': 26,
  'left_ankle': 27,
  'right_ankle': 28,
  'left_foot_index': 31,
  'right_foot_index': 32,
};

double jointAngle(
  Vector3? first,
  Vector3? vertex,
  Vector3? last, {
  double epsilon = 1e-8,
}) {
  if (first == null ||
      vertex == null ||
      last == null ||
      !first.isFinite ||
      !vertex.isFinite ||
      !last.isFinite) {
    return double.nan;
  }
  final Vector3 firstRay = first - vertex;
  final Vector3 lastRay = last - vertex;
  final double firstNorm = _norm(firstRay);
  final double lastNorm = _norm(lastRay);
  final double denominator = firstNorm * lastNorm;
  if (!denominator.isFinite || denominator <= epsilon) {
    return double.nan;
  }
  final double cosine = _dot(firstRay, lastRay) / denominator;
  return math.acos(cosine.clamp(-1.0, 1.0)) * 180 / math.pi;
}

Map<String, List<double>> computeArmRaiseFeatures(PoseStream stream) {
  final Map<String, List<double>> features = <String, List<double>>{
    'arm_elevation_l': <double>[],
    'arm_elevation_r': <double>[],
    'arm_elevation_mean': <double>[],
    'elbow_angle_l': <double>[],
    'elbow_angle_r': <double>[],
    'trunk_lean': <double>[],
  };
  for (final PoseFrame frame in stream.frames) {
    final List<PoseLandmark>? points = frame.landmarks;
    final Vector3? leftShoulder = _at(points, 'left_shoulder');
    final Vector3? rightShoulder = _at(points, 'right_shoulder');
    final Vector3? leftHip = _at(points, 'left_hip');
    final Vector3? rightHip = _at(points, 'right_hip');
    final double leftElevation = jointAngle(
      leftHip,
      leftShoulder,
      _at(points, 'left_wrist'),
    );
    final double rightElevation = jointAngle(
      rightHip,
      rightShoulder,
      _at(points, 'right_wrist'),
    );
    features['arm_elevation_l']!.add(leftElevation);
    features['arm_elevation_r']!.add(rightElevation);
    features['arm_elevation_mean']!.add(
      leftElevation.isFinite && rightElevation.isFinite
          ? (leftElevation + rightElevation) / 2
          : double.nan,
    );
    features['elbow_angle_l']!.add(
      jointAngle(
        leftShoulder,
        _at(points, 'left_elbow'),
        _at(points, 'left_wrist'),
      ),
    );
    features['elbow_angle_r']!.add(
      jointAngle(
        rightShoulder,
        _at(points, 'right_elbow'),
        _at(points, 'right_wrist'),
      ),
    );
    if (leftHip == null ||
        rightHip == null ||
        leftShoulder == null ||
        rightShoulder == null) {
      features['trunk_lean']!.add(double.nan);
    } else {
      final Vector3 midHip = (leftHip + rightHip) / 2;
      final Vector3 midShoulder = (leftShoulder + rightShoulder) / 2;
      features['trunk_lean']!.add(
        jointAngle(
          midHip + const Vector3(0, -1, 0),
          midHip,
          midShoulder,
        ),
      );
    }
  }
  return features;
}

Vector3? _at(List<PoseLandmark>? points, String name) =>
    points?[landmarkIndex[name]!].position;

double _dot(Vector3 first, Vector3 second) =>
    first.x * second.x + first.y * second.y + first.z * second.z;

double _norm(Vector3 value) =>
    math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z);
