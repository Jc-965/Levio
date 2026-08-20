import 'confidence.dart';

final class RepBoundary {
  const RepBoundary({
    required this.startIndex,
    required this.peakIndex,
    required this.endIndex,
    required this.startTimestampMs,
    required this.peakTimestampMs,
    required this.endTimestampMs,
    required this.amplitudeDeg,
    required this.durationS,
    this.confidence = ConfidenceLevel.high,
    this.reasonCodes = const <ReasonCode>[],
  });

  final int startIndex;
  final int peakIndex;
  final int endIndex;
  final double startTimestampMs;
  final double peakTimestampMs;
  final double endTimestampMs;
  final double amplitudeDeg;
  final double durationS;
  final ConfidenceLevel confidence;
  final List<ReasonCode> reasonCodes;
}

final class SegmentationConfig {
  SegmentationConfig({
    required this.referenceRomDeg,
    required this.referenceTempoS,
    this.minimumRomRatio = 0.25,
    this.activationRatio = 0.15,
    this.reversalRatio = 0.08,
    this.returnRatio = 0.20,
    this.minimumDurationRatio = 0.35,
    this.maximumDurationRatio = 6,
  }) {
    if (!referenceRomDeg.isFinite || referenceRomDeg <= 0) {
      throw ArgumentError.value(referenceRomDeg, 'referenceRomDeg');
    }
    if (!referenceTempoS.isFinite || referenceTempoS <= 0) {
      throw ArgumentError.value(referenceTempoS, 'referenceTempoS');
    }
  }

  final double referenceRomDeg;
  final double referenceTempoS;
  final double minimumRomRatio;
  final double activationRatio;
  final double reversalRatio;
  final double returnRatio;
  final double minimumDurationRatio;
  final double maximumDurationRatio;
}

List<RepBoundary> segmentReps(
  List<double> signal,
  List<num> timestampsMs,
  SegmentationConfig config,
) {
  if (signal.length != timestampsMs.length) {
    throw ArgumentError('signal and timestampsMs must have equal length');
  }
  for (final num timestamp in timestampsMs) {
    // NaN defeats ordering comparisons below (every comparison is false),
    // so finiteness must be validated explicitly, as the Python engine does.
    if (!timestamp.toDouble().isFinite) {
      throw ArgumentError('timestampsMs must contain only finite values');
    }
  }
  for (int index = 1; index < timestampsMs.length; index += 1) {
    if (timestampsMs[index].toDouble() <= timestampsMs[index - 1].toDouble()) {
      throw ArgumentError('timestampsMs must be strictly increasing');
    }
  }
  final List<RepBoundary> result = <RepBoundary>[];
  int index = 0;
  while (index < signal.length) {
    while (index < signal.length && !signal[index].isFinite) {
      index += 1;
    }
    final int start = index;
    while (index < signal.length && signal[index].isFinite) {
      index += 1;
    }
    result.addAll(
      _segmentFiniteRun(signal, timestampsMs, start, index, config),
    );
  }
  return result;
}

List<RepBoundary> _segmentFiniteRun(
  List<double> values,
  List<num> timestamps,
  int runStart,
  int runEnd,
  SegmentationConfig config,
) {
  if (runEnd - runStart < 3) {
    return <RepBoundary>[];
  }
  final double activation = config.activationRatio * config.referenceRomDeg;
  final double reversal = config.reversalRatio * config.referenceRomDeg;
  final double minimumRom = config.minimumRomRatio * config.referenceRomDeg;
  final double minimumDuration =
      config.minimumDurationRatio * config.referenceTempoS;
  final double maximumDuration =
      config.maximumDurationRatio * config.referenceTempoS;
  _SegmentState state = _SegmentState.seekingStart;
  int valley = runStart;
  int start = runStart;
  int peak = runStart;
  final List<RepBoundary> repetitions = <RepBoundary>[];

  for (int index = runStart + 1; index < runEnd; index += 1) {
    final double value = values[index];
    if (state == _SegmentState.seekingStart) {
      if (value <= values[valley]) {
        valley = index;
      } else if (value - values[valley] >= activation) {
        // The boundary start is the activation-crossing sample, not the
        // valley index: on a flat rest plateau, sub-degree filter ripple
        // decides where the minimum lands, and a tempo measured from that
        // index would differ between implementations (and runs) by up to
        // the whole rest period. The valley VALUE stays authoritative for
        // amplitude.
        state = _SegmentState.raising;
        start = index;
        peak = index;
      }
      continue;
    }
    if (state == _SegmentState.raising) {
      if (value >= values[peak]) {
        peak = index;
        continue;
      }
      if (values[peak] - value < reversal) {
        continue;
      }
      if (values[peak] - values[valley] < minimumRom) {
        state = _SegmentState.seekingStart;
        valley = index;
        continue;
      }
      state = _SegmentState.lowering;
      continue;
    }

    // Lowering: the repetition ends at the first sample back within the
    // return band, mirroring the activation-crossing start rule.
    final double observedRom = values[peak] - values[valley];
    final double returnLimit =
        values[valley] + config.returnRatio * observedRom;
    if (value > returnLimit) {
      continue;
    }
    final RepBoundary? repetition = _buildBoundary(
      values,
      timestamps,
      valley,
      start,
      peak,
      index,
      minimumRom,
      minimumDuration,
      maximumDuration,
    );
    if (repetition != null) {
      repetitions.add(repetition);
    }
    state = _SegmentState.seekingStart;
    valley = index;
  }

  return repetitions;
}

RepBoundary? _buildBoundary(
  List<double> values,
  List<num> timestamps,
  int valley,
  int start,
  int peak,
  int end,
  double minimumRom,
  double minimumDuration,
  double maximumDuration,
) {
  if (!(start <= peak && peak < end)) {
    return null;
  }
  final double amplitude = values[peak] -
      (values[valley] < values[end] ? values[valley] : values[end]);
  final double duration =
      (timestamps[end].toDouble() - timestamps[start].toDouble()) / 1000;
  if (amplitude < minimumRom ||
      duration < minimumDuration ||
      duration > maximumDuration) {
    return null;
  }
  return RepBoundary(
    startIndex: start,
    peakIndex: peak,
    endIndex: end,
    startTimestampMs: timestamps[start].toDouble(),
    peakTimestampMs: timestamps[peak].toDouble(),
    endTimestampMs: timestamps[end].toDouble(),
    amplitudeDeg: amplitude,
    durationS: duration,
  );
}

enum _SegmentState { seekingStart, raising, lowering }
