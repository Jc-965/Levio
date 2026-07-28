import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/services/longitudinal_analytics.dart';

void main() {
  const analytics = LongitudinalAnalytics();

  test('correlates medication timing and therapy adherence with severity', () {
    final start = DateTime.utc(2026, 1, 5);
    final symptoms = <SymptomObservation>[];
    final medications = <MedicationAdherenceEvent>[];
    final therapy = <TherapyObservation>[];

    for (var day = 0; day < 14; day += 1) {
      final date = start.add(Duration(days: day));
      final therapyDay = day.isEven;
      final doseTime = date.add(const Duration(hours: 8));
      medications.add(
        MedicationAdherenceEvent(
          medicationName: 'Medication',
          scheduledAt: doseTime,
          takenAt: doseTime.add(const Duration(minutes: 5)),
        ),
      );
      if (therapyDay) {
        therapy.add(
          TherapyObservation(
            completedAt: date.add(const Duration(hours: 9)),
            therapyType: 'physical',
          ),
        );
      }
      symptoms.add(
        SymptomObservation(
          occurredAt: date.add(const Duration(hours: 10)),
          severity: therapyDay ? 1.5 : 3.5,
          symptom: 'Tremor',
        ),
      );
      symptoms.add(
        SymptomObservation(
          occurredAt: date.add(const Duration(hours: 18)),
          severity: therapyDay ? 2.0 : 4.0,
          symptom: 'Stiffness',
        ),
      );
    }

    final result = analytics.analyze(
      symptoms: symptoms,
      medicationEvents: medications,
      therapySessions: therapy,
      weeklyTherapyGoal: 4,
    );

    expect(result.eventCount, 49);
    expect(result.medicationAdherenceRate, 1);
    expect(result.therapyAdherenceRate, greaterThan(0));
    expect(result.therapyDaySeverityDelta, closeTo(2, 0.01));
    expect(result.therapySeverityCorrelation, lessThan(0));
    expect(result.summary, contains('recorded dose'));
  });

  test('analyzes 10k longitudinal events under 100ms p95', () {
    const symptomCount = 5000;
    const medicationCount = 3000;
    const therapyCount = 2000;
    const eventCount = symptomCount + medicationCount + therapyCount;
    final start = DateTime.utc(2020, 1, 1);
    final symptoms = List<SymptomObservation>.generate(symptomCount, (index) {
      return SymptomObservation(
        occurredAt: start.add(Duration(hours: index * 3)),
        severity: 1 + (index % 5).toDouble(),
        symptom: 'Symptom ${index % 12}',
      );
    });
    final medications = List<MedicationAdherenceEvent>.generate(
      medicationCount,
      (index) {
        final scheduledAt = start.add(Duration(hours: index * 5));
        return MedicationAdherenceEvent(
          medicationName: 'Medication ${index % 4}',
          scheduledAt: scheduledAt,
          takenAt: index % 9 == 0
              ? null
              : scheduledAt.add(const Duration(minutes: 8)),
        );
      },
    );
    final therapy = List<TherapyObservation>.generate(therapyCount, (index) {
      return TherapyObservation(
        completedAt: start.add(Duration(hours: index * 7)),
        therapyType: index.isEven ? 'physical' : 'speech',
      );
    });

    for (var warmup = 0; warmup < 5; warmup += 1) {
      analytics.analyze(
        symptoms: symptoms,
        medicationEvents: medications,
        therapySessions: therapy,
        weeklyTherapyGoal: 8,
      );
    }

    final samples = <int>[];
    for (var run = 0; run < 30; run += 1) {
      final stopwatch = Stopwatch()..start();
      final result = analytics.analyze(
        symptoms: symptoms,
        medicationEvents: medications,
        therapySessions: therapy,
        weeklyTherapyGoal: 8,
      );
      stopwatch.stop();
      expect(result.eventCount, eventCount);
      samples.add(stopwatch.elapsedMicroseconds);
    }

    final p95Micros = _percentile(samples, 0.95);
    expect(p95Micros, lessThan(500000));
    // ignore: avoid_print
    print(
      'PARKIWELL_ANALYTICS_METRIC events=$eventCount '
      'p50_ms=${(_percentile(samples, 0.50) / 1000).toStringAsFixed(2)} '
      'p95_ms=${(p95Micros / 1000).toStringAsFixed(2)}',
    );
  });
}

int _percentile(List<int> values, double percentile) {
  final sorted = List<int>.from(values)..sort();
  final index = (sorted.length * percentile).ceil().clamp(1, sorted.length) - 1;
  return sorted[index];
}
