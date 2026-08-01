import 'package:flutter_test/flutter_test.dart';
import 'package:motion_engine/motion_engine.dart';
import 'package:parkiwell/motion_coach/motion_coach_home_screen.dart';
import 'package:parkiwell/motion_coach/motion_coach_session.dart';
import 'package:parkiwell/motion_coach/motion_exercise_catalog.dart';
import 'package:parkiwell/motion_coach/motion_reference_library.dart';
import 'package:parkiwell/motion_coach/motion_routine_catalog.dart';
import 'package:parkiwell/motion_coach/motion_routine_controller.dart';

import 'motion_pose_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MotionReferenceLibrary', () {
    test('loads a template for every catalog exercise', () async {
      final MotionReferenceLibrary library = MotionReferenceLibrary();
      await library.loadTemplates();

      for (final MotionExerciseDefinition exercise in motionExerciseCatalog) {
        final Map<String, Object?> template = library.template(
          exercise.exerciseId,
        );
        expect(template['schema_version'], 'exercise-template.v1');
        expect(template['exercise_id'], exercise.exerciseId);
        expect(template['primary_signal'], exercise.engineSpec.primarySignal);
      }
    });

    test('refuses a synchronous lookup before the asset is read', () {
      expect(
        () => MotionReferenceLibrary().template('sit_to_stand'),
        throwsStateError,
      );
    });

    test('derives live thresholds from the template, not the app', () async {
      final MotionReferenceLibrary library = MotionReferenceLibrary();
      await library.templateFor('seated_bilateral_lateral_arm_raise');
      final LiveExerciseCoachConfig config = library.configFor(
        'seated_bilateral_lateral_arm_raise',
      );

      expect(config.referenceRomDeg, closeTo(70, 0.5));
      // Threshold-crossing tempo, which is shorter than the template's
      // full valley-to-valley median.
      expect(config.referenceTempoS, closeTo(2.93, 0.05));
    });

    test('loads every routine and preloads the templates it names', () async {
      for (final MotionRoutineDescription description in motionRoutineCatalog) {
        final MotionReferenceLibrary library = MotionReferenceLibrary();
        final RoutineDefinition routine = await library.loadRoutine(
          description.routineAssetId,
        );

        expect(routine.steps, isNotEmpty);
        for (final RoutineStepDefinition step in routine.steps) {
          expect(
            () => motionExerciseById(step.exerciseId),
            returnsNormally,
            reason: '${description.routineAssetId} names ${step.exerciseId}',
          );
          // Preloaded, so RoutineSession can build its coaches synchronously.
          expect(() => library.template(step.exerciseId), returnsNormally);
        }
      }
    });

    test('decodes a demonstration loop of consistent size', () async {
      final MotionDemonstrationLoop loop = await MotionReferenceLibrary()
          .loadDemonstration('sit_to_stand');

      expect(loop.exerciseId, 'sit_to_stand');
      expect(loop.frameCount, greaterThan(0));
      expect(loop.pointsXy, hasLength(loop.frameCount * 33 * 2));
      expect(loop.frame(0), hasLength(33));
      // Frame indices wrap, so an animation clock can run past the end.
      expect(loop.frame(loop.frameCount), loop.frame(0));
      expect(loop.frameIndexAt(loop.duration), 0);
    });
  });

  group('MotionRoutineController', () {
    test('gates the start on stable framing', () async {
      final MotionRoutineController controller = await _controller(
        targetRepetitions: 2,
      );
      addTearDown(controller.dispose);

      expect(controller.isFramingReady, isFalse);
      for (int index = 0; index < 6; index += 1) {
        controller.handleSample(armRaiseSample(10, index * 60));
      }
      expect(controller.isFramingReady, isTrue);
      expect(controller.framingStatus, MotionFramingStatus.ready);
    });

    test('scores repetitions, then completes with an evaluation', () async {
      final MotionRoutineController controller = await _controller(
        targetRepetitions: 2,
      );
      addTearDown(controller.dispose);

      controller.start();
      expect(controller.phase, MotionRoutinePhase.active);
      expect(controller.currentExercise, same(seatedArmRaiseExercise));

      _driveRepetitions(controller, count: 2, startMs: 200);

      expect(controller.completedRepetitions, 2);
      expect(controller.lastRepScore, isNotNull);
      expect(controller.phase, MotionRoutinePhase.complete);

      final Map<String, Object?> evaluation = controller.evaluation!;
      expect(evaluation['schema_version'], 'session-evaluation.v1');
      final Map<String, Object?> overall =
          evaluation['overall']! as Map<String, Object?>;
      expect(overall['total_steps'], 1);
      expect(overall['assessed_steps'], 1);
      expect(overall['score'], isA<double>());
    });

    test('reports progress across the whole routine', () async {
      final MotionRoutineController controller = await _controller(
        targetRepetitions: 4,
      );
      addTearDown(controller.dispose);

      controller.start();
      expect(controller.progress, 0);
      _driveRepetitions(controller, count: 2, startMs: 200);
      expect(controller.progress, closeTo(0.5, 1e-9));
    });

    test('does not charge camera setup time against the step', () async {
      final MotionRoutineController controller = await _controller(
        targetRepetitions: 2,
        maximumDurationS: 30,
      );
      addTearDown(controller.dispose);

      // Two minutes of framing before the person taps start — far past the
      // step's own 30-second limit.
      for (int index = 0; index < 6; index += 1) {
        controller.handleSample(armRaiseSample(10, 120000 + index * 60));
      }
      controller.start();
      _driveRepetitions(controller, count: 2, startMs: 120400);

      expect(controller.completedRepetitions, 2);
      expect(controller.phase, MotionRoutinePhase.complete);
      final Map<String, Object?> overall =
          controller.evaluation!['overall']! as Map<String, Object?>;
      expect(overall['assessed_steps'], 1);
    });

    test('reset abandons the run without producing an evaluation', () async {
      final MotionRoutineController controller = await _controller(
        targetRepetitions: 4,
      );
      addTearDown(controller.dispose);

      controller.start();
      _driveRepetitions(controller, count: 1, startMs: 200);
      controller.reset();

      expect(controller.isStarted, isFalse);
      expect(controller.evaluation, isNull);
      expect(controller.completedRepetitions, 0);
      expect(controller.phase, MotionRoutinePhase.framing);
    });
  });

  group('single-exercise practice', () {
    test('is a one-step routine over the same engine path', () {
      final RoutineDefinition routine = singleExerciseRoutine(
        sitToStandExercise,
      );

      expect(routine.steps, hasLength(1));
      expect(routine.steps.single.exerciseId, 'sit_to_stand');
      expect(
        routine.steps.single.targetRepetitions,
        sitToStandExercise.maximumRecordingRepetitions,
      );
      expect(routine.steps.single.restDurationS, 0);
    });

    test('marks a standing exercise in its description', () {
      expect(
        singleExerciseDescription(sitToStandExercise).requiresStanding,
        isTrue,
      );
      expect(
        singleExerciseDescription(seatedArmRaiseExercise).requiresStanding,
        isFalse,
      );
    });

    test('every catalog exercise builds a valid routine', () {
      for (final MotionExerciseDefinition exercise in motionExerciseCatalog) {
        expect(() => singleExerciseRoutine(exercise), returnsNormally);
      }
    });
  });
}

Future<MotionRoutineController> _controller({
  required int targetRepetitions,
  double maximumDurationS = 600,
}) async {
  final MotionReferenceLibrary library = MotionReferenceLibrary();
  await library.templateFor(seatedArmRaiseExercise.exerciseId);
  return MotionRoutineController(
    routine: RoutineDefinition(
      routineId: 'test_routine',
      routineVersion: 1,
      displayName: 'Test routine',
      steps: <RoutineStepDefinition>[
        RoutineStepDefinition(
          exerciseId: seatedArmRaiseExercise.exerciseId,
          targetRepetitions: targetRepetitions,
          maximumDurationS: maximumDurationS,
          restDurationS: 0,
        ),
      ],
    ),
    library: library,
  );
}

/// Feed [count] complete raises, slow and large enough that the engine
/// accepts them against the shipped template's thresholds.
void _driveRepetitions(
  MotionRoutineController controller, {
  required int count,
  required int startMs,
}) {
  int timestampMs = startMs;
  for (int repetition = 0; repetition < count; repetition += 1) {
    for (final double phase in repPhase) {
      controller.handleSample(armRaiseSample(10 + 60 * phase, timestampMs));
      timestampMs += 200;
    }
  }
}
