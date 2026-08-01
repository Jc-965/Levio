import 'package:motion_engine/motion_engine.dart';

enum MotionExercisePosture { seated, standing }

enum MotionExerciseClinicalStatus { development, clinicianApproved }

enum MotionAnalysisKind { bilateralLateralArmRaise }

/// A licensed reference video segment shown as the demonstration.
///
/// Only exercises that have a reviewed, linkable source carry one. The rest
/// are demonstrated by the engine's own stick-figure reference loop, which
/// avoids taking a content dependency on a third-party video per exercise.
class MotionExerciseVideoSegment {
  const MotionExerciseVideoSegment({
    required this.segmentId,
    required this.videoId,
    required this.sourceTitle,
    required this.sourceAttribution,
    required this.sourceReviewDate,
    required this.startSeconds,
    required this.endSeconds,
    required this.demonstrationRepetitions,
  }) : assert(startSeconds >= 0),
       assert(endSeconds > startSeconds),
       assert(demonstrationRepetitions > 0),
       assert(sourceReviewDate.length == 10);

  final String segmentId;
  final String videoId;
  final String sourceTitle;
  final String sourceAttribution;
  final String sourceReviewDate;
  final int startSeconds;
  final int endSeconds;
  final int demonstrationRepetitions;

  int get demoDurationSeconds => endSeconds - startSeconds;

  String get demoTimeRangeLabel =>
      '${_formatTimestamp(startSeconds)}–${_formatTimestamp(endSeconds)}';

  Uri youtubeEmbedUri({bool demoOnly = false}) {
    return Uri.https('www.youtube.com', '/embed/$videoId', <String, String>{
      'playsinline': '1',
      'controls': '1',
      'rel': '0',
      if (demoOnly) 'start': '$startSeconds',
      if (demoOnly) 'end': '$endSeconds',
    });
  }

  Uri youtubeWatchUri({bool demoOnly = false}) {
    return Uri.https('www.youtube.com', '/watch', <String, String>{
      'v': videoId,
      if (demoOnly) 't': '${startSeconds}s',
    });
  }
}

/// Parameters the offline detailed-analysis pipeline needs.
///
/// Present only where `analyzePoseStream` actually supports the exercise's
/// primary signal — today that is the bilateral arm raise alone. Every other
/// exercise is measured by the live/routine engine, which is fully
/// spec-driven. Modelling this as a nullable field rather than a flag keeps
/// the reference constants from being invented for exercises that have no
/// offline path.
class MotionDetailedAnalysisSpec {
  const MotionDetailedAnalysisSpec({
    required this.kind,
    required this.templateVersion,
    required this.referenceRomDegrees,
    required this.referenceTempoSeconds,
  }) : assert(templateVersion > 0),
       assert(referenceRomDegrees > 0),
       assert(referenceTempoSeconds > 0);

  final MotionAnalysisKind kind;
  final int templateVersion;
  final double referenceRomDegrees;
  final double referenceTempoSeconds;
}

class MotionExerciseDefinition {
  const MotionExerciseDefinition({
    required this.exerciseId,
    required this.title,
    required this.instructions,
    required this.setupHint,
    required this.minimumRecordingRepetitions,
    required this.maximumRecordingRepetitions,
    required this.posture,
    required this.clinicalStatus,
    this.videoSegment,
    this.detailedAnalysis,
  }) : assert(minimumRecordingRepetitions > 0),
       assert(maximumRecordingRepetitions >= minimumRecordingRepetitions);

  /// Matches an `exerciseId` in the engine's [exerciseRegistry].
  final String exerciseId;
  final String title;

  /// What the person should do, phrased for the capture screen.
  final String instructions;

  /// How to place the phone and body so the exercise is measurable at all.
  final String setupHint;

  final int minimumRecordingRepetitions;
  final int maximumRecordingRepetitions;
  final MotionExercisePosture posture;
  final MotionExerciseClinicalStatus clinicalStatus;
  final MotionExerciseVideoSegment? videoSegment;
  final MotionDetailedAnalysisSpec? detailedAnalysis;

  /// The engine's declarative specification for this exercise. Throws if the
  /// catalog names an exercise the engine does not implement, which the
  /// catalog test asserts can never happen.
  ExerciseSpec get engineSpec => exerciseSpecById(exerciseId);

  bool get hasVideoDemonstration => videoSegment != null;

  bool get supportsDetailedAnalysis => detailedAnalysis != null;

  String get recordingRepetitionLabel =>
      '$minimumRecordingRepetitions–$maximumRecordingRepetitions';

  String get postureLabel =>
      posture == MotionExercisePosture.seated ? 'Seated' : 'Standing';
}

const MotionExerciseVideoSegment sitNFitArmRaiseSegment =
    MotionExerciseVideoSegment(
      segmentId: 'sit_n_fit_seated_arm_raise_32_55',
      videoId: 'AZV3_NfcpVs',
      sourceTitle: "Parkinson's Disease Exercises: Sit 'n' Fit",
      sourceAttribution: "Parkinson's Foundation (YouTube)",
      sourceReviewDate: '2026-07-19',
      startSeconds: 32,
      endSeconds: 55,
      demonstrationRepetitions: 3,
    );

const MotionExerciseDefinition seatedArmRaiseExercise =
    MotionExerciseDefinition(
      exerciseId: 'seated_bilateral_lateral_arm_raise',
      title: 'Seated bilateral arm raise',
      instructions:
          'Sit facing the phone and move both arms out to the sides through '
          'a comfortable range.',
      setupHint:
          'Sit about an arm-and-a-half from the phone so both hands stay in '
          'view at the top of the movement.',
      minimumRecordingRepetitions: 3,
      maximumRecordingRepetitions: 5,
      posture: MotionExercisePosture.seated,
      clinicalStatus: MotionExerciseClinicalStatus.development,
      videoSegment: sitNFitArmRaiseSegment,
      detailedAnalysis: MotionDetailedAnalysisSpec(
        kind: MotionAnalysisKind.bilateralLateralArmRaise,
        templateVersion: 1,
        referenceRomDegrees: 68,
        referenceTempoSeconds: 0.964,
      ),
    );

const MotionExerciseDefinition seatedForwardReachExercise =
    MotionExerciseDefinition(
      exerciseId: 'seated_bilateral_forward_reach',
      title: 'Seated forward reach',
      instructions:
          'Sit facing the phone and reach both arms forward and up, then '
          'lower them under control.',
      setupHint:
          'Leave room in front of you so your hands do not leave the frame '
          'at the top of the reach.',
      minimumRecordingRepetitions: 3,
      maximumRecordingRepetitions: 5,
      posture: MotionExercisePosture.seated,
      clinicalStatus: MotionExerciseClinicalStatus.development,
    );

const MotionExerciseDefinition seatedElbowFlexionExercise =
    MotionExerciseDefinition(
      exerciseId: 'seated_bilateral_elbow_flexion',
      title: 'Seated elbow bends',
      instructions:
          'With your arms at your sides, bend both elbows to bring your '
          'hands up, then lower them.',
      setupHint:
          'Keep your upper arms close to your body so the camera can see '
          'both elbows.',
      minimumRecordingRepetitions: 3,
      maximumRecordingRepetitions: 6,
      posture: MotionExercisePosture.seated,
      clinicalStatus: MotionExerciseClinicalStatus.development,
    );

const MotionExerciseDefinition seatedAlternatingMarchExercise =
    MotionExerciseDefinition(
      exerciseId: 'seated_alternating_march',
      title: 'Seated march',
      instructions:
          'Sitting tall, lift one knee at a time as if marching, '
          'alternating sides.',
      setupHint: 'Angle the phone so both knees stay in view while you march.',
      minimumRecordingRepetitions: 4,
      maximumRecordingRepetitions: 8,
      posture: MotionExercisePosture.seated,
      clinicalStatus: MotionExerciseClinicalStatus.development,
    );

const MotionExerciseDefinition sitToStandExercise = MotionExerciseDefinition(
  exerciseId: 'sit_to_stand',
  title: 'Sit to stand',
  instructions:
      'From sitting, stand up fully, then lower yourself back down with '
      'control.',
  setupHint:
      'Use a stable chair and stand the phone far enough back that your '
      'head and feet both stay in view standing up.',
  minimumRecordingRepetitions: 3,
  maximumRecordingRepetitions: 5,
  posture: MotionExercisePosture.standing,
  clinicalStatus: MotionExerciseClinicalStatus.development,
);

const MotionExerciseDefinition seatedTrunkLeanExercise =
    MotionExerciseDefinition(
      exerciseId: 'seated_lateral_trunk_lean',
      title: 'Seated side lean',
      instructions:
          'Sitting tall, lean gently to one side, return upright, then lean '
          'to the other side.',
      setupHint:
          'Sit square to the phone so a lean shows as a sideways tilt rather '
          'than a turn.',
      minimumRecordingRepetitions: 4,
      maximumRecordingRepetitions: 8,
      posture: MotionExercisePosture.seated,
      clinicalStatus: MotionExerciseClinicalStatus.development,
    );

/// Every exercise the motion engine can measure, in a reasonable warm-up to
/// weight-bearing order.
const List<MotionExerciseDefinition> motionExerciseCatalog =
    <MotionExerciseDefinition>[
      seatedArmRaiseExercise,
      seatedForwardReachExercise,
      seatedElbowFlexionExercise,
      seatedTrunkLeanExercise,
      seatedAlternatingMarchExercise,
      sitToStandExercise,
    ];

const String youTubeEmbeddedPlayerReferer = 'https://com.parkiwell.app';
const Map<String, String> youTubeEmbeddedPlayerHeaders = <String, String>{
  'Referer': youTubeEmbeddedPlayerReferer,
};

MotionExerciseDefinition? motionExerciseForVideo(String? videoId) {
  if (videoId == null) return null;
  for (final MotionExerciseDefinition exercise in motionExerciseCatalog) {
    if (exercise.videoSegment?.videoId == videoId) return exercise;
  }
  return null;
}

MotionExerciseDefinition motionExerciseById(String exerciseId) {
  for (final MotionExerciseDefinition exercise in motionExerciseCatalog) {
    if (exercise.exerciseId == exerciseId) return exercise;
  }
  throw ArgumentError('unknown catalog exercise: $exerciseId');
}

String _formatTimestamp(int totalSeconds) {
  final int minutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
