import 'dart:io';
import 'dart:isolate';

import 'package:motion_engine/motion_engine.dart';

import 'motion_exercise_catalog.dart';
import 'motion_pose_bridge.dart';

const String motionCoachEngineVersion = '0.3.0';
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

ExerciseTemplate motionCoachTemplateFor(MotionExerciseDefinition exercise) =>
    ExerciseTemplate(
      schemaVersion: 'exercise-template.v1',
      templateVersion: exercise.templateVersion,
      exerciseId: exercise.exerciseId,
      poseContract: const PoseModelContract(
        runtime: 'mediapipe_tasks',
        model: motionPoseModelName,
        version: motionPoseModelVersion,
        coordinateSpace: 'mediapipe_world_3d',
      ),
      allowedOrientations: const <String>{'portrait'},
      primarySignal: switch (exercise.analysisKind) {
        MotionAnalysisKind.bilateralLateralArmRaise => 'arm_elevation_mean',
      },
      requiredLandmarks: switch (exercise.analysisKind) {
        MotionAnalysisKind.bilateralLateralArmRaise => const <String>[
          'left_shoulder',
          'right_shoulder',
          'left_wrist',
          'right_wrist',
          'left_hip',
          'right_hip',
        ],
      },
      referenceRomDeg: exercise.referenceRomDegrees,
      referenceTempoS: exercise.referenceTempoSeconds,
      confidencePolicy: const ConfidencePolicy(
        visibilityThreshold: 0.6,
        minimumSessionCoverage: 0.8,
        minimumSamplingHz: 15,
        maximumInterpolatedGapFrames: 3,
      ),
    );

ExerciseTemplate get motionCoachTemplate =>
    motionCoachTemplateFor(seatedArmRaiseExercise);

class MotionCoachAnalyzer {
  const MotionCoachAnalyzer();

  Future<MotionAnalysisResult> analyze({
    required List<PoseFrame> frames,
    required int width,
    required int height,
    String? runtime,
    MotionExerciseDefinition exercise = seatedArmRaiseExercise,
  }) {
    final _AnalysisRequest request = _AnalysisRequest(
      frames: frames,
      width: width,
      height: height,
      runtime: runtime ?? motionPoseRuntime,
      exercise: exercise,
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
      motionCoachTemplateFor(request.exercise),
      engineVersion: motionCoachEngineVersion,
    ),
    referenceRomDegrees: request.exercise.referenceRomDegrees,
    referenceTempoSeconds: request.exercise.referenceTempoSeconds,
  );
}

class _AnalysisRequest {
  const _AnalysisRequest({
    required this.frames,
    required this.width,
    required this.height,
    required this.runtime,
    required this.exercise,
  });

  final List<PoseFrame> frames;
  final int width;
  final int height;
  final String runtime;
  final MotionExerciseDefinition exercise;
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
    required this.rangePercentOfReference,
    required this.tempoSeconds,
    required this.sideRangeRatio,
    required this.amplitudeSequenceLastFirstRatio,
    required this.repetitions,
    required this.referenceRomDegrees,
    required this.referenceTempoSeconds,
  });

  factory MotionAnalysisResult.fromDocument(
    AnalysisDocument document, {
    required double referenceRomDegrees,
    required double referenceTempoSeconds,
  }) {
    final Map<String, Object?> session =
        document['session']! as Map<String, Object?>;
    final Map<String, Object?> metrics =
        document['metrics']! as Map<String, Object?>;
    final Map<String, Object?> repCountMetric =
        metrics['rep_count']! as Map<String, Object?>;
    final Map<String, Object?> range =
        metrics['arm_elevation_rom_pct']! as Map<String, Object?>;
    final Map<String, Object?> tempo =
        metrics['tempo_s']! as Map<String, Object?>;
    final Map<String, Object?> side =
        metrics['symmetry_lr_rom_ratio']! as Map<String, Object?>;
    final Map<String, Object?>? sequence =
        metrics['amplitude_sequence_last_first_ratio'] as Map<String, Object?>?;
    final List<MotionRepObservation> repetitions =
        (metrics['repetitions'] as List<Object?>? ?? const <Object?>[])
            .map(
              (Object? value) => MotionRepObservation.fromDocument(
                value! as Map<String, Object?>,
              ),
            )
            .toList(growable: false);
    final double? rangePercent = (range['median'] as num?)?.toDouble();

    return MotionAnalysisResult(
      document: document,
      sessionConfidence: session['confidence']! as String,
      reasonCodes: List<String>.from(session['reason_codes']! as List<Object?>),
      flags: List<String>.from(document['flags']! as List<Object?>),
      coverage: (session['coverage']! as num).toDouble(),
      durationSeconds: (session['duration_s']! as num).toDouble(),
      repCount: (repCountMetric['value'] as num?)?.toInt(),
      rangeDegrees: rangePercent == null
          ? null
          : rangePercent * referenceRomDegrees / 100,
      rangePercentOfReference: rangePercent,
      tempoSeconds: (tempo['median'] as num?)?.toDouble(),
      sideRangeRatio: (side['value'] as num?)?.toDouble(),
      amplitudeSequenceLastFirstRatio: (sequence?['value'] as num?)?.toDouble(),
      repetitions: repetitions,
      referenceRomDegrees: referenceRomDegrees,
      referenceTempoSeconds: referenceTempoSeconds,
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
  final double? rangePercentOfReference;
  final double? tempoSeconds;
  final double? sideRangeRatio;
  final double? amplitudeSequenceLastFirstRatio;
  final List<MotionRepObservation> repetitions;
  final double referenceRomDegrees;
  final double referenceTempoSeconds;

  bool get needsSetupHelp =>
      sessionConfidence == 'insufficient' || repCount == null || repCount == 0;

  String get evidenceSummary {
    final List<String> observations = <String>[];
    if (repCount != null) {
      observations.add(
        '$repCount complete bilateral ${repCount == 1 ? 'raise was' : 'raises were'} detected',
      );
    }
    if (rangeDegrees != null && rangePercentOfReference != null) {
      observations.add(
        'the median observed arm range was ${rangeDegrees!.round()}° '
        '(${rangePercentOfReference!.round()}% of this exercise reference)',
      );
    }
    if (tempoSeconds != null) {
      observations.add(
        'the median complete cycle took ${tempoSeconds!.toStringAsFixed(1)} '
        'seconds, compared with the ${referenceTempoSeconds.toStringAsFixed(1)}-second '
        'exercise reference',
      );
    }
    if (sideRangeRatio != null) {
      observations.add(
        'the smaller-to-larger observed side range ratio was '
        '${(sideRangeRatio! * 100).round()}%',
      );
    }
    if (observations.isEmpty) {
      return 'The camera did not produce enough reliable movement evidence for a summary.';
    }
    return '${_joinObservations(observations)}.';
  }

  String? get sequenceSummary {
    if (repetitions.length < 3 || amplitudeSequenceLastFirstRatio == null) {
      return null;
    }
    final MotionRepObservation first = repetitions.first;
    final MotionRepObservation last = repetitions.last;
    return 'The first complete raise measured ${first.romDegrees.round()}° and '
        'the last measured ${last.romDegrees.round()}° '
        '(${(amplitudeSequenceLastFirstRatio! * 100).round()}% of the first).';
  }

  String get measurementLimits =>
      'These are camera measurements, not a diagnosis or a measure of how the '
      'movement felt. Use the demonstration as a guide, stay within a '
      'comfortable range, and stop if you feel pain, dizzy, or unwell.';
}

class MotionRepObservation {
  const MotionRepObservation({
    required this.index,
    required this.startSeconds,
    required this.peakSeconds,
    required this.endSeconds,
    required this.romDegrees,
    required this.romPercentOfReference,
    required this.tempoSeconds,
    required this.leftRomDegrees,
    required this.rightRomDegrees,
    required this.sideRangeRatio,
    required this.confidence,
    required this.reasonCodes,
  });

  factory MotionRepObservation.fromDocument(Map<String, Object?> document) =>
      MotionRepObservation(
        index: (document['index']! as num).toInt(),
        startSeconds: (document['start_s']! as num).toDouble(),
        peakSeconds: (document['peak_s']! as num).toDouble(),
        endSeconds: (document['end_s']! as num).toDouble(),
        romDegrees: (document['rom_deg']! as num).toDouble(),
        romPercentOfReference: (document['rom_pct_of_reference']! as num)
            .toDouble(),
        tempoSeconds: (document['tempo_s']! as num).toDouble(),
        leftRomDegrees: (document['left_rom_deg'] as num?)?.toDouble(),
        rightRomDegrees: (document['right_rom_deg'] as num?)?.toDouble(),
        sideRangeRatio: (document['symmetry_lr_rom_ratio'] as num?)?.toDouble(),
        confidence: document['confidence']! as String,
        reasonCodes: List<String>.from(
          document['reason_codes']! as List<Object?>,
        ),
      );

  final int index;
  final double startSeconds;
  final double peakSeconds;
  final double endSeconds;
  final double romDegrees;
  final double romPercentOfReference;
  final double tempoSeconds;
  final double? leftRomDegrees;
  final double? rightRomDegrees;
  final double? sideRangeRatio;
  final String confidence;
  final List<String> reasonCodes;
}

String _joinObservations(List<String> observations) {
  if (observations.length == 1) return observations.single;
  if (observations.length == 2) {
    return '${observations.first}, and ${observations.last}';
  }
  return '${observations.sublist(0, observations.length - 1).join(', ')}, '
      'and ${observations.last}';
}
