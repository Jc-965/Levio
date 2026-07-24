import 'dart:math' as math;

import 'features.dart';
import 'models.dart';

enum LiveArmRaisePhase { idle, raising, lowering }

enum LiveCueKind {
  comfortableRange(
    'comfortable_range',
    'If comfortable, make the next raise a little larger.',
    true,
  ),
  steadyPace(
    'steady_pace',
    'Nice work. Keep a steady, comfortable pace.',
    true,
  ),
  niceMovement('nice_movement', 'Nice movement.', false);

  const LiveCueKind(this.code, this.text, this.isCorrective);

  final String code;
  final String text;
  final bool isCorrective;
}

final class LiveArmRaiseConfig {
  const LiveArmRaiseConfig({
    required this.referenceRomDeg,
    required this.referenceTempoS,
    this.visibilityThreshold = 0.6,
    this.minimumRomRatio = 0.25,
    this.raiseStartRatio = 0.20,
    this.returnRatio = 0.12,
    this.amplitudeCueRatio = 0.70,
    this.minimumTempoRatio = 0.65,
    this.maximumTempoRatio = 1.60,
    this.globalCueCooldown = const Duration(seconds: 8),
    this.sameCueCooldown = const Duration(seconds: 30),
    this.minimumRepsBetweenCorrections = 3,
  })  : assert(referenceRomDeg > 0),
        assert(referenceTempoS > 0),
        assert(visibilityThreshold >= 0 && visibilityThreshold <= 1),
        assert(minimumRomRatio > 0),
        assert(raiseStartRatio > returnRatio),
        assert(returnRatio > 0),
        assert(amplitudeCueRatio > minimumRomRatio),
        assert(minimumTempoRatio > 0),
        assert(maximumTempoRatio > minimumTempoRatio),
        assert(minimumRepsBetweenCorrections > 0);

  final double referenceRomDeg;
  final double referenceTempoS;
  final double visibilityThreshold;
  final double minimumRomRatio;
  final double raiseStartRatio;
  final double returnRatio;
  final double amplitudeCueRatio;
  final double minimumTempoRatio;
  final double maximumTempoRatio;
  final Duration globalCueCooldown;
  final Duration sameCueCooldown;
  final int minimumRepsBetweenCorrections;
}

final class LiveRepObservation {
  const LiveRepObservation({
    required this.index,
    required this.startTimestampMs,
    required this.peakTimestampMs,
    required this.endTimestampMs,
    required this.romDeg,
    required this.tempoS,
    required this.leftRomDeg,
    required this.rightRomDeg,
    required this.sideRangeRatio,
  });

  final int index;
  final int startTimestampMs;
  final int peakTimestampMs;
  final int endTimestampMs;
  final double romDeg;
  final double tempoS;
  final double leftRomDeg;
  final double rightRomDeg;
  final double sideRangeRatio;
}

final class LiveCoachDecision {
  const LiveCoachDecision({required this.repetition, required this.cue});

  final LiveRepObservation repetition;
  final LiveCueKind? cue;
}

/// Causal, camera-independent live coaching for bilateral arm raises.
///
/// The engine emits at most one allowlisted cue at a completed rep boundary.
/// Missing or ambiguous poses immediately invalidate the active repetition.
final class LiveArmRaiseCoach {
  LiveArmRaiseCoach(this.config);

  final LiveArmRaiseConfig config;
  final CausalOneEuroFilter _meanFilter = CausalOneEuroFilter();
  final CausalOneEuroFilter _leftFilter = CausalOneEuroFilter();
  final CausalOneEuroFilter _rightFilter = CausalOneEuroFilter();
  final Map<LiveCueKind, int> _lastCueTimestampMs = <LiveCueKind, int>{};

  LiveArmRaisePhase _phase = LiveArmRaisePhase.idle;
  int? _lastTimestampMs;
  int? _previousFilteredTimestampMs;
  double? _previousFilteredMean;
  double? _baseline;
  int? _repStartTimestampMs;
  int? _repPeakTimestampMs;
  double _repMinimum = double.infinity;
  double _repPeak = -double.infinity;
  double _leftMinimum = double.infinity;
  double _leftMaximum = -double.infinity;
  double _rightMinimum = double.infinity;
  double _rightMaximum = -double.infinity;
  int _completedReps = 0;
  int? _lastGlobalCueTimestampMs;
  int? _lastCorrectionRep;
  bool _correctionNeedsPositive = false;

  LiveArmRaisePhase get phase => _phase;
  int get completedReps => _completedReps;

  LiveCoachDecision? addFrame(PoseFrame frame) {
    final int? lastTimestamp = _lastTimestampMs;
    if (lastTimestamp != null && frame.timestampMs <= lastTimestamp) {
      throw ArgumentError('live frame timestamps must be strictly increasing');
    }
    _lastTimestampMs = frame.timestampMs;
    final (double, double)? elevations = _armElevations(frame);
    if (elevations == null) {
      _invalidateTracking();
      return null;
    }

    final double left = _leftFilter.filter(elevations.$1, frame.timestampMs);
    final double right = _rightFilter.filter(elevations.$2, frame.timestampMs);
    final double mean = _meanFilter.filter(
      (elevations.$1 + elevations.$2) / 2,
      frame.timestampMs,
    );
    final double velocity = _velocity(mean, frame.timestampMs);
    _baseline ??= mean;

    switch (_phase) {
      case LiveArmRaisePhase.idle:
        _updateIdleBaseline(mean);
        if (mean - _baseline! >=
                config.raiseStartRatio * config.referenceRomDeg &&
            velocity > 0) {
          _beginRepetition(mean, left, right, frame.timestampMs);
        }
      case LiveArmRaisePhase.raising:
        _updateRepetition(mean, left, right, frame.timestampMs);
        final double amplitude = _repPeak - _repMinimum;
        if (velocity < -3 &&
            amplitude >= config.minimumRomRatio * config.referenceRomDeg) {
          _phase = LiveArmRaisePhase.lowering;
        }
      case LiveArmRaisePhase.lowering:
        _updateRepetition(mean, left, right, frame.timestampMs);
        if (mean - _baseline! <= config.returnRatio * config.referenceRomDeg) {
          return _completeRepetition(frame.timestampMs);
        }
    }
    return null;
  }

  void reset() {
    _phase = LiveArmRaisePhase.idle;
    _lastTimestampMs = null;
    _previousFilteredTimestampMs = null;
    _previousFilteredMean = null;
    _baseline = null;
    _completedReps = 0;
    _lastGlobalCueTimestampMs = null;
    _lastCueTimestampMs.clear();
    _lastCorrectionRep = null;
    _correctionNeedsPositive = false;
    _clearRepetition();
    _meanFilter.reset();
    _leftFilter.reset();
    _rightFilter.reset();
  }

  (double, double)? _armElevations(PoseFrame frame) {
    final List<PoseLandmark>? points = frame.landmarks;
    if (points == null || points.length != 33) {
      return null;
    }
    const List<String> required = <String>[
      'left_shoulder',
      'right_shoulder',
      'left_wrist',
      'right_wrist',
      'left_hip',
      'right_hip',
    ];
    for (final String name in required) {
      final PoseLandmark landmark = points[landmarkIndex[name]!];
      if (landmark.position?.isFinite != true ||
          !landmark.visibility.isFinite ||
          landmark.visibility < config.visibilityThreshold) {
        return null;
      }
    }
    final double left = jointAngle(
      points[landmarkIndex['left_hip']!].position,
      points[landmarkIndex['left_shoulder']!].position,
      points[landmarkIndex['left_wrist']!].position,
    );
    final double right = jointAngle(
      points[landmarkIndex['right_hip']!].position,
      points[landmarkIndex['right_shoulder']!].position,
      points[landmarkIndex['right_wrist']!].position,
    );
    return left.isFinite && right.isFinite ? (left, right) : null;
  }

  double _velocity(double mean, int timestampMs) {
    final double? previous = _previousFilteredMean;
    final int? previousTimestamp = _previousFilteredTimestampMs;
    _previousFilteredMean = mean;
    _previousFilteredTimestampMs = timestampMs;
    if (previous == null || previousTimestamp == null) {
      return 0;
    }
    return (mean - previous) / ((timestampMs - previousTimestamp) / 1000);
  }

  void _updateIdleBaseline(double mean) {
    if (mean <= _baseline! + config.returnRatio * config.referenceRomDeg) {
      _baseline = 0.98 * _baseline! + 0.02 * mean;
    }
  }

  void _beginRepetition(
    double mean,
    double left,
    double right,
    int timestampMs,
  ) {
    _phase = LiveArmRaisePhase.raising;
    _repStartTimestampMs = timestampMs;
    _repPeakTimestampMs = timestampMs;
    _repMinimum = math.min(_baseline!, mean);
    _repPeak = mean;
    _leftMinimum = left;
    _leftMaximum = left;
    _rightMinimum = right;
    _rightMaximum = right;
  }

  void _updateRepetition(
    double mean,
    double left,
    double right,
    int timestampMs,
  ) {
    _repMinimum = math.min(_repMinimum, mean);
    if (mean > _repPeak) {
      _repPeak = mean;
      _repPeakTimestampMs = timestampMs;
    }
    _leftMinimum = math.min(_leftMinimum, left);
    _leftMaximum = math.max(_leftMaximum, left);
    _rightMinimum = math.min(_rightMinimum, right);
    _rightMaximum = math.max(_rightMaximum, right);
  }

  LiveCoachDecision? _completeRepetition(int timestampMs) {
    final int? startTimestampMs = _repStartTimestampMs;
    final int? peakTimestampMs = _repPeakTimestampMs;
    final double rom = _repPeak - _repMinimum;
    final double tempoS =
        startTimestampMs == null ? 0 : (timestampMs - startTimestampMs) / 1000;
    final bool accepted = startTimestampMs != null &&
        peakTimestampMs != null &&
        rom >= config.minimumRomRatio * config.referenceRomDeg &&
        tempoS >= 0.35 * config.referenceTempoS &&
        tempoS <= 4 * config.referenceTempoS;
    _phase = LiveArmRaisePhase.idle;
    _baseline =
        _baseline == null ? _repMinimum : math.min(_baseline!, _repMinimum);
    if (!accepted) {
      _clearRepetition();
      return null;
    }

    _completedReps += 1;
    final double leftRom = _leftMaximum - _leftMinimum;
    final double rightRom = _rightMaximum - _rightMinimum;
    final double larger = math.max(leftRom, rightRom);
    final LiveRepObservation repetition = LiveRepObservation(
      index: _completedReps,
      startTimestampMs: startTimestampMs,
      peakTimestampMs: peakTimestampMs,
      endTimestampMs: timestampMs,
      romDeg: rom,
      tempoS: tempoS,
      leftRomDeg: leftRom,
      rightRomDeg: rightRom,
      sideRangeRatio: larger > 0 ? math.min(leftRom, rightRom) / larger : 0,
    );
    final LiveCueKind? cue = _selectCue(repetition);
    _clearRepetition();
    return LiveCoachDecision(repetition: repetition, cue: cue);
  }

  LiveCueKind? _selectCue(LiveRepObservation repetition) {
    LiveCueKind candidate;
    if (repetition.romDeg < config.amplitudeCueRatio * config.referenceRomDeg) {
      candidate = LiveCueKind.comfortableRange;
    } else if (repetition.tempoS <
            config.minimumTempoRatio * config.referenceTempoS ||
        repetition.tempoS > config.maximumTempoRatio * config.referenceTempoS) {
      candidate = LiveCueKind.steadyPace;
    } else {
      candidate = LiveCueKind.niceMovement;
    }

    if (candidate.isCorrective) {
      final int? lastCorrectionRep = _lastCorrectionRep;
      if (_correctionNeedsPositive ||
          (lastCorrectionRep != null &&
              repetition.index - lastCorrectionRep <
                  config.minimumRepsBetweenCorrections)) {
        candidate = LiveCueKind.niceMovement;
      }
    }
    if (!_cooldownAllows(candidate, repetition.endTimestampMs)) {
      return null;
    }

    _lastGlobalCueTimestampMs = repetition.endTimestampMs;
    _lastCueTimestampMs[candidate] = repetition.endTimestampMs;
    if (candidate.isCorrective) {
      _correctionNeedsPositive = true;
      _lastCorrectionRep = repetition.index;
    } else {
      _correctionNeedsPositive = false;
    }
    return candidate;
  }

  bool _cooldownAllows(LiveCueKind cue, int timestampMs) {
    final int? global = _lastGlobalCueTimestampMs;
    if (global != null &&
        timestampMs - global < config.globalCueCooldown.inMilliseconds) {
      return false;
    }
    final int? sameCue = _lastCueTimestampMs[cue];
    return sameCue == null ||
        timestampMs - sameCue >= config.sameCueCooldown.inMilliseconds;
  }

  void _invalidateTracking() {
    _phase = LiveArmRaisePhase.idle;
    _baseline = null;
    _previousFilteredTimestampMs = null;
    _previousFilteredMean = null;
    _clearRepetition();
    _meanFilter.reset();
    _leftFilter.reset();
    _rightFilter.reset();
  }

  void _clearRepetition() {
    _repStartTimestampMs = null;
    _repPeakTimestampMs = null;
    _repMinimum = double.infinity;
    _repPeak = -double.infinity;
    _leftMinimum = double.infinity;
    _leftMaximum = -double.infinity;
    _rightMinimum = double.infinity;
    _rightMaximum = -double.infinity;
  }
}

final class CausalOneEuroFilter {
  CausalOneEuroFilter({
    this.minimumCutoffHz = 1.0,
    this.speedCoefficient = 0.007,
    this.derivativeCutoffHz = 1.0,
  })  : assert(minimumCutoffHz > 0),
        assert(speedCoefficient >= 0),
        assert(derivativeCutoffHz > 0);

  final double minimumCutoffHz;
  final double speedCoefficient;
  final double derivativeCutoffHz;
  int? _lastTimestampMs;
  double? _lastRaw;
  double? _filteredValue;
  double _filteredDerivative = 0;

  double filter(double value, int timestampMs) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    final int? previousTimestamp = _lastTimestampMs;
    final double? previousRaw = _lastRaw;
    if (previousTimestamp == null || previousRaw == null) {
      _lastTimestampMs = timestampMs;
      _lastRaw = value;
      _filteredValue = value;
      return value;
    }
    if (timestampMs <= previousTimestamp) {
      throw ArgumentError('filter timestamps must be strictly increasing');
    }
    final double elapsedS = (timestampMs - previousTimestamp) / 1000;
    final double derivative = (value - previousRaw) / elapsedS;
    _filteredDerivative = _lowPass(
      _filteredDerivative,
      derivative,
      _alpha(derivativeCutoffHz, elapsedS),
    );
    final double cutoff =
        minimumCutoffHz + speedCoefficient * _filteredDerivative.abs();
    _filteredValue = _lowPass(
      _filteredValue!,
      value,
      _alpha(cutoff, elapsedS),
    );
    _lastTimestampMs = timestampMs;
    _lastRaw = value;
    return _filteredValue!;
  }

  void reset() {
    _lastTimestampMs = null;
    _lastRaw = null;
    _filteredValue = null;
    _filteredDerivative = 0;
  }

  double _alpha(double cutoffHz, double elapsedS) {
    final double timeConstant = 1 / (2 * math.pi * cutoffHz);
    return 1 / (1 + timeConstant / elapsedS);
  }

  double _lowPass(double previous, double current, double alpha) =>
      alpha * current + (1 - alpha) * previous;
}
