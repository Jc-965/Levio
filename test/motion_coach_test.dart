import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_engine/motion_engine.dart';
import 'package:parkiwell/motion_coach/motion_analysis.dart';
import 'package:parkiwell/motion_coach/motion_capture_driver.dart';
import 'package:parkiwell/motion_coach/motion_coach_results_screen.dart';
import 'package:parkiwell/motion_coach/motion_coach_screen.dart';
import 'package:parkiwell/motion_coach/motion_coach_session.dart';
import 'package:parkiwell/motion_coach/motion_pose_bridge.dart';
import 'package:parkiwell/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MotionCoachSession', () {
    test(
      'requires stable framing and uses hysteresis when framing is lost',
      () {
        final MotionCoachSession session = MotionCoachSession();
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
        final MotionCoachSession session = MotionCoachSession();
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
            tempoSeconds: 1.12,
            sideRangeRatio: 0.91,
          ),
        ),
      );

      expect(find.text('Movement captured'), findsOneWidget);
      expect(find.text('Complete raises'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('64°'), findsOneWidget);
      expect(find.text('1.1 sec'), findsOneWidget);
      expect(find.text('91%'), findsOneWidget);
      expect(find.text('Use this result'), findsOneWidget);
    });
  });

  group('MotionCoachScreen', () {
    testWidgets('explains how to recover from denied camera access', (
      WidgetTester tester,
    ) async {
      final _FakeMotionCaptureDriver driver = _FakeMotionCaptureDriver(
        initializeError: CameraException(
          'CameraAccessDenied',
          'Permission denied',
        ),
      );
      await _pumpApp(tester, MotionCoachScreen(driverFactory: () => driver));
      await tester.pumpAndSettle();

      expect(find.text('Camera access is needed'), findsOneWidget);
      expect(find.textContaining('allow Camera access'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(driver.disposeCalls, 1);
    });

    testWidgets(
      'cancels and disposes a recording when the app is backgrounded',
      (WidgetTester tester) async {
        final _FakeMotionCaptureDriver driver = _FakeMotionCaptureDriver();
        await _pumpApp(tester, MotionCoachScreen(driverFactory: () => driver));
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

Future<void> _pumpApp(WidgetTester tester, Widget home) {
  return tester.pumpWidget(
    MaterialApp(theme: AppTheme.lightTheme(), home: home),
  );
}

MotionPoseSample _sample({
  required int timestampMs,
  bool visible = true,
  bool hasPose = true,
}) {
  return MotionPoseSample(
    detection: hasPose
        ? _detection(timestampMs: timestampMs, visible: visible)
        : MotionPoseDetection.empty(timestampMs: timestampMs),
    frameWidth: 480,
    frameHeight: 640,
  );
}

MotionPoseDetection _detection({
  required int timestampMs,
  bool visible = true,
  bool closeEnough = true,
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
  double? tempoSeconds,
  double? sideRangeRatio,
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
    tempoSeconds: tempoSeconds,
    sideRangeRatio: sideRangeRatio,
  );
}

class _FakeMotionCaptureDriver implements MotionCaptureDriver {
  _FakeMotionCaptureDriver({this.initializeError});

  final CameraException? initializeError;
  MotionSampleCallback? _onSample;
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
  Future<void> initialize(MotionSampleCallback onSample) async {
    if (initializeError != null) throw initializeError!;
    _onSample = onSample;
    _initialized = true;
  }

  @override
  Future<void> startRecording() async {
    _recording = true;
  }

  @override
  Future<String> stopRecording() async {
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
