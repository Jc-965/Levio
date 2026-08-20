import 'dart:math' as math;

import 'confidence.dart';
import 'exercise_specs.dart';
import 'features.dart';
import 'filtering.dart';
import 'metrics.dart';
import 'models.dart';

const String filterName = 'butterworth_sosfiltfilt_segmented';
const String filterVersion = '1';
const double filterCutoffHz = 6;
const int filterOrder = 4;

AnalysisDocument analyzePoseDocuments(
  Map<String, Object?> poseStreamJson,
  Map<String, Object?> exerciseTemplateJson, {
  required String engineVersion,
}) =>
    analyzePoseStream(
      PoseStream.fromJson(poseStreamJson),
      ExerciseTemplate.fromJson(exerciseTemplateJson),
      engineVersion: engineVersion,
    );

AnalysisDocument analyzePoseStream(
  PoseStream poseStream,
  ExerciseTemplate exerciseTemplate, {
  required String engineVersion,
}) {
  _validatePoseCompatibility(poseStream, exerciseTemplate);
  final ExerciseSpec spec;
  try {
    spec = exerciseSpecById(exerciseTemplate.exerciseId);
  } on ArgumentError {
    throw UnsupportedError(
      'unknown exercise: ${exerciseTemplate.exerciseId}',
    );
  }
  if (exerciseTemplate.primarySignal != spec.primarySignal) {
    throw UnsupportedError(
      'template primary signal ${exerciseTemplate.primarySignal} does not '
      'match the registered specification ${spec.primarySignal} '
      'for ${exerciseTemplate.exerciseId}',
    );
  }
  final List<int> requiredLandmarks =
      exerciseTemplate.requiredLandmarks.map((String name) {
    final int? index = landmarkIndex[name];
    if (index == null) {
      throw UnsupportedError('unsupported required landmark: $name');
    }
    return index;
  }).toList(growable: false);
  final ConfidencePolicy policy = exerciseTemplate.confidencePolicy;
  CoverageAssessment coverage = assessTrackingCoverage(
    poseStream,
    requiredLandmarks,
    visibilityThreshold: policy.visibilityThreshold,
    minimumCoverage: policy.minimumSessionCoverage,
  );
  final PoseDiscontinuityAssessment discontinuities =
      assessPoseDiscontinuities(poseStream, requiredLandmarks);
  if (discontinuities.frameIndices.isNotEmpty) {
    final List<ReasonCode> reasons = List<ReasonCode>.of(coverage.reasons);
    if (!reasons.contains(ReasonCode.poseDiscontinuity)) {
      reasons.add(ReasonCode.poseDiscontinuity);
    }
    coverage = coverage.copyWith(
      level: ConfidenceLevel.insufficient,
      reasons: reasons,
    );
  }
  final List<int> timestampsMs =
      poseStream.frames.map((PoseFrame frame) => frame.timestampMs).toList();
  final double samplingHz = estimateSamplingHz(timestampsMs);
  if (coverage.totalFrames > 0 && samplingHz < policy.minimumSamplingHz) {
    final List<ReasonCode> reasons = List<ReasonCode>.of(coverage.reasons);
    if (!reasons.contains(ReasonCode.lowSamplingRate)) {
      reasons.add(ReasonCode.lowSamplingRate);
    }
    coverage = coverage.copyWith(
      level: ConfidenceLevel.insufficient,
      reasons: reasons,
    );
  }

  final Map<String, List<double>> rawFeatures =
      computeFeatures(poseStream, spec);
  final double effectiveCutoffHz =
      samplingHz > 0 ? math.min(filterCutoffHz, 0.4 * samplingHz) : 0.1;
  final Map<String, List<double>> features = timestampsMs.length > 1
      ? rawFeatures.map(
          (String name, List<double> values) => MapEntry<String, List<double>>(
            name,
            lowpassTimestamped(
              values,
              timestampsMs,
              cutoffHz: effectiveCutoffHz,
              order: filterOrder,
              maxGapFrames: policy.maximumInterpolatedGapFrames,
            ),
          ),
        )
      : rawFeatures;
  final Map<String, Object?> provenance = <String, Object?>{
    'pose_model': <String, Object?>{
      'runtime': poseStream.poseModel.runtime,
      'model': poseStream.poseModel.model,
      'version': poseStream.poseModel.version,
      'coordinate_space': poseStream.poseModel.coordinateSpace,
    },
    'camera': <String, Object?>{
      'orientation': poseStream.camera.orientation,
      'mirrored': poseStream.camera.mirrored,
      'width': poseStream.camera.width,
      'height': poseStream.camera.height,
    },
    'filter': <String, Object?>{
      'name': filterName,
      'version': filterVersion,
      'cutoff_hz': effectiveCutoffHz,
      'order': filterOrder,
      'maximum_interpolated_gap_frames': policy.maximumInterpolatedGapFrames,
    },
  };
  return analyzeSession(
    features: features,
    timestampsMs: timestampsMs,
    coverage: coverage,
    spec: spec,
    templateVersion: exerciseTemplate.templateVersion,
    referenceRomDeg: exerciseTemplate.referenceRomDeg,
    referenceTempoS: exerciseTemplate.referenceTempoS,
    engineVersion: engineVersion,
    provenance: provenance,
  );
}

void _validatePoseCompatibility(
  PoseStream stream,
  ExerciseTemplate template,
) {
  final PoseModelContract actual = stream.poseModel;
  final PoseModelContract expected = template.poseContract;
  if (actual.model != expected.model) {
    throw const FormatException('pose model does not match template');
  }
  if (actual.version != expected.version) {
    throw const FormatException('pose model version does not match template');
  }
  if (actual.coordinateSpace != expected.coordinateSpace) {
    throw const FormatException(
        'pose coordinate space does not match template');
  }
  if (!template.allowedOrientations.contains(stream.camera.orientation)) {
    throw const FormatException(
        'camera orientation is not allowed by template');
  }
}
