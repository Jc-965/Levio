import 'dart:math' as math;

import 'package:motion_engine/motion_engine.dart';
import 'package:test/test.dart';

void main() {
  test('One Euro filter is causal and resettable', () {
    final CausalOneEuroFilter filter = CausalOneEuroFilter();

    expect(filter.filter(0, 0), 0);
    final double next = filter.filter(10, 100);
    expect(next, greaterThan(0));
    expect(next, lessThan(10));
    filter.reset();
    expect(filter.filter(10, 200), 10);
  });

  test('emits one allowlisted cue at a completed rep boundary', () {
    final LiveArmRaiseCoach coach = _coach();

    final List<LiveCoachDecision> decisions = _feedRepetition(
      coach,
      amplitude: 40,
      startTimestampMs: 0,
    );

    expect(decisions, hasLength(1));
    expect(decisions.single.repetition.index, 1);
    expect(decisions.single.repetition.romDeg, greaterThan(20));
    expect(decisions.single.cue, LiveCueKind.comfortableRange);
    expect(
      LiveCueKind.values.map((LiveCueKind cue) => cue.text),
      everyElement(isNotEmpty),
    );
  });

  test('enforces the global cue cooldown while still counting reps', () {
    final LiveArmRaiseCoach coach = _coach();
    final List<LiveCoachDecision> first = _feedRepetition(
      coach,
      amplitude: 40,
      startTimestampMs: 0,
    );
    final List<LiveCoachDecision> second = _feedRepetition(
      coach,
      amplitude: 40,
      startTimestampMs: 2200,
    );

    expect(first.single.cue, isNotNull);
    expect(second.single.repetition.index, 2);
    expect(second.single.cue, isNull);
    expect(coach.completedReps, 2);
  });

  test('missing tracking invalidates an active repetition', () {
    final LiveArmRaiseCoach coach = _coach();
    int timestampMs = 0;
    for (final double angle in <double>[10, 20, 35, 50, 65]) {
      coach.addFrame(_frame(angle, timestampMs));
      timestampMs += 100;
    }
    coach.addFrame(PoseFrame(timestampMs: timestampMs, landmarks: null));
    timestampMs += 100;
    final List<LiveCoachDecision> decisions = <LiveCoachDecision>[];
    for (final double angle in <double>[50, 35, 20, 10, 10, 10, 10]) {
      final LiveCoachDecision? decision = coach.addFrame(
        _frame(angle, timestampMs),
      );
      if (decision != null) decisions.add(decision);
      timestampMs += 100;
    }

    expect(decisions, isEmpty);
    expect(coach.completedReps, 0);
    expect(coach.phase, LiveArmRaisePhase.idle);
  });

  test('a small false start does not swallow the next repetition', () {
    final LiveArmRaiseCoach coach = _coach();
    // A hesitation between the raise-start (20%) and minimum-ROM (25%)
    // thresholds of the 80-degree reference, then two full repetitions.
    final List<LiveCoachDecision> falseStart = _feedRepetition(
      coach,
      amplitude: 18,
      startTimestampMs: 0,
    );
    final List<LiveCoachDecision> first = _feedRepetition(
      coach,
      amplitude: 70,
      startTimestampMs: 2200,
    );
    final List<LiveCoachDecision> second = _feedRepetition(
      coach,
      amplitude: 70,
      startTimestampMs: 4400,
    );

    expect(falseStart, isEmpty);
    expect(first, hasLength(1));
    expect(second, hasLength(1));
    expect(coach.completedReps, 2);
  });

  test('decision path remains far below the 100 ms budget', () {
    final LiveArmRaiseCoach coach = _coach();
    final Stopwatch stopwatch = Stopwatch()..start();
    int timestampMs = 0;
    for (int rep = 0; rep < 50; rep += 1) {
      _feedRepetition(
        coach,
        amplitude: 80,
        startTimestampMs: timestampMs,
      );
      timestampMs += 2200;
    }
    stopwatch.stop();

    expect(coach.completedReps, 50);
    expect(stopwatch.elapsedMilliseconds, lessThan(100));
  });
}

LiveArmRaiseCoach _coach() => LiveArmRaiseCoach(
      const LiveArmRaiseConfig(referenceRomDeg: 80, referenceTempoS: 1),
    );

List<LiveCoachDecision> _feedRepetition(
  LiveArmRaiseCoach coach, {
  required double amplitude,
  required int startTimestampMs,
}) {
  const List<double> phase = <double>[
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
  final List<LiveCoachDecision> decisions = <LiveCoachDecision>[];
  int timestampMs = startTimestampMs;
  for (final double value in phase) {
    final LiveCoachDecision? decision = coach.addFrame(
      _frame(10 + amplitude * value, timestampMs),
    );
    if (decision != null) decisions.add(decision);
    timestampMs += 100;
  }
  return decisions;
}

PoseFrame _frame(double angleDegrees, int timestampMs) {
  final List<PoseLandmark> points = List<PoseLandmark>.generate(
    33,
    (_) => const PoseLandmark(position: null, visibility: 0),
  );
  const Vector3 leftShoulder = Vector3(-0.2, -0.5, 0);
  const Vector3 rightShoulder = Vector3(0.2, -0.5, 0);
  final double radians = angleDegrees * math.pi / 180;
  points[landmarkIndex['left_hip']!] = const PoseLandmark(
    position: Vector3(-0.2, 0, 0),
    visibility: 1,
  );
  points[landmarkIndex['right_hip']!] = const PoseLandmark(
    position: Vector3(0.2, 0, 0),
    visibility: 1,
  );
  points[landmarkIndex['left_shoulder']!] = const PoseLandmark(
    position: leftShoulder,
    visibility: 1,
  );
  points[landmarkIndex['right_shoulder']!] = const PoseLandmark(
    position: rightShoulder,
    visibility: 1,
  );
  points[landmarkIndex['left_wrist']!] = PoseLandmark(
    position: leftShoulder + Vector3(-math.sin(radians), math.cos(radians), 0),
    visibility: 1,
  );
  points[landmarkIndex['right_wrist']!] = PoseLandmark(
    position: rightShoulder + Vector3(math.sin(radians), math.cos(radians), 0),
    visibility: 1,
  );
  return PoseFrame(timestampMs: timestampMs, landmarks: points);
}
