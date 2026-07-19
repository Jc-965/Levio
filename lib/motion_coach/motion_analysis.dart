import 'dart:io';
import 'dart:isolate';

import 'package:motion_engine/motion_engine.dart';

import 'motion_pose_bridge.dart';

const String motionCoachExerciseId = 'seated_bilateral_lateral_arm_raise';
const String motionCoachEngineVersion = '0.2.0';
const double motionCoachReferenceRomDeg = 68;
const double motionCoachReferenceTempoS = 0.964;
const bool motionCoachEnabled = bool.fromEnvironment(
  'PARKIWELL_MOTION_COACH',
  defaultValue: true,
);

String get motionPoseRuntime {
  if (Platform.isAndroid) {
    return 'mediapipe_tasks_android_0.10.35';
  }
  if (Platform.isIOS) {
    return 'mediapipe_tasks_ios_0.10.21';
  }
  return 'mediapipe_tasks_test';
}

ExerciseTemplate get motionCoachTemplate => ExerciseTemplate(
  schemaVersion: 'exercise-template.v1',
  templateVersion: 1,
  exerciseId: motionCoachExerciseId,
  poseContract: const PoseModelContract(
    runtime: 'mediapipe_tasks',
    model: motionPoseModelName,
    version: motionPoseModelVersion,
    coordinateSpace: 'mediapipe_world_3d',
  ),
  allowedOrientations: const <String>{'portrait'},
  primarySignal: 'arm_elevation_mean',
  requiredLandmarks: const <String>[
    'left_shoulder',
    'right_shoulder',
    'left_wrist',
    'right_wrist',
    'left_hip',
    'right_hip',
  ],
  referenceRomDeg: motionCoachReferenceRomDeg,
  referenceTempoS: motionCoachReferenceTempoS,
  confidencePolicy: const ConfidencePolicy(
    visibilityThreshold: 0.6,
    minimumSessionCoverage: 0.8,
    minimumSamplingHz: 15,
    maximumInterpolatedGapFrames: 3,
  ),
);

class MotionCoachAnalyzer {
  const MotionCoachAnalyzer();

  Future<MotionAnalysisResult> analyze({
    required List<PoseFrame> frames,
    required int width,
    required int height,
    String? runtime,
  }) {
    final _AnalysisRequest request = _AnalysisRequest(
      frames: frames,
      width: width,
      height: height,
      runtime: runtime ?? motionPoseRuntime,
    );
    return Isolate.run(() => _analyze(request));
  }
}

MotionAnalysisResult _analyze(_AnalysisRequest request) {
  final PoseStream stream = PoseStream(
    schemaVersion: 'pose-stream.v1',
    engineVersion: motionCoachEngineVersion,
    poseModel: PoseModelContract(
      runtime: request.runtime,
      model: motionPoseModelName,
      version: motionPoseModelVersion,
      coordinateSpace: 'mediapipe_world_3d',
    ),
    camera: CameraContract(
      orientation: 'portrait',
      mirrored: false,
      width: request.width,
      height: request.height,
    ),
    frames: request.frames,
  );
  return MotionAnalysisResult.fromDocument(
    analyzePoseStream(
      stream,
      motionCoachTemplate,
      engineVersion: motionCoachEngineVersion,
    ),
  );
}

class _AnalysisRequest {
  const _AnalysisRequest({
    required this.frames,
    required this.width,
    required this.height,
    required this.runtime,
  });

  final List<PoseFrame> frames;
  final int width;
  final int height;
  final String runtime;
}

class MotionAnalysisResult {
  const MotionAnalysisResult({
    required this.document,
    required this.sessionConfidence,
    required this.reasonCodes,
    required this.flags,
    required this.coverage,
    required this.durationSeconds,
    required this.repCount,
    required this.rangeDegrees,
    required this.tempoSeconds,
    required this.sideRangeRatio,
  });

  factory MotionAnalysisResult.fromDocument(AnalysisDocument document) {
    final Map<String, Object?> session =
        document['session']! as Map<String, Object?>;
    final Map<String, Object?> metrics =
        document['metrics']! as Map<String, Object?>;
    final Map<String, Object?> repetitions =
        metrics['rep_count']! as Map<String, Object?>;
    final Map<String, Object?> range =
        metrics['arm_elevation_rom_pct']! as Map<String, Object?>;
    final Map<String, Object?> tempo =
        metrics['tempo_s']! as Map<String, Object?>;
    final Map<String, Object?> side =
        metrics['symmetry_lr_rom_ratio']! as Map<String, Object?>;
    final double? rangePercent = (range['median'] as num?)?.toDouble();

    return MotionAnalysisResult(
      document: document,
      sessionConfidence: session['confidence']! as String,
      reasonCodes: List<String>.from(session['reason_codes']! as List<Object?>),
      flags: List<String>.from(document['flags']! as List<Object?>),
      coverage: (session['coverage']! as num).toDouble(),
      durationSeconds: (session['duration_s']! as num).toDouble(),
      repCount: (repetitions['value'] as num?)?.toInt(),
      rangeDegrees: rangePercent == null
          ? null
          : rangePercent * motionCoachReferenceRomDeg / 100,
      tempoSeconds: (tempo['median'] as num?)?.toDouble(),
      sideRangeRatio: (side['value'] as num?)?.toDouble(),
    );
  }

  final AnalysisDocument document;
  final String sessionConfidence;
  final List<String> reasonCodes;
  final List<String> flags;
  final double coverage;
  final double durationSeconds;
  final int? repCount;
  final double? rangeDegrees;
  final double? tempoSeconds;
  final double? sideRangeRatio;

  bool get needsSetupHelp =>
      sessionConfidence == 'insufficient' || repCount == null || repCount == 0;
}
