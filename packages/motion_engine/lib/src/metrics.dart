/// Deterministic session metrics for every registered exercise.
///
/// Dart mirror of `motion_coach_cv.metrics`: the analysis is parameterized
/// by an [ExerciseSpec], side features gate or attribute repetitions
/// according to the exercise's laterality, and the emitted
/// `analysis-metrics.v2` document names the signal every aggregate refers
/// to. Cross-language behavior is pinned by the golden parity fixtures.
library;

import 'confidence.dart';
import 'exercise_specs.dart';
import 'filtering.dart';
import 'segmentation.dart';

const String sideLeft = 'left';
const String sideRight = 'right';
const String sideBoth = 'both';

/// Deterministic measurements for one accepted repetition.
final class RepMetrics {
  const RepMetrics({
    required this.boundary,
    required this.side,
    required this.romDeg,
    required this.romPctOfReference,
    required this.leftRomDeg,
    required this.rightRomDeg,
    required this.symmetryLrRomRatio,
  });

  final RepBoundary boundary;
  final String side;
  final double romDeg;
  final double romPctOfReference;
  final double? leftRomDeg;
  final double? rightRomDeg;
  final double? symmetryLrRomRatio;
}

Map<String, Object?> analyzeSession({
  required Map<String, List<double>> features,
  required List<num> timestampsMs,
  required CoverageAssessment coverage,
  required ExerciseSpec spec,
  required int templateVersion,
  required double referenceRomDeg,
  required double referenceTempoS,
  required String engineVersion,
  required Map<String, Object?> provenance,
}) {
  final List<double> primary = _feature(features, spec.primarySignal);
  final List<String> requiredNames = <String>[
    spec.primarySignal,
    ...?spec.sideFeatures,
  ];
  for (final String name in requiredNames) {
    if (_feature(features, name).length != timestampsMs.length) {
      throw ArgumentError('features and timestampsMs must have equal length');
    }
  }
  final double durationS = timestampsMs.length > 1
      ? (timestampsMs.last.toDouble() - timestampsMs.first.toDouble()) / 1000
      : 0;
  final Map<String, Object?> base = <String, Object?>{
    'schema_version': 'analysis-metrics.v2',
    'engine_version': engineVersion,
    'provenance': provenance,
    'exercise': <String, Object?>{
      'exercise_id': spec.exerciseId,
      'template_version': templateVersion,
      'primary_signal': spec.primarySignal,
    },
    'session': <String, Object?>{
      'duration_s': durationS,
      'coverage': coverage.coverage,
      'confidence': coverage.level.serialized,
      'reason_codes': coverage.reasons
          .map((ReasonCode reason) => reason.serialized)
          .toList(growable: false),
    },
    'metrics': <String, Object?>{},
    'flags': <String>[],
  };
  if (coverage.level == ConfidenceLevel.insufficient) {
    final List<String> reasons = coverage.reasons
        .map((ReasonCode reason) => reason.serialized)
        .toList(growable: false);
    base['metrics'] = _abstainedMetrics(reasons);
    base['flags'] = coverage.reasons
        .map(
          (ReasonCode reason) =>
              reason == ReasonCode.lowRequiredLandmarkCoverage
                  ? 'low_coverage'
                  : reason.serialized,
        )
        .toSet()
        .toList(growable: false);
    return base;
  }

  final SegmentationConfig config = SegmentationConfig(
    referenceRomDeg: referenceRomDeg,
    referenceTempoS: referenceTempoS,
  );
  final List<RepBoundary> candidates = segmentReps(
    primary,
    timestampsMs,
    config,
  );
  final List<RepBoundary> repetitions;
  if (spec.laterality == ExerciseLaterality.bilateralSync) {
    final List<String> sideFeatures = spec.sideFeatures!;
    repetitions = selectBilateralReps(
      left: _feature(features, sideFeatures[0]),
      right: _feature(features, sideFeatures[1]),
      timestampsMs: timestampsMs,
      repetitions: candidates,
      referenceRomDeg: referenceRomDeg,
      referenceTempoS: referenceTempoS,
    );
  } else {
    // Alternating and unsided exercises have no two-side synchrony to
    // verify; every segmented repetition is a real movement candidate.
    repetitions = List<RepBoundary>.of(candidates);
  }
  base['metrics'] = _summarizeMetrics(
    features,
    timestampsMs,
    repetitions,
    spec: spec,
    referenceRomDeg: referenceRomDeg,
    sessionCoverage: coverage.coverage,
  );
  if (repetitions.isEmpty) {
    base['flags'] = <String>[
      candidates.isEmpty
          ? ReasonCode.noCompleteReps.serialized
          : ReasonCode.bilateralMovementRequired.serialized,
    ];
  } else if (repetitions.length < candidates.length) {
    base['flags'] = <String>[
      ReasonCode.bilateralMovementRequired.serialized,
    ];
  }
  return base;
}

List<RepBoundary> selectBilateralReps({
  required List<double> left,
  required List<double> right,
  required List<num> timestampsMs,
  required List<RepBoundary> repetitions,
  required double referenceRomDeg,
  required double referenceTempoS,
  double minimumSideRomRatio = 0.10,
  double maximumPeakOffsetRatio = 0.35,
}) {
  final double minimumSideRom = minimumSideRomRatio * referenceRomDeg;
  final double maximumPeakOffsetMs =
      maximumPeakOffsetRatio * referenceTempoS * 1000;
  final List<RepBoundary> accepted = <RepBoundary>[];
  for (final RepBoundary rep in repetitions) {
    final List<double> leftSegment =
        left.sublist(rep.startIndex, rep.endIndex + 1);
    final List<double> rightSegment =
        right.sublist(rep.startIndex, rep.endIndex + 1);
    if (leftSegment.any((double value) => !value.isFinite) ||
        rightSegment.any((double value) => !value.isFinite)) {
      continue;
    }
    final double leftRom = _range(leftSegment);
    final double rightRom = _range(rightSegment);
    if ((leftRom < rightRom ? leftRom : rightRom) < minimumSideRom) {
      continue;
    }
    final int leftPeak = rep.startIndex + _argMax(leftSegment);
    final int rightPeak = rep.startIndex + _argMax(rightSegment);
    if ((timestampsMs[leftPeak].toDouble() - timestampsMs[rightPeak].toDouble())
            .abs() >
        maximumPeakOffsetMs) {
      continue;
    }
    accepted.add(rep);
  }
  return accepted;
}

/// Measure accepted repetitions without ignoring missing side samples.
List<RepMetrics> measureReps(
  Map<String, List<double>> features,
  List<RepBoundary> repetitions, {
  required double referenceRomDeg,
  required List<String>? sideFeatures,
  required ExerciseLaterality laterality,
}) {
  List<double>? left;
  List<double>? right;
  if (sideFeatures != null) {
    left = _feature(features, sideFeatures[0]);
    right = _feature(features, sideFeatures[1]);
  }
  final List<RepMetrics> measurements = <RepMetrics>[];
  for (final RepBoundary rep in repetitions) {
    double? leftRom;
    double? rightRom;
    double? symmetry;
    String side = sideBoth;
    if (left != null && right != null) {
      leftRom = _finiteRange(left.sublist(rep.startIndex, rep.endIndex + 1));
      rightRom = _finiteRange(right.sublist(rep.startIndex, rep.endIndex + 1));
      if (laterality == ExerciseLaterality.alternating) {
        // Mirrors the live engine: the moving side is the one with the
        // larger observed range in this repetition's window.
        if (leftRom != null && rightRom != null) {
          side = leftRom >= rightRom ? sideLeft : sideRight;
        }
      } else if (leftRom != null && rightRom != null) {
        final double larger = leftRom > rightRom ? leftRom : rightRom;
        if (larger > 0) {
          symmetry = (leftRom < rightRom ? leftRom : rightRom) / larger;
        }
      }
    }
    measurements.add(
      RepMetrics(
        boundary: rep,
        side: side,
        romDeg: rep.amplitudeDeg,
        romPctOfReference: 100 * rep.amplitudeDeg / referenceRomDeg,
        leftRomDeg: leftRom,
        rightRomDeg: rightRom,
        symmetryLrRomRatio: symmetry,
      ),
    );
  }
  return measurements;
}

Map<String, Object?> _summarizeMetrics(
  Map<String, List<double>> features,
  List<num> timestampsMs,
  List<RepBoundary> repetitions, {
  required ExerciseSpec spec,
  required double referenceRomDeg,
  required double sessionCoverage,
}) {
  final int count = repetitions.length;
  final bool completeTracking = sessionCoverage == 1;
  final Map<String, Object?> repCount = <String, Object?>{
    'value': count,
    'confidence': completeTracking
        ? ConfidenceLevel.high.name
        : ConfidenceLevel.partial.name,
    'reason_codes': completeTracking
        ? <String>[]
        : <String>[ReasonCode.incompleteSessionTracking.serialized],
  };
  if (repetitions.isEmpty) {
    final List<String> reason = <String>[ReasonCode.noCompleteReps.serialized];
    return <String, Object?>{
      'rep_count': repCount,
      'rom_pct': _emptyAggregate(reason),
      'tempo_s': _emptyAggregate(reason),
      'symmetry_lr_rom_ratio': spec.laterality == ExerciseLaterality.none
          ? _emptyNumber(
              <String>[ReasonCode.symmetryNotApplicable.serialized],
            )
          : _emptyNumber(reason),
      'amplitude_sequence_last_first_ratio': _emptyNumber(reason),
      'repetitions': <Map<String, Object?>>[],
    };
  }

  final List<RepMetrics> measurements = measureReps(
    features,
    repetitions,
    referenceRomDeg: referenceRomDeg,
    sideFeatures: spec.sideFeatures,
    laterality: spec.laterality,
  );
  final List<double> romPercent = <double>[
    for (final RepMetrics measurement in measurements)
      measurement.romPctOfReference,
  ];
  final List<double> tempos = <double>[
    for (final RepMetrics measurement in measurements)
      measurement.boundary.durationS,
  ];
  final Map<String, Object?> rom = _aggregate(romPercent, count);
  final Map<String, Object?> tempo = _aggregate(tempos, count);
  final Map<String, Object?> symmetry =
      _sessionSymmetry(spec, measurements, expectedCount: count);
  final Map<String, Object?> sequence = _amplitudeSequenceSummary(measurements);
  if (!completeTracking) {
    for (final Map<String, Object?> metric in <Map<String, Object?>>[
      rom,
      tempo,
      symmetry,
      sequence,
    ]) {
      _downgradeForIncompleteTracking(metric);
    }
  }
  return <String, Object?>{
    'rep_count': repCount,
    'rom_pct': rom,
    'tempo_s': tempo,
    'symmetry_lr_rom_ratio': symmetry,
    'amplitude_sequence_last_first_ratio': sequence,
    'repetitions': _serializeRepetitions(
      measurements,
      timestampsMs,
      completeTracking: completeTracking,
    ),
  };
}

Map<String, Object?> _sessionSymmetry(
  ExerciseSpec spec,
  List<RepMetrics> measurements, {
  required int expectedCount,
}) {
  if (spec.laterality == ExerciseLaterality.none) {
    // The exercise has no left/right decomposition; an unsided angle cannot
    // say which direction moved less. Abstain with its own code so "not
    // measurable" is distinguishable from "tracking failed".
    return _emptyNumber(<String>[ReasonCode.symmetryNotApplicable.serialized]);
  }
  if (spec.laterality == ExerciseLaterality.alternating) {
    // Symmetry across repetitions: the mean range of left-attributed
    // movements against the mean range of right-attributed ones, exactly
    // like the routine engine's step symmetry.
    final List<double> left = <double>[
      for (final RepMetrics m in measurements)
        if (m.side == sideLeft) m.romDeg,
    ];
    final List<double> right = <double>[
      for (final RepMetrics m in measurements)
        if (m.side == sideRight) m.romDeg,
    ];
    if (left.isEmpty || right.isEmpty) {
      return _emptyNumber(<String>[ReasonCode.noValidSideFeatures.serialized]);
    }
    final double leftMean = _mean(left);
    final double rightMean = _mean(right);
    final double larger = leftMean > rightMean ? leftMean : rightMean;
    if (larger <= 0) {
      return _emptyNumber(<String>[ReasonCode.noValidSideFeatures.serialized]);
    }
    final (ConfidenceLevel level, List<String> reasons) =
        _measurementConfidence(
      left.length + right.length,
      expectedCount,
      sideMetric: true,
    );
    return <String, Object?>{
      'value': (leftMean < rightMean ? leftMean : rightMean) / larger,
      'confidence': level.serialized,
      'reason_codes': reasons,
    };
  }
  final List<double> sideRatios = <double>[
    for (final RepMetrics measurement in measurements)
      if (measurement.symmetryLrRomRatio != null)
        measurement.symmetryLrRomRatio!,
  ];
  return _numberSummary(sideRatios, expectedCount);
}

Map<String, Object?> _amplitudeSequenceSummary(
  List<RepMetrics> measurements,
) {
  if (measurements.length < 3) {
    return _emptyNumber(
      <String>[ReasonCode.insufficientRepsForSequence.serialized],
    );
  }
  final double first = measurements.first.romDeg;
  if (first <= 0) {
    return _emptyNumber(<String>[ReasonCode.noCompleteReps.serialized]);
  }
  return <String, Object?>{
    'value': measurements.last.romDeg / first,
    'confidence': ConfidenceLevel.high.serialized,
    'reason_codes': <String>[],
  };
}

List<Map<String, Object?>> _serializeRepetitions(
  List<RepMetrics> measurements,
  List<num> timestampsMs, {
  required bool completeTracking,
}) {
  if (measurements.isEmpty) {
    return <Map<String, Object?>>[];
  }
  final double originMs = timestampsMs.first.toDouble();
  final String confidence = completeTracking
      ? ConfidenceLevel.high.serialized
      : ConfidenceLevel.partial.serialized;
  final List<String> reasons = completeTracking
      ? <String>[]
      : <String>[ReasonCode.incompleteSessionTracking.serialized];
  return <Map<String, Object?>>[
    for (int index = 0; index < measurements.length; index += 1)
      <String, Object?>{
        'index': index + 1,
        'side': measurements[index].side,
        'start_s':
            (timestampsMs[measurements[index].boundary.startIndex].toDouble() -
                    originMs) /
                1000,
        'peak_s':
            (timestampsMs[measurements[index].boundary.peakIndex].toDouble() -
                    originMs) /
                1000,
        'end_s':
            (timestampsMs[measurements[index].boundary.endIndex].toDouble() -
                    originMs) /
                1000,
        'rom_deg': measurements[index].romDeg,
        'rom_pct_of_reference': measurements[index].romPctOfReference,
        'tempo_s': measurements[index].boundary.durationS,
        'left_rom_deg': measurements[index].leftRomDeg,
        'right_rom_deg': measurements[index].rightRomDeg,
        'symmetry_lr_rom_ratio': measurements[index].symmetryLrRomRatio,
        'confidence': confidence,
        'reason_codes': List<String>.from(reasons),
      },
  ];
}

Map<String, Object?> _aggregate(List<double> values, int expectedCount) {
  final (ConfidenceLevel level, List<String> reasons) =
      _measurementConfidence(values.length, expectedCount);
  return <String, Object?>{
    'median': median(values),
    'iqr': values.length >= 2
        ? <double>[percentile(values, 25), percentile(values, 75)]
        : null,
    'confidence': level.serialized,
    'reason_codes': reasons,
  };
}

Map<String, Object?> _numberSummary(
  List<double> values,
  int expectedCount,
) {
  if (values.isEmpty) {
    return _emptyNumber(
      <String>[ReasonCode.noValidSideFeatures.serialized],
    );
  }
  final (ConfidenceLevel level, List<String> reasons) =
      _measurementConfidence(values.length, expectedCount, sideMetric: true);
  return <String, Object?>{
    'value': median(values),
    'confidence': level.serialized,
    'reason_codes': reasons,
  };
}

(ConfidenceLevel, List<String>) _measurementConfidence(
  int valueCount,
  int expectedCount, {
  bool sideMetric = false,
}) {
  if (valueCount == expectedCount && expectedCount >= 2) {
    return (ConfidenceLevel.high, <String>[]);
  }
  final List<String> reasons = <String>[];
  if (expectedCount == 1) {
    reasons.add(ReasonCode.singleRep.serialized);
  }
  if (sideMetric && valueCount < expectedCount) {
    reasons.add(ReasonCode.partialSideFeatureCoverage.serialized);
  }
  return (ConfidenceLevel.partial, reasons);
}

Map<String, Object?> _abstainedMetrics(List<String> reasons) =>
    <String, Object?>{
      'rep_count': <String, Object?>{
        'value': null,
        'confidence': ConfidenceLevel.insufficient.serialized,
        'reason_codes': reasons,
      },
      'rom_pct': <String, Object?>{
        'median': null,
        'iqr': null,
        'confidence': ConfidenceLevel.insufficient.serialized,
        'reason_codes': reasons,
      },
      'tempo_s': <String, Object?>{
        'median': null,
        'iqr': null,
        'confidence': ConfidenceLevel.insufficient.serialized,
        'reason_codes': reasons,
      },
      'symmetry_lr_rom_ratio': <String, Object?>{
        'value': null,
        'confidence': ConfidenceLevel.insufficient.serialized,
        'reason_codes': reasons,
      },
      'amplitude_sequence_last_first_ratio': <String, Object?>{
        'value': null,
        'confidence': ConfidenceLevel.insufficient.serialized,
        'reason_codes': reasons,
      },
      'repetitions': <Map<String, Object?>>[],
    };

Map<String, Object?> _emptyAggregate(List<String> reasons) => <String, Object?>{
      'median': null,
      'iqr': null,
      'confidence': ConfidenceLevel.insufficient.serialized,
      'reason_codes': reasons,
    };

Map<String, Object?> _emptyNumber(List<String> reasons) => <String, Object?>{
      'value': null,
      'confidence': ConfidenceLevel.insufficient.serialized,
      'reason_codes': reasons,
    };

void _downgradeForIncompleteTracking(Map<String, Object?> metric) {
  if (metric['confidence'] == ConfidenceLevel.insufficient.serialized) {
    return;
  }
  metric['confidence'] = ConfidenceLevel.partial.serialized;
  final List<String> reasons = metric['reason_codes']! as List<String>;
  if (!reasons.contains(ReasonCode.incompleteSessionTracking.serialized)) {
    reasons.add(ReasonCode.incompleteSessionTracking.serialized);
  }
}

List<double> _feature(Map<String, List<double>> features, String name) {
  final List<double>? values = features[name];
  if (values == null) {
    throw ArgumentError('missing required feature: $name');
  }
  return values;
}

double _mean(List<double> values) {
  double total = 0;
  for (final double value in values) {
    total += value;
  }
  return total / values.length;
}

double _range(List<double> values) {
  double minimum = values.first;
  double maximum = values.first;
  for (final double value in values.skip(1)) {
    if (value < minimum) {
      minimum = value;
    }
    if (value > maximum) {
      maximum = value;
    }
  }
  return maximum - minimum;
}

double? _finiteRange(List<double> values) {
  for (final double value in values) {
    if (!value.isFinite) {
      return null;
    }
  }
  return _range(values);
}

int _argMax(List<double> values) {
  int result = 0;
  for (int index = 1; index < values.length; index += 1) {
    if (values[index] > values[result]) {
      result = index;
    }
  }
  return result;
}
