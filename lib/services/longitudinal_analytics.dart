import 'dart:math';

class SymptomObservation {
  const SymptomObservation({
    required this.occurredAt,
    required this.severity,
    required this.symptom,
  });

  final DateTime occurredAt;
  final double severity;
  final String symptom;
}

class MedicationAdherenceEvent {
  const MedicationAdherenceEvent({
    required this.medicationName,
    required this.scheduledAt,
    this.takenAt,
  });

  final String medicationName;
  final DateTime scheduledAt;
  final DateTime? takenAt;

  bool get wasTaken => takenAt != null;
}

class TherapyObservation {
  const TherapyObservation({
    required this.completedAt,
    required this.therapyType,
  });

  final DateTime completedAt;
  final String therapyType;
}

class LongitudinalAnalyticsResult {
  const LongitudinalAnalyticsResult({
    required this.eventCount,
    required this.symptomCount,
    required this.medicationEventCount,
    required this.therapySessionCount,
    required this.medicationAdherenceRate,
    required this.therapyAdherenceRate,
    required this.medicationTimingSeverityDelta,
    required this.therapyDaySeverityDelta,
    required this.medicationSeverityCorrelation,
    required this.therapySeverityCorrelation,
    required this.dailySeverityTrend,
    required this.summary,
  });

  final int eventCount;
  final int symptomCount;
  final int medicationEventCount;
  final int therapySessionCount;
  final double medicationAdherenceRate;
  final double therapyAdherenceRate;
  final double medicationTimingSeverityDelta;
  final double therapyDaySeverityDelta;
  final double medicationSeverityCorrelation;
  final double therapySeverityCorrelation;
  final double dailySeverityTrend;
  final String summary;

  bool get hasMeaningfulData => symptomCount >= 3;
}

class LongitudinalAnalytics {
  const LongitudinalAnalytics({
    this.medicationWindow = const Duration(hours: 4),
  });

  final Duration medicationWindow;

  LongitudinalAnalyticsResult analyze({
    required Iterable<SymptomObservation> symptoms,
    required Iterable<MedicationAdherenceEvent> medicationEvents,
    required Iterable<TherapyObservation> therapySessions,
    int weeklyTherapyGoal = 0,
    Map<int, int> expectedDosesByWeekday = const <int, int>{},
  }) {
    final symptomList = symptoms.toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final medicationList = medicationEvents.toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final therapyList = therapySessions.toList()
      ..sort((a, b) => a.completedAt.compareTo(b.completedAt));

    final takenMedicationTimes =
        medicationList
            .where((event) => event.wasTaken)
            .map((event) => event.takenAt!)
            .toList()
          ..sort();

    var afterMedicationSeverity = 0.0;
    var afterMedicationCount = 0;
    var baselineSeverity = 0.0;
    var baselineCount = 0;
    var medicationIndex = -1;

    for (final symptom in symptomList) {
      while (medicationIndex + 1 < takenMedicationTimes.length &&
          !takenMedicationTimes[medicationIndex + 1].isAfter(
            symptom.occurredAt,
          )) {
        medicationIndex += 1;
      }

      final isWithinMedicationWindow =
          medicationIndex >= 0 &&
          symptom.occurredAt.difference(
                takenMedicationTimes[medicationIndex],
              ) <=
              medicationWindow;
      if (isWithinMedicationWindow) {
        afterMedicationSeverity += symptom.severity;
        afterMedicationCount += 1;
      } else {
        baselineSeverity += symptom.severity;
        baselineCount += 1;
      }
    }

    final daily = <int, _DailySignals>{};
    for (final symptom in symptomList) {
      daily.putIfAbsent(_dayKey(symptom.occurredAt), _DailySignals.new)
        ..severityTotal += symptom.severity
        ..symptomCount += 1;
    }
    final hasExpectations = expectedDosesByWeekday.values.any(
      (count) => count > 0,
    );
    for (final medication in medicationList) {
      final signals = daily.putIfAbsent(
        _dayKey(medication.scheduledAt),
        _DailySignals.new,
      );
      if (!hasExpectations) signals.medicationsScheduled += 1;
      if (medication.wasTaken) signals.medicationsTaken += 1;
    }
    if (hasExpectations) {
      // The schedule, not the event log, defines how many doses each day
      // was supposed to contain; the app only records taken doses, so
      // counting events as "scheduled" would make adherence always 100%.
      for (final entry in daily.entries) {
        final weekday = DateTime.fromMillisecondsSinceEpoch(
          entry.key,
          isUtc: true,
        ).weekday;
        entry.value.medicationsScheduled = expectedDosesByWeekday[weekday] ?? 0;
      }
    }
    for (final therapy in therapyList) {
      final signals = daily.putIfAbsent(
        _dayKey(therapy.completedAt),
        _DailySignals.new,
      );
      signals.therapySessions += 1;
    }

    final sortedDays = daily.keys.toList()..sort();
    final adherenceSamples = <_Pair>[];
    final trendSamples = <_Pair>[];
    var therapyDaySeverity = 0.0;
    var therapyDayCount = 0;
    var nonTherapyDaySeverity = 0.0;
    var nonTherapyDayCount = 0;

    for (var index = 0; index < sortedDays.length; index += 1) {
      final signals = daily[sortedDays[index]]!;
      if (signals.symptomCount == 0) continue;
      final averageSeverity = signals.averageSeverity;
      trendSamples.add(_Pair(index.toDouble(), averageSeverity));

      if (signals.medicationsScheduled > 0) {
        adherenceSamples.add(_Pair(signals.adherence, averageSeverity));
      }
      if (signals.therapySessions > 0) {
        therapyDaySeverity += averageSeverity;
        therapyDayCount += 1;
      } else {
        nonTherapyDaySeverity += averageSeverity;
        nonTherapyDayCount += 1;
      }
    }

    final takenCount = medicationList.where((event) => event.wasTaken).length;
    double adherenceRate;
    if (hasExpectations && sortedDays.isNotEmpty) {
      var expectedTotal = 0;
      final firstDay = DateTime.fromMillisecondsSinceEpoch(
        sortedDays.first,
        isUtc: true,
      );
      final lastDay = DateTime.fromMillisecondsSinceEpoch(
        sortedDays.last,
        isUtc: true,
      );
      for (
        var day = firstDay;
        !day.isAfter(lastDay);
        day = DateTime.utc(day.year, day.month, day.day + 1)
      ) {
        expectedTotal += expectedDosesByWeekday[day.weekday] ?? 0;
      }
      adherenceRate = expectedTotal == 0
          ? 0.0
          : (takenCount / expectedTotal).clamp(0.0, 1.0);
    } else {
      adherenceRate = medicationList.isEmpty
          ? 0.0
          : takenCount / medicationList.length;
    }
    final medicationTimingDelta =
        baselineCount == 0 || afterMedicationCount == 0
        ? 0.0
        : (baselineSeverity / baselineCount) -
              (afterMedicationSeverity / afterMedicationCount);
    final therapyDayDelta = therapyDayCount == 0 || nonTherapyDayCount == 0
        ? 0.0
        : (nonTherapyDaySeverity / nonTherapyDayCount) -
              (therapyDaySeverity / therapyDayCount);
    final weeklySignals = <int, _WeeklySignals>{};
    for (final symptom in symptomList) {
      weeklySignals
          .putIfAbsent(_weekKey(symptom.occurredAt), _WeeklySignals.new)
          .addSeverity(symptom.severity);
    }
    for (final therapy in therapyList) {
      weeklySignals
              .putIfAbsent(_weekKey(therapy.completedAt), _WeeklySignals.new)
              .therapySessions +=
          1;
    }
    final therapyAdherenceSamples = <_Pair>[];
    var adherenceTotal = 0.0;
    var adherenceWeekCount = 0;
    if (weeklyTherapyGoal > 0) {
      for (final signals in weeklySignals.values) {
        final adherence = (signals.therapySessions / weeklyTherapyGoal).clamp(
          0.0,
          1.0,
        );
        adherenceTotal += adherence;
        adherenceWeekCount += 1;
        if (signals.symptomCount > 0) {
          therapyAdherenceSamples.add(
            _Pair(adherence, signals.averageSeverity),
          );
        }
      }
    }

    return LongitudinalAnalyticsResult(
      eventCount:
          symptomList.length + medicationList.length + therapyList.length,
      symptomCount: symptomList.length,
      medicationEventCount: medicationList.length,
      therapySessionCount: therapyList.length,
      medicationAdherenceRate: adherenceRate,
      therapyAdherenceRate: adherenceWeekCount == 0
          ? 0
          : adherenceTotal / adherenceWeekCount,
      medicationTimingSeverityDelta: medicationTimingDelta,
      therapyDaySeverityDelta: therapyDayDelta,
      medicationSeverityCorrelation: _pearson(adherenceSamples),
      therapySeverityCorrelation: _pearson(therapyAdherenceSamples),
      dailySeverityTrend: _linearSlope(trendSamples),
      summary: _summary(
        symptomCount: symptomList.length,
        medicationTimingDelta: medicationTimingDelta,
        medicationSamples: afterMedicationCount + baselineCount,
        therapyDayDelta: therapyDayDelta,
        therapyDayCount: therapyDayCount,
      ),
    );
  }

  static int _dayKey(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day).millisecondsSinceEpoch;
  }

  static int _weekKey(DateTime value) {
    final utc = value.toUtc();
    final day = DateTime.utc(utc.year, utc.month, utc.day);
    return day
        .subtract(Duration(days: day.weekday - DateTime.monday))
        .millisecondsSinceEpoch;
  }

  static double _pearson(List<_Pair> samples) {
    if (samples.length < 2) return 0.0;
    final meanX =
        samples.fold<double>(0, (sum, pair) => sum + pair.x) / samples.length;
    final meanY =
        samples.fold<double>(0, (sum, pair) => sum + pair.y) / samples.length;

    var covariance = 0.0;
    var varianceX = 0.0;
    var varianceY = 0.0;
    for (final sample in samples) {
      final dx = sample.x - meanX;
      final dy = sample.y - meanY;
      covariance += dx * dy;
      varianceX += dx * dx;
      varianceY += dy * dy;
    }

    final denominator = sqrt(varianceX * varianceY);
    return denominator == 0 ? 0.0 : covariance / denominator;
  }

  static double _linearSlope(List<_Pair> samples) {
    if (samples.length < 2) return 0.0;
    final meanX =
        samples.fold<double>(0, (sum, pair) => sum + pair.x) / samples.length;
    final meanY =
        samples.fold<double>(0, (sum, pair) => sum + pair.y) / samples.length;

    var numerator = 0.0;
    var denominator = 0.0;
    for (final sample in samples) {
      final dx = sample.x - meanX;
      numerator += dx * (sample.y - meanY);
      denominator += dx * dx;
    }
    return denominator == 0 ? 0.0 : numerator / denominator;
  }

  static String _summary({
    required int symptomCount,
    required double medicationTimingDelta,
    required int medicationSamples,
    required double therapyDayDelta,
    required int therapyDayCount,
  }) {
    if (symptomCount < 3) {
      return 'Log more symptoms to reveal personal patterns.';
    }
    if (medicationSamples >= 6 && medicationTimingDelta.abs() >= 0.1) {
      final direction = medicationTimingDelta > 0 ? 'lower' : 'higher';
      return 'Logged severity was ${medicationTimingDelta.abs().toStringAsFixed(1)} points $direction within four hours of a recorded dose.';
    }
    if (therapyDayCount >= 2 && therapyDayDelta.abs() >= 0.1) {
      final direction = therapyDayDelta > 0 ? 'lower' : 'higher';
      return 'Logged severity was ${therapyDayDelta.abs().toStringAsFixed(1)} points $direction on therapy days.';
    }
    return 'Your recent symptom pattern is stable across recorded activities.';
  }
}

class _DailySignals {
  double severityTotal = 0;
  int symptomCount = 0;
  int medicationsScheduled = 0;
  int medicationsTaken = 0;
  int therapySessions = 0;

  double get averageSeverity =>
      symptomCount == 0 ? 0 : severityTotal / symptomCount;
  double get adherence =>
      medicationsScheduled == 0 ? 0 : medicationsTaken / medicationsScheduled;
}

class _Pair {
  const _Pair(this.x, this.y);

  final double x;
  final double y;
}

class _WeeklySignals {
  double severityTotal = 0;
  int symptomCount = 0;
  int therapySessions = 0;

  void addSeverity(double severity) {
    severityTotal += severity;
    symptomCount += 1;
  }

  double get averageSeverity =>
      symptomCount == 0 ? 0 : severityTotal / symptomCount;
}
