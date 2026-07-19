import 'dart:math' as math;

double estimateSamplingHz(List<num> timestampsMs) {
  if (timestampsMs.length < 2) {
    return 0;
  }
  final List<double> intervals = <double>[];
  for (int index = 1; index < timestampsMs.length; index += 1) {
    final double previous = timestampsMs[index - 1].toDouble();
    final double current = timestampsMs[index].toDouble();
    if (!previous.isFinite || !current.isFinite || current <= previous) {
      throw ArgumentError(
          'timestampsMs must be finite and strictly increasing');
    }
    intervals.add(current - previous);
  }
  return 1000 / median(intervals);
}

List<double> interpolateShortGaps(
  List<double> series, {
  int maxGapFrames = 3,
}) {
  if (maxGapFrames < 0) {
    throw ArgumentError.value(
      maxGapFrames,
      'maxGapFrames',
      'must be non-negative',
    );
  }
  final List<double> output = List<double>.of(series);
  if (maxGapFrames == 0) {
    return output;
  }
  int index = 0;
  while (index < output.length) {
    if (output[index].isFinite) {
      index += 1;
      continue;
    }
    final int start = index;
    while (index < output.length && !output[index].isFinite) {
      index += 1;
    }
    final int end = index;
    final int count = end - start;
    if (count <= maxGapFrames &&
        start > 0 &&
        end < output.length &&
        output[start - 1].isFinite &&
        output[end].isFinite) {
      final double first = output[start - 1];
      final double last = output[end];
      for (int offset = 1; offset <= count; offset += 1) {
        output[start + offset - 1] =
            first + (last - first) * offset / (count + 1);
      }
    }
  }
  return output;
}

List<double> lowpassTimestamped(
  List<double> series,
  List<num> timestampsMs, {
  double cutoffHz = 6,
  int order = 4,
  int maxGapFrames = 3,
  double maximumIntervalRatio = 2.5,
}) {
  if (series.length != timestampsMs.length) {
    throw ArgumentError('series and timestampsMs must have equal length');
  }
  if (!cutoffHz.isFinite || cutoffHz <= 0) {
    throw ArgumentError.value(cutoffHz, 'cutoffHz', 'must be positive');
  }
  if (order != 4) {
    throw UnsupportedError('the parity filter currently supports order 4');
  }
  if (!maximumIntervalRatio.isFinite || maximumIntervalRatio <= 1) {
    throw ArgumentError.value(
      maximumIntervalRatio,
      'maximumIntervalRatio',
      'must be finite and greater than 1',
    );
  }
  final List<double> output = interpolateShortGaps(
    series,
    maxGapFrames: maxGapFrames,
  );
  if (timestampsMs.length < 2) {
    return output;
  }

  final double samplingHz = estimateSamplingHz(timestampsMs);
  final double nominalIntervalMs = 1000 / samplingHz;
  final Set<int> segmentStarts = <int>{};
  for (int index = 1; index < timestampsMs.length; index += 1) {
    final double interval =
        timestampsMs[index].toDouble() - timestampsMs[index - 1].toDouble();
    if (interval > maximumIntervalRatio * nominalIntervalMs) {
      segmentStarts.add(index);
    }
  }

  int index = 0;
  while (index < output.length) {
    while (index < output.length && !output[index].isFinite) {
      index += 1;
    }
    if (index == output.length) {
      break;
    }
    final int start = index;
    index += 1;
    while (index < output.length &&
        output[index].isFinite &&
        !segmentStarts.contains(index)) {
      index += 1;
    }
    final int end = index;
    if (end - start >= 2) {
      final double localHz = estimateSamplingHz(
        timestampsMs.sublist(start, end),
      );
      final double effectiveCutoff = math.min(cutoffHz, 0.4 * localHz);
      final List<double> filtered = lowpassSegmented(
        output.sublist(start, end),
        localHz,
        cutoffHz: effectiveCutoff,
        order: order,
        maxGapFrames: 0,
      );
      output.setRange(start, end, filtered);
    }
  }
  return output;
}

List<double> lowpassSegmented(
  List<double> series,
  double samplingHz, {
  double cutoffHz = 6,
  int order = 4,
  int maxGapFrames = 3,
}) {
  if (!samplingHz.isFinite || samplingHz <= 0) {
    throw ArgumentError.value(samplingHz, 'samplingHz', 'must be positive');
  }
  if (!cutoffHz.isFinite || cutoffHz <= 0 || cutoffHz >= samplingHz / 2) {
    throw ArgumentError.value(
      cutoffHz,
      'cutoffHz',
      'must be positive and below Nyquist',
    );
  }
  if (order != 4) {
    throw UnsupportedError('the parity filter currently supports order 4');
  }
  final List<double> output = interpolateShortGaps(
    series,
    maxGapFrames: maxGapFrames,
  );
  final List<_SosSection> sections = _butterworthOrderFour(
    cutoffHz,
    samplingHz,
  );
  int index = 0;
  while (index < output.length) {
    while (index < output.length && !output[index].isFinite) {
      index += 1;
    }
    final int start = index;
    while (index < output.length && output[index].isFinite) {
      index += 1;
    }
    final int end = index;
    if (end - start > 15) {
      output.setRange(
        start,
        end,
        _sosFiltFilt(sections, output.sublist(start, end)),
      );
    }
  }
  return output;
}

double median(List<double> values) => percentile(values, 50);

double percentile(List<double> values, double percentage) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, 'values', 'must not be empty');
  }
  if (percentage < 0 || percentage > 100) {
    throw ArgumentError.value(
      percentage,
      'percentage',
      'must be between 0 and 100',
    );
  }
  final List<double> sorted = List<double>.of(values)..sort();
  final double position = (sorted.length - 1) * percentage / 100;
  final int lower = position.floor();
  final int upper = position.ceil();
  if (lower == upper) {
    return sorted[lower];
  }
  final double fraction = position - lower;
  return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
}

List<_SosSection> _butterworthOrderFour(
  double cutoffHz,
  double samplingHz,
) {
  final double warped = math.tan(math.pi * cutoffHz / samplingHz);
  const List<double> poleFactors = <double>[
    1.8477590650225735,
    0.7653668647301795,
  ];
  final List<_SosSection> normalized = poleFactors.map((double factor) {
    final double scale = 1 / (1 + factor * warped + warped * warped);
    final double gain = warped * warped * scale;
    return _SosSection(
      b0: gain,
      b1: 2 * gain,
      b2: gain,
      a1: 2 * (warped * warped - 1) * scale,
      a2: (1 - factor * warped + warped * warped) * scale,
    );
  }).toList(growable: false);

  // SciPy's zpk2sos consolidates the section gains into the first numerator.
  final double totalGain = normalized[0].b0 * normalized[1].b0;
  return <_SosSection>[
    _SosSection(
      b0: totalGain,
      b1: 2 * totalGain,
      b2: totalGain,
      a1: normalized[0].a1,
      a2: normalized[0].a2,
    ),
    _SosSection(
      b0: 1,
      b1: 2,
      b2: 1,
      a1: normalized[1].a1,
      a2: normalized[1].a2,
    ),
  ];
}

List<double> _sosFiltFilt(
  List<_SosSection> sections,
  List<double> values,
) {
  const int edge = 15;
  if (values.length <= edge) {
    throw ArgumentError('input must contain more than $edge samples');
  }
  final List<double> extended = <double>[
    for (int index = edge; index >= 1; index -= 1)
      2 * values.first - values[index],
    ...values,
    for (int index = values.length - 2;
        index >= values.length - edge - 1;
        index -= 1)
      2 * values.last - values[index],
  ];
  final List<_FilterState> initial = _sosFilterInitialState(sections);
  final List<double> forward = _sosFilter(
    sections,
    extended,
    initial
        .map(
          (_FilterState state) => state.scaled(extended.first),
        )
        .toList(growable: false),
  );
  final List<double> reversed = forward.reversed.toList(growable: false);
  final List<double> backward = _sosFilter(
    sections,
    reversed,
    initial
        .map(
          (_FilterState state) => state.scaled(reversed.first),
        )
        .toList(growable: false),
  ).reversed.toList(growable: false);
  return backward.sublist(edge, backward.length - edge);
}

List<_FilterState> _sosFilterInitialState(List<_SosSection> sections) {
  double scale = 1;
  final List<_FilterState> result = <_FilterState>[];
  for (final _SosSection section in sections) {
    final double steadyOutput =
        (section.b0 + section.b1 + section.b2) / (1 + section.a1 + section.a2);
    result.add(
      _FilterState(
        (steadyOutput - section.b0) * scale,
        (section.b2 - section.a2 * steadyOutput) * scale,
      ),
    );
    scale *= steadyOutput;
  }
  return result;
}

List<double> _sosFilter(
  List<_SosSection> sections,
  List<double> values,
  List<_FilterState> initial,
) {
  final List<_FilterState> states = initial
      .map((_FilterState state) => _FilterState(state.first, state.second))
      .toList(growable: false);
  final List<double> output = <double>[];
  for (final double input in values) {
    double value = input;
    for (int index = 0; index < sections.length; index += 1) {
      final _SosSection section = sections[index];
      final _FilterState state = states[index];
      final double filtered = section.b0 * value + state.first;
      state.first = section.b1 * value - section.a1 * filtered + state.second;
      state.second = section.b2 * value - section.a2 * filtered;
      value = filtered;
    }
    output.add(value);
  }
  return output;
}

final class _SosSection {
  const _SosSection({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;
}

final class _FilterState {
  _FilterState(this.first, this.second);

  double first;
  double second;

  _FilterState scaled(double multiplier) =>
      _FilterState(first * multiplier, second * multiplier);
}
