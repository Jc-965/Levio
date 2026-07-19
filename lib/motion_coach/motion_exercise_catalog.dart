enum MotionExercisePosture { seated, standing }

enum MotionExerciseClinicalStatus { development, clinicianApproved }

enum MotionAnalysisKind { bilateralLateralArmRaise }

class MotionExerciseDefinition {
  const MotionExerciseDefinition({
    required this.segmentId,
    required this.exerciseId,
    required this.videoId,
    required this.title,
    required this.sourceTitle,
    required this.sourceAttribution,
    required this.sourceReviewDate,
    required this.instructions,
    required this.startSeconds,
    required this.endSeconds,
    required this.demonstrationRepetitions,
    required this.minimumRecordingRepetitions,
    required this.maximumRecordingRepetitions,
    required this.posture,
    required this.templateVersion,
    required this.referenceRomDegrees,
    required this.referenceTempoSeconds,
    required this.clinicalStatus,
    required this.analysisKind,
  }) : assert(startSeconds >= 0),
       assert(endSeconds > startSeconds),
       assert(demonstrationRepetitions > 0),
       assert(minimumRecordingRepetitions > 0),
       assert(maximumRecordingRepetitions >= minimumRecordingRepetitions),
       assert(templateVersion > 0),
       assert(referenceRomDegrees > 0),
       assert(referenceTempoSeconds > 0),
       assert(sourceReviewDate.length == 10);

  final String segmentId;
  final String exerciseId;
  final String videoId;
  final String title;
  final String sourceTitle;
  final String sourceAttribution;
  final String sourceReviewDate;
  final String instructions;
  final int startSeconds;
  final int endSeconds;
  final int demonstrationRepetitions;
  final int minimumRecordingRepetitions;
  final int maximumRecordingRepetitions;
  final MotionExercisePosture posture;
  final int templateVersion;
  final double referenceRomDegrees;
  final double referenceTempoSeconds;
  final MotionExerciseClinicalStatus clinicalStatus;
  final MotionAnalysisKind analysisKind;

  int get demoDurationSeconds => endSeconds - startSeconds;

  String get recordingRepetitionLabel =>
      '$minimumRecordingRepetitions–$maximumRecordingRepetitions';

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

const String youTubeEmbeddedPlayerReferer = 'https://com.parkiwell.app';
const Map<String, String> youTubeEmbeddedPlayerHeaders = <String, String>{
  'Referer': youTubeEmbeddedPlayerReferer,
};

const MotionExerciseDefinition seatedArmRaiseExercise =
    MotionExerciseDefinition(
      segmentId: 'sit_n_fit_seated_arm_raise_32_55',
      exerciseId: 'seated_bilateral_lateral_arm_raise',
      videoId: 'AZV3_NfcpVs',
      title: 'Seated bilateral arm raise',
      sourceTitle: "Parkinson's Disease Exercises: Sit 'n' Fit",
      sourceAttribution: "Parkinson's Foundation (YouTube)",
      sourceReviewDate: '2026-07-19',
      instructions:
          'Sit facing the phone and move both arms out to the sides through '
          'a comfortable range.',
      startSeconds: 32,
      endSeconds: 55,
      demonstrationRepetitions: 3,
      minimumRecordingRepetitions: 3,
      maximumRecordingRepetitions: 5,
      posture: MotionExercisePosture.seated,
      templateVersion: 1,
      referenceRomDegrees: 68,
      referenceTempoSeconds: 0.964,
      clinicalStatus: MotionExerciseClinicalStatus.development,
      analysisKind: MotionAnalysisKind.bilateralLateralArmRaise,
    );

const List<MotionExerciseDefinition> motionExerciseCatalog =
    <MotionExerciseDefinition>[seatedArmRaiseExercise];

MotionExerciseDefinition? motionExerciseForVideo(String? videoId) {
  if (videoId == null) return null;
  for (final MotionExerciseDefinition exercise in motionExerciseCatalog) {
    if (exercise.videoId == videoId) return exercise;
  }
  return null;
}

String _formatTimestamp(int totalSeconds) {
  final int minutes = totalSeconds ~/ 60;
  final int seconds = totalSeconds.remainder(60);
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
