/// Declarative exercise specifications and per-frame feature computation.
///
/// Mirrors `motion_coach_cv.exercises` in the Python reference engine: every
/// exercise is data only (angle triples over the 33-landmark topology plus
/// derived pair features), and the live engine consumes specifications
/// without any per-exercise code. Parity is enforced by the shared golden
/// fixtures.
library;

import 'features.dart';
import 'models.dart';

const String midHipPoint = 'mid_hip';
const String midShoulderPoint = 'mid_shoulder';
const String worldVerticalUpPoint = 'world_vertical_up';

enum ExerciseLaterality { bilateralSync, alternating, none }

enum ExercisePosture { seated, standing }

enum PairCombine { mean, max }

sealed class FeatureDefinition {
  const FeatureDefinition();
}

final class AngleFeatureDefinition extends FeatureDefinition {
  const AngleFeatureDefinition(
    this.first,
    this.vertex,
    this.last, {
    this.invert = false,
  });

  final String first;
  final String vertex;
  final String last;
  final bool invert;
}

final class PairFeatureDefinition extends FeatureDefinition {
  const PairFeatureDefinition(this.combine, this.firstInput, this.secondInput);

  final PairCombine combine;
  final String firstInput;
  final String secondInput;
}

final class ExerciseCueTexts {
  const ExerciseCueTexts({
    required this.amplitude,
    this.tempo = 'Nice work. Keep a steady, comfortable pace.',
    this.smoothness = 'Try to keep the movement smooth and controlled.',
    this.positive = 'Nice movement.',
  });

  final String amplitude;
  final String tempo;
  final String smoothness;
  final String positive;
}

final class ExerciseSpec {
  ExerciseSpec({
    required this.exerciseId,
    required this.displayName,
    required this.instruction,
    required this.posture,
    required this.features,
    required this.primarySignal,
    required this.laterality,
    required this.requiredLandmarks,
    required this.cues,
    this.sideFeatures,
  }) {
    if (!features.containsKey(primarySignal)) {
      throw ArgumentError('primary signal $primarySignal is not defined');
    }
    if (laterality == ExerciseLaterality.none) {
      if (sideFeatures != null) {
        throw ArgumentError('side features require a sided laterality');
      }
    } else if (sideFeatures == null || sideFeatures!.length != 2) {
      throw ArgumentError('laterality $laterality requires two side features');
    }
  }

  final String exerciseId;
  final String displayName;
  final String instruction;
  final ExercisePosture posture;
  final Map<String, FeatureDefinition> features;
  final String primarySignal;
  final ExerciseLaterality laterality;
  final List<String> requiredLandmarks;
  final ExerciseCueTexts cues;
  final List<String>? sideFeatures;
}

/// Per-frame feature evaluation; missing data propagates as NaN exactly like
/// the Python engine (`bilateral_mean`/`pair_max` are valid only when both
/// sides are valid).
Map<String, double> computeFrameFeatures(
  List<PoseLandmark>? points,
  ExerciseSpec spec,
) {
  final Map<String, double> computed = <String, double>{};
  for (final MapEntry<String, FeatureDefinition> entry
      in spec.features.entries) {
    final FeatureDefinition definition = entry.value;
    switch (definition) {
      case AngleFeatureDefinition():
        final Vector3? vertex = _resolvePoint(definition.vertex, points, null);
        final double angle = jointAngle(
          _resolvePoint(definition.first, points, vertex),
          vertex,
          _resolvePoint(definition.last, points, vertex),
        );
        computed[entry.key] = definition.invert ? 180.0 - angle : angle;
      case PairFeatureDefinition():
        final double first = computed[definition.firstInput] ?? double.nan;
        final double second = computed[definition.secondInput] ?? double.nan;
        if (!first.isFinite || !second.isFinite) {
          computed[entry.key] = double.nan;
        } else if (definition.combine == PairCombine.mean) {
          computed[entry.key] = (first + second) / 2;
        } else {
          computed[entry.key] = first >= second ? first : second;
        }
    }
  }
  return computed;
}

Vector3? _resolvePoint(
  String name,
  List<PoseLandmark>? points,
  Vector3? vertex,
) {
  if (points == null || points.length != 33) {
    return null;
  }
  switch (name) {
    case midHipPoint:
      final Vector3? left = points[landmarkIndex['left_hip']!].position;
      final Vector3? right = points[landmarkIndex['right_hip']!].position;
      if (left == null || right == null) {
        return null;
      }
      return (left + right) / 2;
    case midShoulderPoint:
      final Vector3? left = points[landmarkIndex['left_shoulder']!].position;
      final Vector3? right = points[landmarkIndex['right_shoulder']!].position;
      if (left == null || right == null) {
        return null;
      }
      return (left + right) / 2;
    case worldVerticalUpPoint:
      if (vertex == null) {
        return null;
      }
      return vertex + const Vector3(0, -1, 0);
    default:
      return points[landmarkIndex[name]!].position;
  }
}

Map<String, FeatureDefinition> _armFeatures() => <String, FeatureDefinition>{
      'arm_elevation_l': const AngleFeatureDefinition(
        'left_hip',
        'left_shoulder',
        'left_wrist',
      ),
      'arm_elevation_r': const AngleFeatureDefinition(
        'right_hip',
        'right_shoulder',
        'right_wrist',
      ),
      'arm_elevation_mean': const PairFeatureDefinition(
        PairCombine.mean,
        'arm_elevation_l',
        'arm_elevation_r',
      ),
      'elbow_angle_l': const AngleFeatureDefinition(
        'left_shoulder',
        'left_elbow',
        'left_wrist',
      ),
      'elbow_angle_r': const AngleFeatureDefinition(
        'right_shoulder',
        'right_elbow',
        'right_wrist',
      ),
      'trunk_lean': const AngleFeatureDefinition(
        worldVerticalUpPoint,
        midHipPoint,
        midShoulderPoint,
      ),
    };

final Map<String, ExerciseSpec> exerciseRegistry = <String, ExerciseSpec>{
  'seated_bilateral_lateral_arm_raise': ExerciseSpec(
    exerciseId: 'seated_bilateral_lateral_arm_raise',
    displayName: 'Seated bilateral lateral arm raise',
    instruction:
        'Sitting tall, raise both arms out to the sides, then lower them '
        'slowly.',
    posture: ExercisePosture.seated,
    features: _armFeatures(),
    primarySignal: 'arm_elevation_mean',
    laterality: ExerciseLaterality.bilateralSync,
    sideFeatures: const <String>['arm_elevation_l', 'arm_elevation_r'],
    requiredLandmarks: const <String>[
      'left_shoulder',
      'right_shoulder',
      'left_wrist',
      'right_wrist',
      'left_hip',
      'right_hip',
    ],
    cues: const ExerciseCueTexts(
      amplitude: 'If comfortable, make the next raise a little larger.',
    ),
  ),
  'seated_bilateral_forward_reach': ExerciseSpec(
    exerciseId: 'seated_bilateral_forward_reach',
    displayName: 'Seated bilateral forward reach',
    instruction:
        'Sitting tall, reach both arms forward and up, then bring them back '
        'down.',
    posture: ExercisePosture.seated,
    features: _armFeatures(),
    primarySignal: 'arm_elevation_mean',
    laterality: ExerciseLaterality.bilateralSync,
    sideFeatures: const <String>['arm_elevation_l', 'arm_elevation_r'],
    requiredLandmarks: const <String>[
      'left_shoulder',
      'right_shoulder',
      'left_wrist',
      'right_wrist',
      'left_hip',
      'right_hip',
    ],
    cues: const ExerciseCueTexts(
      amplitude: 'If comfortable, reach a little further on the next one.',
    ),
  ),
  'seated_bilateral_elbow_flexion': ExerciseSpec(
    exerciseId: 'seated_bilateral_elbow_flexion',
    displayName: 'Seated bilateral elbow bends',
    instruction:
        'With arms at your sides, bend both elbows to bring your hands up, '
        'then lower.',
    posture: ExercisePosture.seated,
    features: <String, FeatureDefinition>{
      'elbow_flexion_l': const AngleFeatureDefinition(
        'left_shoulder',
        'left_elbow',
        'left_wrist',
        invert: true,
      ),
      'elbow_flexion_r': const AngleFeatureDefinition(
        'right_shoulder',
        'right_elbow',
        'right_wrist',
        invert: true,
      ),
      'elbow_flexion_mean': const PairFeatureDefinition(
        PairCombine.mean,
        'elbow_flexion_l',
        'elbow_flexion_r',
      ),
      'trunk_lean': const AngleFeatureDefinition(
        worldVerticalUpPoint,
        midHipPoint,
        midShoulderPoint,
      ),
    },
    primarySignal: 'elbow_flexion_mean',
    laterality: ExerciseLaterality.bilateralSync,
    sideFeatures: const <String>['elbow_flexion_l', 'elbow_flexion_r'],
    requiredLandmarks: const <String>[
      'left_shoulder',
      'right_shoulder',
      'left_elbow',
      'right_elbow',
      'left_wrist',
      'right_wrist',
    ],
    cues: const ExerciseCueTexts(
      amplitude: 'If comfortable, bend your elbows a little further.',
    ),
  ),
  'seated_alternating_march': ExerciseSpec(
    exerciseId: 'seated_alternating_march',
    displayName: 'Seated alternating march',
    instruction:
        'Sitting tall, lift one knee at a time as if marching, alternating '
        'sides.',
    posture: ExercisePosture.seated,
    features: <String, FeatureDefinition>{
      'hip_flexion_l': const AngleFeatureDefinition(
        'left_shoulder',
        'left_hip',
        'left_knee',
        invert: true,
      ),
      'hip_flexion_r': const AngleFeatureDefinition(
        'right_shoulder',
        'right_hip',
        'right_knee',
        invert: true,
      ),
      'hip_flexion_peak': const PairFeatureDefinition(
        PairCombine.max,
        'hip_flexion_l',
        'hip_flexion_r',
      ),
      'trunk_lean': const AngleFeatureDefinition(
        worldVerticalUpPoint,
        midHipPoint,
        midShoulderPoint,
      ),
    },
    primarySignal: 'hip_flexion_peak',
    laterality: ExerciseLaterality.alternating,
    sideFeatures: const <String>['hip_flexion_l', 'hip_flexion_r'],
    requiredLandmarks: const <String>[
      'left_shoulder',
      'right_shoulder',
      'left_hip',
      'right_hip',
      'left_knee',
      'right_knee',
    ],
    cues: const ExerciseCueTexts(
      amplitude: 'If comfortable, lift your knees a little higher.',
    ),
  ),
  'sit_to_stand': ExerciseSpec(
    exerciseId: 'sit_to_stand',
    displayName: 'Sit to stand',
    instruction:
        'From sitting, stand up fully, then lower yourself back down with '
        'control.',
    posture: ExercisePosture.standing,
    features: <String, FeatureDefinition>{
      'knee_extension_l': const AngleFeatureDefinition(
        'left_hip',
        'left_knee',
        'left_ankle',
      ),
      'knee_extension_r': const AngleFeatureDefinition(
        'right_hip',
        'right_knee',
        'right_ankle',
      ),
      'knee_extension_mean': const PairFeatureDefinition(
        PairCombine.mean,
        'knee_extension_l',
        'knee_extension_r',
      ),
      'trunk_lean': const AngleFeatureDefinition(
        worldVerticalUpPoint,
        midHipPoint,
        midShoulderPoint,
      ),
    },
    primarySignal: 'knee_extension_mean',
    laterality: ExerciseLaterality.bilateralSync,
    sideFeatures: const <String>['knee_extension_l', 'knee_extension_r'],
    requiredLandmarks: const <String>[
      'left_hip',
      'right_hip',
      'left_knee',
      'right_knee',
      'left_ankle',
      'right_ankle',
    ],
    cues: const ExerciseCueTexts(
      amplitude: 'If comfortable, rise a little taller before sitting back.',
    ),
  ),
  'seated_lateral_trunk_lean': ExerciseSpec(
    exerciseId: 'seated_lateral_trunk_lean',
    displayName: 'Seated side lean',
    instruction:
        'Sitting tall, lean gently to one side, return upright, then lean to '
        'the other.',
    posture: ExercisePosture.seated,
    features: <String, FeatureDefinition>{
      'trunk_lean': const AngleFeatureDefinition(
        worldVerticalUpPoint,
        midHipPoint,
        midShoulderPoint,
      ),
    },
    primarySignal: 'trunk_lean',
    laterality: ExerciseLaterality.none,
    requiredLandmarks: const <String>[
      'left_shoulder',
      'right_shoulder',
      'left_hip',
      'right_hip',
    ],
    cues: const ExerciseCueTexts(
      amplitude: 'If comfortable, lean just a little further next time.',
    ),
  ),
};

ExerciseSpec exerciseSpecById(String exerciseId) {
  final ExerciseSpec? spec = exerciseRegistry[exerciseId];
  if (spec == null) {
    throw ArgumentError('unknown exercise: $exerciseId');
  }
  return spec;
}
