import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_engine/motion_engine.dart';
import 'package:parkiwell/motion_coach/motion_analysis.dart';
import 'package:parkiwell/motion_coach/motion_capture_driver.dart';
import 'package:parkiwell/motion_coach/motion_coach_results_screen.dart';
import 'package:parkiwell/motion_coach/motion_coach_screen.dart';
import 'package:parkiwell/motion_coach/motion_coach_session.dart';
import 'package:parkiwell/motion_coach/motion_cue_speaker.dart';
import 'package:parkiwell/motion_coach/motion_exercise_catalog.dart';
import 'package:parkiwell/motion_coach/motion_pose_bridge.dart';
import 'package:parkiwell/motion_coach/motion_reference_library.dart';
import 'package:parkiwell/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('MotionCoachSession', () {
    test(
      'requires stable framing and uses hysteresis when framing is lost',
      () {
        final MotionCoachSession session = _session();
        addTearDown(session.dispose);

        for (int index = 0; index < 5; index += 1) {
          session.handleSample(_sample(timestampMs: index * 60));
        }
        expect(session.isReady, isFalse);

        session.handleSample(_sample(timestampMs: 300));
        expect(session.isReady, isTrue);
        expect(session.framingStatus, MotionFramingStatus.ready);

        session.handleSample(_sample(timestampMs: 360, visible: false));
        session.handleSample(_sample(timestampMs: 420, visible: false));
        expect(session.isReady, isTrue);

        session.handleSample(_sample(timestampMs: 480, visible: false));
        expect(session.isReady, isFalse);
        expect(session.framingStatus, MotionFramingStatus.showMoreBody);
      },
    );

    test(
      'buffers only ordered recording frames and drains them immediately',
      () {
        final MotionCoachSession session = _session();
        addTearDown(session.dispose);

        session.handleSample(_sample(timestampMs: 0));
        expect(session.bufferedFrameCount, 0);

        session.beginRecording();
        session.handleSample(_sample(timestampMs: 60));
        session.handleSample(_sample(timestampMs: 60));
        session.handleSample(_sample(timestampMs: 120, hasPose: false));

        expect(session.bufferedFrameCount, 2);
        final List<PoseFrame> frames = session.finishAndDrain();
        expect(frames, hasLength(2));
        expect(frames.first.landmarks, hasLength(33));
        expect(frames.last.landmarks, isNull);
        expect(session.bufferedFrameCount, 0);
        expect(session.isRecording, isFalse);
      },
    );

    test('does not analyze frames containing multiple people', () {
      final MotionCoachSession session = _session();
      addTearDown(session.dispose);

      session.beginRecording();
      // Three identical readings: the published framing status is debounced
      // so a single frame cannot reclassify it.
      session.handleSample(_sample(timestampMs: 60, poseCount: 2));
      session.handleSample(_sample(timestampMs: 120, poseCount: 2));
      session.handleSample(_sample(timestampMs: 180, poseCount: 2));

      final List<PoseFrame> frames = session.finishAndDrain();
      expect(frames, hasLength(3));
      expect(frames.first.landmarks, isNull);
      expect(frames.last.landmarks, isNull);
      expect(session.framingStatus, MotionFramingStatus.multiplePeople);
    });

    test('counts a live rep, scores it, and exposes an allowlisted cue', () {
      final MotionCoachSession session = _session();
      addTearDown(session.dispose);
      session.beginRecording();
      for (int index = 0; index < _repPhase.length; index += 1) {
        session.handleSample(
          _motionSampleForAngle(10 + 40 * _repPhase[index], index * 200),
        );
      }

      expect(session.liveRepCount, 1);
      expect(session.liveCue!.kind, ExerciseCueKind.amplitude);
      expect(session.liveCue!.text, contains('If comfortable'));
      // Scores are the engine's, never the app's: a half-reference raise
      // must not read as a good repetition.
      expect(session.lastRepScore!.rangeScore, lessThan(60));
      expect(session.averageRepScore, session.lastRepScore!.overall);
      expect(session.maximumDecisionMicros, lessThan(100000));
    });

    test('distinguishes missing, cropped, and distant framing', () {
      expect(
        assessFraming(MotionPoseDetection.empty(timestampMs: 0)),
        MotionFramingStatus.lookingForPerson,
      );
      expect(
        assessFraming(_detection(timestampMs: 60, visible: false)),
        MotionFramingStatus.showMoreBody,
      );
      expect(
        assessFraming(_detection(timestampMs: 120, closeEnough: false)),
        MotionFramingStatus.moveCloser,
      );
      expect(
        assessFraming(
          MotionPoseDetection(
            timestampMs: 180,
            normalizedLandmarks: _detection(
              timestampMs: 180,
            ).normalizedLandmarks,
            worldLandmarks: null,
            inferenceMs: 8,
            poseCount: 2,
          ),
        ),
        MotionFramingStatus.multiplePeople,
      );
    });
  });

  test(
    'analysis abstains instead of inventing metrics for missing poses',
    () async {
      final List<PoseFrame> frames = List<PoseFrame>.generate(
        30,
        (int index) => PoseFrame(timestampMs: index * 60, landmarks: null),
      );

      final MotionAnalysisResult result = await const MotionCoachAnalyzer()
          .analyze(
            frames: frames,
            width: 480,
            height: 640,
            runtime: 'mediapipe_tasks_test',
          );

      expect(result.needsSetupHelp, isTrue);
      expect(result.sessionConfidence, 'insufficient');
      expect(result.repCount, isNull);
      expect(result.flags, contains('low_coverage'));
    },
  );

  test('analysis handles an immediately finished empty recording', () async {
    final MotionAnalysisResult result = await const MotionCoachAnalyzer()
        .analyze(
          frames: const <PoseFrame>[],
          width: 480,
          height: 640,
          runtime: 'mediapipe_tasks_test',
        );

    expect(result.needsSetupHelp, isTrue);
    expect(result.sessionConfidence, 'insufficient');
    expect(result.repCount, isNull);
  });

  test('parses per-repetition evidence from the vendored engine', () {
    final List<double> signal = <double>[
      10,
      30,
      50,
      70,
      90,
      70,
      50,
      30,
      10,
      26,
      42,
      58,
      74,
      58,
      42,
      26,
      10,
      22,
      34,
      46,
      58,
      46,
      34,
      22,
      10,
    ];
    final AnalysisDocument document = analyzeArmRaiseSession(
      features: <String, List<double>>{
        'arm_elevation_mean': signal,
        'arm_elevation_l': signal,
        'arm_elevation_r': signal,
      },
      timestampsMs: <int>[
        for (int index = 0; index < signal.length; index += 1) index * 100,
      ],
      coverage: CoverageAssessment(
        level: ConfidenceLevel.high,
        coverage: 1,
        validFrames: signal.length,
        totalFrames: signal.length,
        reasons: const <ReasonCode>[],
      ),
      exerciseId: 'seated_bilateral_lateral_arm_raise',
      templateVersion: 1,
      referenceRomDeg: 80,
      referenceTempoS: 0.8,
      engineVersion: 'test',
      provenance: const <String, Object?>{},
    );

    final MotionAnalysisResult result = MotionAnalysisResult.fromDocument(
      document,
      referenceRomDegrees: 80,
      referenceTempoSeconds: 0.8,
    );

    expect(result.repCount, 3);
    expect(result.repetitions, hasLength(3));
    expect(result.repetitions.first.romDegrees, closeTo(80, 1e-9));
    expect(result.repetitions.last.romDegrees, closeTo(48, 1e-9));
    expect(result.amplitudeSequenceLastFirstRatio, closeTo(0.6, 1e-9));
    expect(
      result.sequenceSummary,
      contains('first complete raise measured 80°'),
    );
    expect(result.sequenceSummary, contains('last measured 48°'));
  });

  group('MotionCoachResultsScreen', () {
    testWidgets('shows setup help without unreliable observations', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        MotionCoachResultsScreen(
          result: _result(
            confidence: 'insufficient',
            reasons: const <String>['low_sampling_rate'],
          ),
        ),
      );

      expect(find.text('Let’s adjust the setup'), findsOneWidget);
      expect(
        find.textContaining('did not analyze frames quickly enough'),
        findsOneWidget,
      );
      expect(find.text('Complete raises'), findsNothing);
      expect(find.text('Keep private recording'), findsOneWidget);
      expect(find.textContaining('not a diagnosis'), findsOneWidget);
    });

    testWidgets('shows neutral observations for a supported result', (
      WidgetTester tester,
    ) async {
      await _pumpApp(
        tester,
        MotionCoachResultsScreen(
          result: _result(
            confidence: 'high',
            repCount: 3,
            rangeDegrees: 64.4,
            rangePercentOfReference: 94.7,
            tempoSeconds: 1.12,
            sideRangeRatio: 0.91,
            amplitudeSequenceLastFirstRatio: 0.8,
            repetitions: const <MotionRepObservation>[
              MotionRepObservation(
                index: 1,
                startSeconds: 0,
                peakSeconds: 0.5,
                endSeconds: 1,
                romDegrees: 70,
                romPercentOfReference: 103,
                tempoSeconds: 1,
                leftRomDegrees: 72,
                rightRomDegrees: 68,
                sideRangeRatio: 0.94,
                confidence: 'high',
                reasonCodes: <String>[],
              ),
              MotionRepObservation(
                index: 2,
                startSeconds: 1,
                peakSeconds: 1.5,
                endSeconds: 2,
                romDegrees: 64,
                romPercentOfReference: 94,
                tempoSeconds: 1,
                leftRomDegrees: 66,
                rightRomDegrees: 62,
                sideRangeRatio: 0.94,
                confidence: 'high',
                reasonCodes: <String>[],
              ),
              MotionRepObservation(
                index: 3,
                startSeconds: 2,
                peakSeconds: 2.5,
                endSeconds: 3,
                romDegrees: 56,
                romPercentOfReference: 82,
                tempoSeconds: 1,
                leftRomDegrees: 58,
                rightRomDegrees: 54,
                sideRangeRatio: 0.93,
                confidence: 'high',
                reasonCodes: <String>[],
              ),
            ],
          ),
        ),
      );

      expect(find.text('Movement captured'), findsOneWidget);
      expect(find.text('Complete raises'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('64°'), findsOneWidget);
      expect(find.text('1.1 sec'), findsOneWidget);
      expect(find.text('91%'), findsOneWidget);
      expect(find.text('Practice summary'), findsOneWidget);
      expect(
        find.textContaining('95% of this exercise reference'),
        findsWidgets,
      );
      expect(find.text('70° → 56°'), findsOneWidget);
      expect(find.textContaining('not a fatigue score'), findsOneWidget);
      expect(find.textContaining('stop if you feel pain'), findsOneWidget);
      expect(find.text('Use this result'), findsOneWidget);
    });
  });

  group('MotionCoachScreen', () {
    // Asset I/O must not happen inside a testWidgets body: the
    // widget-test zone controls the clock, and a real bundle read
    // awaited there never completes.
    late MotionReferenceLibrary library;
    setUpAll(() async => library = await _armRaiseLibrary());

    testWidgets('explains how to recover from denied camera access', (
      WidgetTester tester,
    ) async {
      final _FakeMotionCaptureDriver driver = _FakeMotionCaptureDriver(
        initializeError: CameraException(
          'CameraAccessDenied',
          'Permission denied',
        ),
      );
      await _pumpApp(
        tester,
        MotionCoachScreen(library: library, driverFactory: () => driver),
      );
      await tester.pumpAndSettle();

      expect(find.text('Camera access is needed'), findsOneWidget);
      expect(find.textContaining('allow Camera access'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(driver.disposeCalls, 1);
    });

    testWidgets('shows a large live cue and completed-rep count', (
      WidgetTester tester,
    ) async {
      final _FakeMotionCaptureDriver driver = _FakeMotionCaptureDriver();
      final _FakeMotionCueSpeaker speaker = _FakeMotionCueSpeaker();
      await _pumpApp(
        tester,
        MotionCoachScreen(
          library: library,
          driverFactory: () => driver,
          cueSpeaker: speaker,
        ),
      );
      await tester.pumpAndSettle();
      for (int index = 0; index < 6; index += 1) {
        driver.emit(_sample(timestampMs: index * 60));
      }
      await tester.pump();
      await tester.ensureVisible(find.text('Start movement'));
      await tester.tap(find.text('Start movement'));
      await tester.pumpAndSettle();

      for (int index = 0; index < _repPhase.length; index += 1) {
        driver.emit(
          _motionSampleForAngle(10 + 40 * _repPhase[index], 400 + index * 200),
        );
      }
      await tester.pump();

      expect(find.text('1 complete'), findsOneWidget);
      expect(
        find.text('If comfortable, make the next raise a little larger.'),
        findsWidgets,
      );
      expect(speaker.spoken, <String>[
        'If comfortable, make the next raise a little larger.',
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(speaker.disposed, isTrue);
    });

    testWidgets('surfaces an error when pose detection keeps failing', (
      WidgetTester tester,
    ) async {
      final _FakeMotionCaptureDriver driver = _FakeMotionCaptureDriver();
      await _pumpApp(
        tester,
        MotionCoachScreen(library: library, driverFactory: () => driver),
      );
      await tester.pumpAndSettle();

      driver.persistentFailureCallback!();
      await tester.pumpAndSettle();

      expect(find.text('Movement tracking stopped working'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(driver.disposeCalls, 1);
    });

    testWidgets('backgrounding during finish cannot wipe the recording', (
      WidgetTester tester,
    ) async {
      final _FakeMotionCaptureDriver driver = _FakeMotionCaptureDriver();
      await _pumpApp(
        tester,
        MotionCoachScreen(
          library: library,
          driverFactory: () => driver,
          // A canned result keeps the finish path inside the fake-async
          // zone; the real analyzer would hop to an isolate the widget
          // test clock cannot drive.
          analyzer: _CannedAnalyzer(_result(confidence: 'high', repCount: 1)),
        ),
      );
      await tester.pumpAndSettle();
      for (int index = 0; index < 6; index += 1) {
        driver.emit(_sample(timestampMs: index * 60));
      }
      await tester.pump();
      await tester.ensureVisible(find.text('Start movement'));
      await tester.tap(find.text('Start movement'));
      await tester.pumpAndSettle();
      driver.emit(_sample(timestampMs: 400));

      // Stall stopRecording so the lifecycle event lands mid-finalization.
      driver.holdStopRecording = true;
      await tester.ensureVisible(find.text('Finish and review'));
      await tester.tap(find.text('Finish and review'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // The suspend path must not have cancelled or disposed the driver the
      // finish already owns, nor reset the session's buffered frames.
      expect(driver.cancelCalls, 0);
      expect(driver.disposeCalls, 0);

      driver.releaseStopRecording();
      await tester.pumpAndSettle();
      expect(find.text('Motion check'), findsOneWidget);
      expect(driver.disposeCalls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'cancels and disposes a recording when the app is backgrounded',
      (WidgetTester tester) async {
        final _FakeMotionCaptureDriver driver = _FakeMotionCaptureDriver();
        await _pumpApp(
          tester,
          MotionCoachScreen(library: library, driverFactory: () => driver),
        );
        await tester.pumpAndSettle();

        for (int index = 0; index < 6; index += 1) {
          driver.emit(_sample(timestampMs: index * 60));
        }
        await tester.pump();

        await tester.ensureVisible(find.text('Start movement'));
        await tester.tap(find.text('Start movement'));
        await tester.pumpAndSettle();
        expect(find.text('Finish and review'), findsOneWidget);
        expect(driver.isRecording, isTrue);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();

        expect(driver.cancelCalls, 1);
        expect(driver.disposeCalls, 1);

        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
    );
  });
}

/// One rise-and-return cycle, sampled as a fraction of the peak.
const List<double> _repPhase = <double>[
  0,
  0.25,
  0.5,
  0.75,
  1,
  0.75,
  0.5,
  0.25,
  0,
  0,
  0,
  0,
];

/// A session wired to the real arm-raise specification with explicit
/// thresholds, so the pure-logic tests need no asset bundle.
MotionCoachSession _session() => MotionCoachSession(
  liveCoach: LiveExerciseCoach(
    seatedArmRaiseExercise.engineSpec,
    const LiveExerciseCoachConfig(referenceRomDeg: 70, referenceTempoS: 2.93),
  ),
);

/// A library holding the shipped arm-raise template, loaded from the real
/// asset so the widget tests exercise the same thresholds as the app.
Future<MotionReferenceLibrary> _armRaiseLibrary() async {
  final MotionReferenceLibrary library = MotionReferenceLibrary();
  await library.templateFor(seatedArmRaiseExercise.exerciseId);
  return library;
}

Future<void> _pumpApp(WidgetTester tester, Widget home) {
  return tester.pumpWidget(
    MaterialApp(theme: AppTheme.lightTheme(), home: home),
  );
}

MotionPoseSample _sample({
  required int timestampMs,
  bool visible = true,
  bool hasPose = true,
  int poseCount = 1,
}) {
  return MotionPoseSample(
    detection: hasPose
        ? _detection(
            timestampMs: timestampMs,
            visible: visible,
            poseCount: poseCount,
          )
        : MotionPoseDetection.empty(timestampMs: timestampMs),
    frameWidth: 480,
    frameHeight: 640,
  );
}

MotionPoseSample _motionSampleForAngle(double angleDegrees, int timestampMs) {
  final MotionPoseDetection base = _detection(timestampMs: timestampMs);
  final List<MotionPoseLandmark> world = List<MotionPoseLandmark>.generate(
    33,
    (_) =>
        const MotionPoseLandmark(x: 0, y: 0, z: 0, visibility: 1, presence: 1),
  );
  const MotionPoseLandmark leftShoulder = MotionPoseLandmark(
    x: -0.2,
    y: -0.5,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  const MotionPoseLandmark rightShoulder = MotionPoseLandmark(
    x: 0.2,
    y: -0.5,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  final double radians = angleDegrees * math.pi / 180;
  world[11] = leftShoulder;
  world[12] = rightShoulder;
  world[15] = MotionPoseLandmark(
    x: leftShoulder.x - math.sin(radians),
    y: leftShoulder.y + math.cos(radians),
    z: 0,
    visibility: 1,
    presence: 1,
  );
  world[16] = MotionPoseLandmark(
    x: rightShoulder.x + math.sin(radians),
    y: rightShoulder.y + math.cos(radians),
    z: 0,
    visibility: 1,
    presence: 1,
  );
  world[23] = const MotionPoseLandmark(
    x: -0.2,
    y: 0,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  world[24] = const MotionPoseLandmark(
    x: 0.2,
    y: 0,
    z: 0,
    visibility: 1,
    presence: 1,
  );
  return MotionPoseSample(
    detection: MotionPoseDetection(
      timestampMs: timestampMs,
      normalizedLandmarks: base.normalizedLandmarks,
      worldLandmarks: world,
      inferenceMs: 8,
      poseCount: 1,
    ),
    frameWidth: 480,
    frameHeight: 640,
  );
}

MotionPoseDetection _detection({
  required int timestampMs,
  bool visible = true,
  bool closeEnough = true,
  int poseCount = 1,
}) {
  final List<MotionPoseLandmark> normalized = List<MotionPoseLandmark>.generate(
    33,
    (_) => MotionPoseLandmark(
      x: 0.5,
      y: 0.5,
      z: 0,
      visibility: visible ? 1 : 0,
      presence: visible ? 1 : 0,
    ),
  );
  normalized[0] = _landmark(0.5, 0.14, visible);
  normalized[11] = _landmark(closeEnough ? 0.34 : 0.48, 0.34, visible);
  normalized[12] = _landmark(closeEnough ? 0.66 : 0.52, 0.34, visible);
  normalized[15] = _landmark(0.24, 0.55, visible);
  normalized[16] = _landmark(0.76, 0.55, visible);
  normalized[23] = _landmark(0.4, closeEnough ? 0.66 : 0.42, visible);
  normalized[24] = _landmark(0.6, closeEnough ? 0.66 : 0.42, visible);
  final List<MotionPoseLandmark> world = List<MotionPoseLandmark>.generate(
    33,
    (int index) => MotionPoseLandmark(
      x: normalized[index].x,
      y: normalized[index].y,
      z: 0,
      visibility: normalized[index].visibility,
      presence: normalized[index].presence,
    ),
  );
  return MotionPoseDetection(
    timestampMs: timestampMs,
    normalizedLandmarks: normalized,
    worldLandmarks: world,
    inferenceMs: 8,
    poseCount: poseCount,
  );
}

MotionPoseLandmark _landmark(double x, double y, bool visible) {
  return MotionPoseLandmark(
    x: x,
    y: y,
    z: 0,
    visibility: visible ? 1 : 0,
    presence: visible ? 1 : 0,
  );
}

MotionAnalysisResult _result({
  required String confidence,
  List<String> reasons = const <String>[],
  int? repCount,
  double? rangeDegrees,
  double? rangePercentOfReference,
  double? tempoSeconds,
  double? sideRangeRatio,
  double? amplitudeSequenceLastFirstRatio,
  List<MotionRepObservation> repetitions = const <MotionRepObservation>[],
}) {
  return MotionAnalysisResult(
    document: const <String, Object?>{},
    sessionConfidence: confidence,
    reasonCodes: reasons,
    flags: const <String>[],
    coverage: confidence == 'high' ? 1 : 0.4,
    durationSeconds: 4,
    repCount: repCount,
    rangeDegrees: rangeDegrees,
    rangePercentOfReference: rangePercentOfReference,
    tempoSeconds: tempoSeconds,
    sideRangeRatio: sideRangeRatio,
    amplitudeSequenceLastFirstRatio: amplitudeSequenceLastFirstRatio,
    repetitions: repetitions,
    referenceRomDegrees: 68,
    referenceTempoSeconds: 0.964,
  );
}

class _FakeMotionCaptureDriver implements MotionCaptureDriver {
  _FakeMotionCaptureDriver({this.initializeError});

  final CameraException? initializeError;
  MotionSampleCallback? _onSample;
  VoidCallback? persistentFailureCallback;
  bool _initialized = false;
  bool _recording = false;
  int cancelCalls = 0;
  int disposeCalls = 0;

  @override
  bool get isInitialized => _initialized;

  @override
  bool get isRecording => _recording;

  @override
  double get aspectRatio => 3 / 4;

  void emit(MotionPoseSample sample) => _onSample?.call(sample);

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.black);

  @override
  Future<void> initialize(
    MotionSampleCallback onSample, {
    VoidCallback? onPersistentFailure,
  }) async {
    if (initializeError != null) throw initializeError!;
    _onSample = onSample;
    persistentFailureCallback = onPersistentFailure;
    _initialized = true;
  }

  @override
  Future<void> startRecording() async {
    _recording = true;
  }

  bool holdStopRecording = false;
  Completer<void>? _stopGate;

  void releaseStopRecording() => _stopGate?.complete();

  @override
  Future<String> stopRecording() async {
    if (holdStopRecording) {
      _stopGate = Completer<void>();
      await _stopGate!.future;
    }
    _recording = false;
    return '/tmp/parkiwell-motion-test.mp4';
  }

  @override
  Future<void> cancelRecording() async {
    if (_recording) cancelCalls += 1;
    _recording = false;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    _initialized = false;
  }
}

class _FakeMotionCueSpeaker implements MotionCueSpeaker {
  final List<String> spoken = <String>[];
  bool disposed = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _CannedAnalyzer extends MotionCoachAnalyzer {
  const _CannedAnalyzer(this.result);

  final MotionAnalysisResult result;

  @override
  Future<MotionAnalysisResult> analyze({
    required List<PoseFrame> frames,
    required int width,
    required int height,
    String? runtime,
    MotionExerciseDefinition exercise = seatedArmRaiseExercise,
  }) async => result;
}
