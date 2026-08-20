import 'package:flutter_test/flutter_test.dart';
import 'package:motion_engine/motion_engine.dart';
import 'package:parkiwell/motion_coach/motion_analysis.dart';
import 'package:parkiwell/motion_coach/motion_exercise_catalog.dart';
import 'package:parkiwell/motion_coach/motion_pose_bridge.dart';
import 'package:parkiwell/motion_coach/motion_reference_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('motion exercise catalog', () {
    test('covers every exercise the engine implements, exactly once', () {
      final Set<String> catalogIds = <String>{
        for (final MotionExerciseDefinition exercise in motionExerciseCatalog)
          exercise.exerciseId,
      };

      expect(catalogIds, hasLength(motionExerciseCatalog.length));
      expect(catalogIds, exerciseRegistry.keys.toSet());
    });

    test('names an engine specification and readable copy for each entry', () {
      for (final MotionExerciseDefinition exercise in motionExerciseCatalog) {
        expect(exercise.engineSpec.exerciseId, exercise.exerciseId);
        expect(exercise.title, isNotEmpty);
        expect(exercise.instructions, isNotEmpty);
        expect(exercise.setupHint, isNotEmpty);
        expect(
          exercise.maximumRecordingRepetitions,
          greaterThanOrEqualTo(exercise.minimumRecordingRepetitions),
        );
      }
    });

    test('posture agrees with the engine specification', () {
      for (final MotionExerciseDefinition exercise in motionExerciseCatalog) {
        final ExercisePosture expected =
            exercise.posture == MotionExercisePosture.seated
            ? ExercisePosture.seated
            : ExercisePosture.standing;
        expect(exercise.engineSpec.posture, expected);
      }
    });

    test('video segments are unique and well formed where present', () {
      final Set<String> segmentIds = <String>{};
      int withVideo = 0;

      for (final MotionExerciseDefinition exercise in motionExerciseCatalog) {
        final MotionExerciseVideoSegment? segment = exercise.videoSegment;
        if (segment == null) continue;
        withVideo += 1;
        expect(segmentIds.add(segment.segmentId), isTrue);
        expect(segment.videoId, matches(RegExp(r'^[A-Za-z0-9_-]{11}$')));
        expect(segment.startSeconds, greaterThanOrEqualTo(0));
        expect(segment.endSeconds, greaterThan(segment.startSeconds));
        expect(
          segment.sourceReviewDate,
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
        );
      }

      expect(withVideo, 1);
    });

    test('maps the Sit n Fit video to the arm raise definition', () {
      final MotionExerciseDefinition? exercise = motionExerciseForVideo(
        'AZV3_NfcpVs',
      );

      expect(exercise, same(seatedArmRaiseExercise));
      expect(exercise!.videoSegment!.demoDurationSeconds, 23);
      expect(exercise.videoSegment!.demoTimeRangeLabel, '0:32–0:55');
      expect(exercise.videoSegment!.demonstrationRepetitions, 3);
      expect(exercise.recordingRepetitionLabel, '3–5');
      expect(exercise.clinicalStatus, MotionExerciseClinicalStatus.development);
      expect(motionExerciseForVideo('QbWyxn8XE-I'), isNull);
      expect(motionExerciseForVideo(null), isNull);
    });

    test('looks exercises up by their engine id', () {
      expect(motionExerciseById('sit_to_stand'), same(sitToStandExercise));
      expect(() => motionExerciseById('not_an_exercise'), throwsArgumentError);
    });

    test('builds an official bounded YouTube embed URL', () {
      final Uri uri = sitNFitArmRaiseSegment.youtubeEmbedUri(demoOnly: true);

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
      final Uri uri = sitNFitArmRaiseSegment.youtubeWatchUri(demoOnly: true);

      expect(uri.path, '/watch');
      expect(uri.queryParameters['v'], 'AZV3_NfcpVs');
      expect(uri.queryParameters['t'], '32s');
    });

    test('every catalog exercise builds an analyzer template from its '
        'vendored asset', () async {
      final MotionReferenceLibrary library = MotionReferenceLibrary();
      for (final MotionExerciseDefinition exercise in motionExerciseCatalog) {
        final Map<String, Object?> json = await library.templateFor(
          exercise.exerciseId,
        );
        final ExerciseTemplate template = motionCoachTemplateFromJson(json);
        expect(template.exerciseId, exercise.exerciseId);
        // The template's measured signal must be the one the live engine
        // watches, or live and offline feedback would describe different
        // movements.
        expect(template.primarySignal, exercise.engineSpec.primarySignal);
        // The substitution swaps only the pose model identity, never the
        // coordinate space the reference statistics were measured in.
        expect(template.poseContract.coordinateSpace, 'mediapipe_world_3d');
        expect(template.poseContract.model, motionPoseModelName);
        expect(template.allowedOrientations, <String>{'portrait'});
        expect(template.referenceRomDeg, greaterThan(0));
        expect(template.referenceTempoS, greaterThan(0));
      }
    });

    test('rejects a template measured in another coordinate space', () async {
      final MotionReferenceLibrary library = MotionReferenceLibrary();
      final Map<String, Object?> json = Map<String, Object?>.of(
        await library.templateFor('seated_bilateral_lateral_arm_raise'),
      );
      json['pose_contract'] = <String, Object?>{
        ...json['pose_contract']! as Map<String, Object?>,
        'coordinate_space': 'normalized_2d',
      };
      expect(
        () => motionCoachTemplateFromJson(json),
        throwsFormatException,
      );
    });
  });
}
