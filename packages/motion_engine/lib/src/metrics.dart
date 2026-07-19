import 'confidence.dart';
import 'filtering.dart';
import 'segmentation.dart';

Map<String, Object?> analyzeArmRaiseSession({
  required Map<String, List<double>> features,
  required List<num> timestampsMs,
  required CoverageAssessment coverage,
  required String exerciseId,
  required int templateVersion,
  required double referenceRomDeg,
  required double referenceTempoS,
  required String engineVersion,
  required Map<String, Object?> provenance,
}) {
  final List<double> primary = _feature(features, 'arm_elevation_mean');
  final List<double> left = _feature(features, 'arm_elevation_l');
  final List<double> right = _feature(features, 'arm_elevation_r');
  for (final List<double> values in <List<double>>[primary, left, right]) {
    if (values.length != timestampsMs.length) {
      throw ArgumentError('features and timestampsMs must have equal length');
    }
  }
  final double durationS = timestampsMs.length > 1
      ? (timestampsMs.last.toDouble() - timestampsMs.first.toDouble()) / 1000
      : 0;
  final Map<String, Object?> base = <String, Object?>{
    'schema_version': 'analysis-metrics.v1',
    'engine_version': engineVersion,
    'provenance': provenance,
    'exercise': <String, Object?>{
      'exercise_id': exerciseId,
      'template_version': templateVersion,
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

  final ArmRaiseSegmentationConfig config = ArmRaiseSegmentationConfig(
    referenceRomDeg: referenceRomDeg,
    referenceTempoS: referenceTempoS,
  );
  final List<RepBoundary> candidates = segmentArmRaiseReps(
    primary,
    timestampsMs,
    config,
  );
  final List<RepBoundary> repetitions = selectBilateralArmRaiseReps(
    left: left,
    right: right,
    timestampsMs: timestampsMs,
    repetitions: candidates,
    referenceRomDeg: referenceRomDeg,
    referenceTempoS: referenceTempoS,
  );
  base['metrics'] = _summarizeMetrics(
    left,
    right,
    repetitions,
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

List<RepBoundary> selectBilateralArmRaiseReps({
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

Map<String, Object?> _summarizeMetrics(
  List<double> left,
  List<double> right,
  List<RepBoundary> repetitions, {
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
    return <String, Object?>{
      'rep_count': repCount,
      'arm_elevation_rom_pct':
          _emptyAggregate(<String>[ReasonCode.noCompleteReps.serialized]),
      'tempo_s':
          _emptyAggregate(<String>[ReasonCode.noCompleteReps.serialized]),
      'symmetry_lr_rom_ratio':
          _emptyNumber(<String>[ReasonCode.noCompleteReps.serialized]),
    };
  }

  final List<double> romPercent = <double>[];
  final List<double> tempos = <double>[];
  final List<double> sideRatios = <double>[];
  for (final RepBoundary rep in repetitions) {
    romPercent.add(100 * rep.amplitudeDeg / referenceRomDeg);
    tempos.add(rep.durationS);
    final List<double> leftSegment =
        left.sublist(rep.startIndex, rep.endIndex + 1);
    final List<double> rightSegment =
        right.sublist(rep.startIndex, rep.endIndex + 1);
    if (leftSegment.every((double value) => value.isFinite) &&
        rightSegment.every((double value) => value.isFinite)) {
      final double leftRom = _range(leftSegment);
      final double rightRom = _range(rightSegment);
      final double larger = leftRom > rightRom ? leftRom : rightRom;
      if (larger > 0) {
        sideRatios.add((leftRom < rightRom ? leftRom : rightRom) / larger);
      }
    }
  }
  final Map<String, Object?> rom = _aggregate(romPercent, count);
  final Map<String, Object?> tempo = _aggregate(tempos, count);
  final Map<String, Object?> symmetry = _numberSummary(sideRatios, count);
  if (!completeTracking) {
    for (final Map<String, Object?> metric in <Map<String, Object?>>[
      rom,
      tempo,
      symmetry
    ]) {
      _downgradeForIncompleteTracking(metric);
    }
  }
  return <String, Object?>{
    'rep_count': repCount,
    'arm_elevation_rom_pct': rom,
    'tempo_s': tempo,
    'symmetry_lr_rom_ratio': symmetry,
  };
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
      'arm_elevation_rom_pct': <String, Object?>{
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

int _argMax(List<double> values) {
  int result = 0;
  for (int index = 1; index < values.length; index += 1) {
    if (values[index] > values[result]) {
      result = index;
    }
  }
  return result;
}
