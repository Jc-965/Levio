import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/motion_coach/motion_analysis.dart';
import 'package:parkiwell/motion_coach/motion_exercise_catalog.dart';

void main() {
  group('motion exercise catalog', () {
    test('contains unique, valid source segments', () {
      final Set<String> segmentIds = <String>{};

      for (final MotionExerciseDefinition exercise in motionExerciseCatalog) {
        expect(segmentIds.add(exercise.segmentId), isTrue);
        expect(exercise.videoId, matches(RegExp(r'^[A-Za-z0-9_-]{11}$')));
        expect(exercise.startSeconds, greaterThanOrEqualTo(0));
        expect(exercise.endSeconds, greaterThan(exercise.startSeconds));
        expect(
          exercise.sourceReviewDate,
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
        );
        expect(
          exercise.maximumRecordingRepetitions,
          greaterThanOrEqualTo(exercise.minimumRecordingRepetitions),
        );
      }
    });

    test('maps the Sit n Fit video to the arm raise definition', () {
      final MotionExerciseDefinition? exercise = motionExerciseForVideo(
        'AZV3_NfcpVs',
      );

      expect(exercise, same(seatedArmRaiseExercise));
      expect(exercise!.demoDurationSeconds, 23);
      expect(exercise.demoTimeRangeLabel, '0:32–0:55');
      expect(exercise.demonstrationRepetitions, 3);
      expect(exercise.recordingRepetitionLabel, '3–5');
      expect(exercise.clinicalStatus, MotionExerciseClinicalStatus.development);
      expect(motionExerciseForVideo('QbWyxn8XE-I'), isNull);
      expect(motionExerciseForVideo(null), isNull);
    });

    test('builds an official bounded YouTube embed URL', () {
      final Uri uri = seatedArmRaiseExercise.youtubeEmbedUri(demoOnly: true);

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.youtube.com');
      expect(uri.path, '/embed/AZV3_NfcpVs');
      expect(uri.queryParameters['playsinline'], '1');
      expect(uri.queryParameters['controls'], '1');
      expect(uri.queryParameters['start'], '32');
      expect(uri.queryParameters['end'], '55');
      expect(youTubeEmbeddedPlayerHeaders, <String, String>{
        'Referer': 'https://com.parkiwell.app',
      });
    });

    test('builds a timestamped external watch URL', () {
      final Uri uri = seatedArmRaiseExercise.youtubeWatchUri(demoOnly: true);

      expect(uri.path, '/watch');
      expect(uri.queryParameters['v'], 'AZV3_NfcpVs');
      expect(uri.queryParameters['t'], '32s');
    });

    test('creates the matching analyzer template', () {
      final template = motionCoachTemplateFor(seatedArmRaiseExercise);

      expect(template.exerciseId, seatedArmRaiseExercise.exerciseId);
      expect(template.templateVersion, seatedArmRaiseExercise.templateVersion);
      expect(template.primarySignal, 'arm_elevation_mean');
      expect(
        template.referenceRomDeg,
        seatedArmRaiseExercise.referenceRomDegrees,
      );
      expect(
        template.referenceTempoS,
        seatedArmRaiseExercise.referenceTempoSeconds,
      );
    });
  });
}
