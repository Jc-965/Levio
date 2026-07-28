/// Causal multi-exercise live coaching: phase machine, per-rep scoring,
/// allowlisted cues.
///
/// Dart port of `motion_coach_cv.live` (the Python reference engine).
/// Everything is causal and deterministic: frames go in with strictly
/// increasing timestamps, decisions come out at completed-repetition
/// boundaries only, and every user-visible string comes from the exercise's
/// allowlisted cue texts. Cross-language behavior is pinned by the
/// live-coach parity fixture.
library;

import 'dart:math' as math;

import 'exercise_specs.dart';
import 'features.dart';
import 'live_coach.dart' show CausalOneEuroFilter;
import 'models.dart';

const double rangeWeight = 0.40;
const double tempoWeight = 0.25;
const double smoothnessWeight = 0.20;
const double symmetryWeight = 0.15;
const double correctionThreshold = 60.0;

enum LiveExercisePhase { idle, moving, returning }

enum ExerciseCueKind {
  amplitude('amplitude'),
  tempo('tempo'),
  smoothness('smoothness'),
  positive('positive');

  const ExerciseCueKind(this.code);

  final String code;
}

final class LiveExerciseCue {
  const LiveExerciseCue({
    required this.kind,
    required this.text,
    required this.isCorrective,
  });

  final ExerciseCueKind kind;
  final String text;
  final bool isCorrective;
}

final class ExerciseRepScore {
  const ExerciseRepScore({
    required this.overall,
    required this.rangeScore,
    required this.tempoScore,
    required this.smoothnessScore,
    required this.symmetryScore,
  });

  final double overall;
  final double rangeScore;
  final double tempoScore;
  final double smoothnessScore;
  final double? symmetryScore;
}

final class LiveExerciseRepetition {
  const LiveExerciseRepetition({
    required this.index,
    required this.startTimestampMs,
    required this.peakTimestampMs,
    required this.endTimestampMs,
    required this.romDeg,
    required this.romPctOfReference,
    required this.tempoS,
    required this.extraReversals,
    required this.leftRomDeg,
    required this.rightRomDeg,
    required this.side,
    required this.score,
  });

  final int index;
  final int startTimestampMs;
  final int peakTimestampMs;
  final int endTimestampMs;
  final double romDeg;
  final double romPctOfReference;
  final double tempoS;
  final int extraReversals;
  final double? leftRomDeg;
  final double? rightRomDeg;
  final String side;
  final ExerciseRepScore score;
}

final class LiveExerciseDecision {
  const LiveExerciseDecision({required this.repetition, required this.cue});

  final LiveExerciseRepetition repetition;
  final LiveExerciseCue? cue;
}

final class LiveExerciseCoachConfig {
  const LiveExerciseCoachConfig({
    required this.referenceRomDeg,
    required this.referenceTempoS,
    this.visibilityThreshold = 0.6,
    this.minimumRomRatio = 0.25,
    this.startRatio = defaultStartRatio,
    this.returnRatio = defaultReturnRatio,
    this.reversalVelocityDegS = 3.0,
    this.minimumTempoRatio = 0.35,
    this.maximumTempoRatio = 4.0,
    this.globalCueCooldownMs = 8000,
    this.sameCueCooldownMs = 30000,
    this.minimumRepsBetweenCorrections = 3,
  })  : assert(referenceRomDeg > 0),
        assert(referenceTempoS > 0),
        assert(visibilityThreshold >= 0 && visibilityThreshold <= 1),
        assert(startRatio > returnRatio),
        assert(maximumTempoRatio > minimumTempoRatio);

  /// Derive thresholds from a raw `exercise-template.v1` JSON document.
  ///
  /// The live engine times repetitions from the start-threshold crossing to
  /// the return-threshold crossing, not valley-to-valley; the reference
  /// tempo is therefore measured from the template's own `reference_series`
  /// with those same thresholds — identical to the Python
  /// `LiveCoachConfig.from_template`.
  factory LiveExerciseCoachConfig.fromTemplateJson(
    Map<String, Object?> template,
  ) {
    final String primary = template['primary_signal']! as String;
    final Map<String, Object?> rep = template['rep']! as Map<String, Object?>;
    final Map<String, Object?> rom = (rep['rom_deg']!
        as Map<String, Object?>)[primary]! as Map<String, Object?>;
    final Map<String, Object?> tempo = rep['tempo_s']! as Map<String, Object?>;
    final Map<String, Object?> referenceSeries =
        template['reference_series']! as Map<String, Object?>;
    final List<double> series = ((referenceSeries['features']!
            as Map<String, Object?>)[primary]! as List<Object?>)
        .map((Object? value) => (value! as num).toDouble())
        .toList(growable: false);
    final double samplingHz =
        (referenceSeries['sampling_hz']! as num).toDouble();
    final Map<String, Object?> policy =
        template['confidence_policy']! as Map<String, Object?>;

    double referenceTempoS = (tempo['median']! as num).toDouble();
    final double minimum = series.reduce(math.min);
    final double maximum = series.reduce(math.max);
    final double span = maximum - minimum;
    if (span > 0 && samplingHz > 0) {
      final double startLevel = minimum + defaultStartRatio * span;
      final double returnLevel = minimum + defaultReturnRatio * span;
      int? startIndex;
      for (int index = 0; index < series.length; index += 1) {
        if (series[index] >= startLevel) {
          startIndex = index;
          break;
        }
      }
      int? endIndex;
      for (int index = series.length - 1; index >= 0; index -= 1) {
        if (series[index] >= returnLevel) {
          endIndex = index;
          break;
        }
      }
      if (startIndex != null && endIndex != null && endIndex > startIndex) {
        referenceTempoS = (endIndex - startIndex) / samplingHz;
      }
    }
    return LiveExerciseCoachConfig(
      referenceRomDeg: (rom['median']! as num).toDouble(),
      referenceTempoS: referenceTempoS,
      visibilityThreshold: (policy['visibility_threshold']! as num).toDouble(),
    );
  }

  static const double defaultStartRatio = 0.20;
  static const double defaultReturnRatio = 0.12;

  final double referenceRomDeg;
  final double referenceTempoS;
  final double visibilityThreshold;
  final double minimumRomRatio;
  final double startRatio;
  final double returnRatio;
  final double reversalVelocityDegS;
  final double minimumTempoRatio;
  final double maximumTempoRatio;
  final int globalCueCooldownMs;
  final int sameCueCooldownMs;
  final int minimumRepsBetweenCorrections;
}

double scoreRange(double romRatio) {
  if (!romRatio.isFinite || romRatio <= 0) {
    return 0.0;
  }
  if (romRatio < 0.9) {
    return _clamp(100.0 * (romRatio - 0.25) / (0.9 - 0.25));
  }
  if (romRatio <= 1.5) {
    return 100.0;
  }
  // Far past the reference range reads as ballistic, not better.
  return _clamp(100.0 - 60.0 * (romRatio - 1.5), minimum: 70.0);
}

double scoreTempo(double tempoRatio) {
  if (!tempoRatio.isFinite || tempoRatio <= 0) {
    return 0.0;
  }
  if (tempoRatio < 0.8) {
    return _clamp(100.0 * (tempoRatio - 0.35) / (0.8 - 0.35));
  }
  if (tempoRatio <= 1.25) {
    return 100.0;
  }
  return _clamp(100.0 * (3.0 - tempoRatio) / (3.0 - 1.25));
}

double scoreSmoothness(int extraReversals) =>
    _clamp(100.0 - 25.0 * math.max(extraReversals, 0));

double scoreSymmetry(double sideRatio) {
  if (!sideRatio.isFinite || sideRatio <= 0.4) {
    return 0.0;
  }
  if (sideRatio >= 0.85) {
    return 100.0;
  }
  return _clamp(100.0 * (sideRatio - 0.4) / (0.85 - 0.4));
}

double combineScores(
  double rangeScore,
  double tempoScore,
  double smoothnessScore,
  double? symmetryScore,
) {
  double weighted = rangeWeight * rangeScore +
      tempoWeight * tempoScore +
      smoothnessWeight * smoothnessScore;
  double weight = rangeWeight + tempoWeight + smoothnessWeight;
  if (symmetryScore != null) {
    weighted += symmetryWeight * symmetryScore;
    weight += symmetryWeight;
  }
  return _clamp(weighted / weight);
}

/// Causal per-exercise coach: counts, scores, and cues completed reps.
final class LiveExerciseCoach {
  LiveExerciseCoach(this.spec, this.config)
      : _requiredIndices = spec.requiredLandmarks
            .map((String name) => landmarkIndex[name]!)
            .toList(growable: false);

  final ExerciseSpec spec;
  final LiveExerciseCoachConfig config;
  final List<int> _requiredIndices;
  final CausalOneEuroFilter _primaryFilter = CausalOneEuroFilter();
  final CausalOneEuroFilter _leftFilter = CausalOneEuroFilter();
  final CausalOneEuroFilter _rightFilter = CausalOneEuroFilter();
  final Map<ExerciseCueKind, int> _lastCueTimestampMs =
      <ExerciseCueKind, int>{};

  LiveExercisePhase _phase = LiveExercisePhase.idle;
  int? _lastTimestampMs;
  double? _previousFiltered;
  int? _previousFilteredTimestampMs;
  double? _previousVelocity;
  double? _baseline;
  final List<LiveExerciseRepetition> _completed = <LiveExerciseRepetition>[];
  int _totalFrames = 0;
  int _validFrames = 0;
  int? _lastGlobalCueTimestampMs;
  int? _lastCorrectionRep;
  bool _correctionNeedsPositive = false;
  int? _repStartTimestampMs;
  int? _repPeakTimestampMs;
  double _repMinimum = double.infinity;
  double _repPeak = double.negativeInfinity;
  double _leftMinimum = double.infinity;
  double _leftMaximum = double.negativeInfinity;
  double _rightMinimum = double.infinity;
  double _rightMaximum = double.negativeInfinity;
  int _reversalCount = 0;

  LiveExercisePhase get phase => _phase;
  List<LiveExerciseRepetition> get completedRepetitions =>
      List<LiveExerciseRepetition>.unmodifiable(_completed);
  int get totalFrames => _totalFrames;
  double get coverage => _totalFrames == 0 ? 0.0 : _validFrames / _totalFrames;

  void reset() {
    _phase = LiveExercisePhase.idle;
    _lastTimestampMs = null;
    _previousFiltered = null;
    _previousFilteredTimestampMs = null;
    _previousVelocity = null;
    _baseline = null;
    _completed.clear();
    _totalFrames = 0;
    _validFrames = 0;
    _lastGlobalCueTimestampMs = null;
    _lastCueTimestampMs.clear();
    _lastCorrectionRep = null;
    _correctionNeedsPositive = false;
    _clearRepetition();
    _primaryFilter.reset();
    _leftFilter.reset();
    _rightFilter.reset();
  }

  /// Process one camera frame of 33 world landmarks.
  LiveExerciseDecision? addFrame(PoseFrame frame) {
    _checkTimestamp(frame.timestampMs);
    _totalFrames += 1;
    final List<PoseLandmark>? points = frame.landmarks;
    if (points == null || points.length != 33) {
      _invalidateTracking();
      return null;
    }
    for (final int index in _requiredIndices) {
      final PoseLandmark landmark = points[index];
      if (landmark.position?.isFinite != true ||
          !landmark.visibility.isFinite ||
          landmark.visibility < config.visibilityThreshold) {
        _invalidateTracking();
        return null;
      }
    }
    final Map<String, double> features = computeFrameFeatures(points, spec);
    return _advance(features, frame.timestampMs);
  }

  /// Process one frame of precomputed features (used by tests and parity).
  LiveExerciseDecision? addFeatures(
    Map<String, double> features,
    int timestampMs,
  ) {
    _checkTimestamp(timestampMs);
    _totalFrames += 1;
    return _advance(features, timestampMs);
  }

  LiveExerciseDecision? _advance(
    Map<String, double> features,
    int timestampMs,
  ) {
    final double primary = features[spec.primarySignal] ?? double.nan;
    double left = double.nan;
    double right = double.nan;
    if (spec.sideFeatures != null) {
      left = features[spec.sideFeatures![0]] ?? double.nan;
      right = features[spec.sideFeatures![1]] ?? double.nan;
    }
    if (!primary.isFinite ||
        (spec.sideFeatures != null && !(left.isFinite && right.isFinite))) {
      _invalidateTracking();
      return null;
    }
    _validFrames += 1;

    final double mean = _primaryFilter.filter(primary, timestampMs);
    if (spec.sideFeatures != null) {
      left = _leftFilter.filter(left, timestampMs);
      right = _rightFilter.filter(right, timestampMs);
    }
    final double velocity = _velocity(mean, timestampMs);
    _baseline ??= mean;

    LiveExerciseDecision? decision;
    final double rom = config.referenceRomDeg;
    switch (_phase) {
      case LiveExercisePhase.idle:
        _updateIdleBaseline(mean);
        if (mean - _baseline! >= config.startRatio * rom && velocity > 0) {
          _beginRepetition(mean, left, right, timestampMs);
        }
      case LiveExercisePhase.moving:
        _updateRepetition(mean, left, right, velocity, timestampMs);
        final double amplitude = _repPeak - _repMinimum;
        if (velocity < -config.reversalVelocityDegS &&
            amplitude >= config.minimumRomRatio * rom) {
          _phase = LiveExercisePhase.returning;
        } else if (mean - _baseline! <= config.returnRatio * rom &&
            amplitude < config.minimumRomRatio * rom) {
          // A false start returned to baseline: abandon it quietly so it
          // cannot swallow the next real repetition.
          _abandonRepetition();
        } else if (_repetitionOverdue(timestampMs)) {
          _abandonRepetition();
        }
      case LiveExercisePhase.returning:
        _updateRepetition(mean, left, right, velocity, timestampMs);
        if (mean - _baseline! <= config.returnRatio * rom) {
          decision = _completeRepetition(timestampMs);
        } else if (_repetitionOverdue(timestampMs)) {
          _abandonRepetition();
        }
    }
    return decision;
  }

  bool _repetitionOverdue(int timestampMs) {
    final int? start = _repStartTimestampMs;
    if (start == null) {
      return false;
    }
    final double limitMs =
        config.maximumTempoRatio * config.referenceTempoS * 1000;
    return timestampMs - start > limitMs;
  }

  void _abandonRepetition() {
    _phase = LiveExercisePhase.idle;
    if (_baseline != null && _repMinimum.isFinite) {
      _baseline = math.min(_baseline!, _repMinimum);
    }
    _clearRepetition();
  }

  void _checkTimestamp(int timestampMs) {
    final int? last = _lastTimestampMs;
    if (last != null && timestampMs <= last) {
      throw ArgumentError('live frame timestamps must be strictly increasing');
    }
    _lastTimestampMs = timestampMs;
  }

  double _velocity(double mean, int timestampMs) {
    final double? previous = _previousFiltered;
    final int? previousTimestamp = _previousFilteredTimestampMs;
    _previousFiltered = mean;
    _previousFilteredTimestampMs = timestampMs;
    if (previous == null || previousTimestamp == null) {
      return 0.0;
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
    _phase = LiveExercisePhase.moving;
    _repStartTimestampMs = timestampMs;
    _repPeakTimestampMs = timestampMs;
    _repMinimum = math.min(_baseline!, mean);
    _repPeak = mean;
    _leftMinimum = left;
    _leftMaximum = left;
    _rightMinimum = right;
    _rightMaximum = right;
    _reversalCount = 0;
    _previousVelocity = null;
  }

  void _updateRepetition(
    double mean,
    double left,
    double right,
    double velocity,
    int timestampMs,
  ) {
    _repMinimum = math.min(_repMinimum, mean);
    if (mean > _repPeak) {
      _repPeak = mean;
      _repPeakTimestampMs = timestampMs;
    }
    if (left.isFinite) {
      _leftMinimum = math.min(_leftMinimum, left);
      _leftMaximum = math.max(_leftMaximum, left);
    }
    if (right.isFinite) {
      _rightMinimum = math.min(_rightMinimum, right);
      _rightMaximum = math.max(_rightMaximum, right);
    }
    final double? previousVelocity = _previousVelocity;
    if (previousVelocity != null &&
        velocity.abs() > 0.5 &&
        previousVelocity.abs() > 0.5 &&
        (velocity > 0) != (previousVelocity > 0)) {
      _reversalCount += 1;
    }
    if (velocity.abs() > 0.5) {
      _previousVelocity = velocity;
    }
  }

  LiveExerciseDecision? _completeRepetition(int timestampMs) {
    final int? start = _repStartTimestampMs;
    final int? peak = _repPeakTimestampMs;
    final double rom = _repPeak - _repMinimum;
    final double tempoS = start == null ? 0.0 : (timestampMs - start) / 1000;
    final bool accepted = start != null &&
        peak != null &&
        rom >= config.minimumRomRatio * config.referenceRomDeg &&
        tempoS >= config.minimumTempoRatio * config.referenceTempoS &&
        tempoS <= config.maximumTempoRatio * config.referenceTempoS;
    _phase = LiveExercisePhase.idle;
    _baseline =
        _baseline == null ? _repMinimum : math.min(_baseline!, _repMinimum);
    if (!accepted) {
      _clearRepetition();
      return null;
    }

    double? leftRom;
    double? rightRom;
    double? symmetry;
    String side = 'both';
    if (spec.sideFeatures != null) {
      leftRom = _finiteRom(_leftMinimum, _leftMaximum);
      rightRom = _finiteRom(_rightMinimum, _rightMaximum);
      if (spec.laterality == ExerciseLaterality.alternating) {
        if (leftRom != null && rightRom != null) {
          side = leftRom >= rightRom ? 'left' : 'right';
        }
      } else if (leftRom != null && rightRom != null) {
        final double larger = math.max(leftRom, rightRom);
        symmetry = larger > 0 ? math.min(leftRom, rightRom) / larger : 0.0;
      }
    }

    final int extraReversals = math.max(0, _reversalCount - 1);
    final double romRatio = rom / config.referenceRomDeg;
    final double tempoRatio = tempoS / config.referenceTempoS;
    final double rangeScore = scoreRange(romRatio);
    final double tempoScore = scoreTempo(tempoRatio);
    final double smoothnessScore = scoreSmoothness(extraReversals);
    final double? symmetryScore =
        symmetry != null ? scoreSymmetry(symmetry) : null;
    final ExerciseRepScore score = ExerciseRepScore(
      overall:
          combineScores(rangeScore, tempoScore, smoothnessScore, symmetryScore),
      rangeScore: rangeScore,
      tempoScore: tempoScore,
      smoothnessScore: smoothnessScore,
      symmetryScore: symmetryScore,
    );
    final LiveExerciseRepetition repetition = LiveExerciseRepetition(
      index: _completed.length + 1,
      startTimestampMs: start,
      peakTimestampMs: peak,
      endTimestampMs: timestampMs,
      romDeg: rom,
      romPctOfReference: 100.0 * romRatio,
      tempoS: tempoS,
      extraReversals: extraReversals,
      leftRomDeg: leftRom,
      rightRomDeg: rightRom,
      side: side,
      score: score,
    );
    _completed.add(repetition);
    final LiveExerciseCue? cue = _selectCue(repetition);
    _clearRepetition();
    return LiveExerciseDecision(repetition: repetition, cue: cue);
  }

  LiveExerciseCue? _selectCue(LiveExerciseRepetition repetition) {
    final ExerciseRepScore score = repetition.score;
    final ExerciseCueTexts cues = spec.cues;
    LiveExerciseCue candidate = LiveExerciseCue(
      kind: ExerciseCueKind.positive,
      text: cues.positive,
      isCorrective: false,
    );
    if (score.rangeScore < correctionThreshold) {
      candidate = LiveExerciseCue(
        kind: ExerciseCueKind.amplitude,
        text: cues.amplitude,
        isCorrective: true,
      );
    } else if (score.tempoScore < correctionThreshold) {
      candidate = LiveExerciseCue(
        kind: ExerciseCueKind.tempo,
        text: cues.tempo,
        isCorrective: true,
      );
    } else if (score.smoothnessScore < correctionThreshold) {
      candidate = LiveExerciseCue(
        kind: ExerciseCueKind.smoothness,
        text: cues.smoothness,
        isCorrective: true,
      );
    }

    if (candidate.isCorrective) {
      final int? lastCorrection = _lastCorrectionRep;
      if (_correctionNeedsPositive ||
          (lastCorrection != null &&
              repetition.index - lastCorrection <
                  config.minimumRepsBetweenCorrections)) {
        candidate = LiveExerciseCue(
          kind: ExerciseCueKind.positive,
          text: cues.positive,
          isCorrective: false,
        );
      }
    }
    if (!_cooldownAllows(candidate.kind, repetition.endTimestampMs)) {
      return null;
    }

    _lastGlobalCueTimestampMs = repetition.endTimestampMs;
    _lastCueTimestampMs[candidate.kind] = repetition.endTimestampMs;
    if (candidate.isCorrective) {
      _correctionNeedsPositive = true;
      _lastCorrectionRep = repetition.index;
    } else {
      _correctionNeedsPositive = false;
    }
    return candidate;
  }

  bool _cooldownAllows(ExerciseCueKind kind, int timestampMs) {
    final int? lastGlobal = _lastGlobalCueTimestampMs;
    if (lastGlobal != null &&
        timestampMs - lastGlobal < config.globalCueCooldownMs) {
      return false;
    }
    final int? lastSame = _lastCueTimestampMs[kind];
    return lastSame == null ||
        timestampMs - lastSame >= config.sameCueCooldownMs;
  }

  void _invalidateTracking() {
    _phase = LiveExercisePhase.idle;
    _baseline = null;
    _previousFiltered = null;
    _previousFilteredTimestampMs = null;
    _clearRepetition();
    _primaryFilter.reset();
    _leftFilter.reset();
    _rightFilter.reset();
  }

  void _clearRepetition() {
    _repStartTimestampMs = null;
    _repPeakTimestampMs = null;
    _repMinimum = double.infinity;
    _repPeak = double.negativeInfinity;
    _leftMinimum = double.infinity;
    _leftMaximum = double.negativeInfinity;
    _rightMinimum = double.infinity;
    _rightMaximum = double.negativeInfinity;
    _reversalCount = 0;
    _previousVelocity = null;
  }

  static double? _finiteRom(double minimum, double maximum) {
    if (minimum.isFinite && maximum.isFinite) {
      return maximum - minimum;
    }
    return null;
  }
}

double _clamp(double value, {double minimum = 0.0, double maximum = 100.0}) =>
    math.max(minimum, math.min(maximum, value));
