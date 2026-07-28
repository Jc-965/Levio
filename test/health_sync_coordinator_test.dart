import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/services/health_sync_coordinator.dart';

void main() {
  const coordinator = HealthSyncCoordinator();

  test('parallel health sync preserves the complete snapshot', () async {
    final snapshot = await coordinator.loadParallel(
      user: () async => <String, dynamic>{'id': 'user-1'},
      logs: () async => <Map<String, dynamic>>[
        <String, dynamic>{'id': 'log-1'},
      ],
      schedules: () async => <Map<String, dynamic>>[
        <String, dynamic>{'id': 'schedule-1'},
      ],
      recoverySessions: () async => <Map<String, dynamic>>[
        <String, dynamic>{'id': 'therapy-1'},
      ],
      medicationEvents: () async => <Map<String, dynamic>>[
        <String, dynamic>{'id': 'medication-1'},
      ],
    );

    expect(snapshot.user?['id'], 'user-1');
    expect(snapshot.logs.single['id'], 'log-1');
    expect(snapshot.schedules.single['id'], 'schedule-1');
    expect(snapshot.recoverySessions.single['id'], 'therapy-1');
    expect(snapshot.medicationEvents.single['id'], 'medication-1');
  });

  test(
    'parallel orchestration cuts p95 sync latency by at least 70%',
    () async {
      Future<Map<String, dynamic>?> user() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return <String, dynamic>{'id': 'user'};
      }

      Future<List<Map<String, dynamic>>> records() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return <Map<String, dynamic>>[];
      }

      final sequentialSamples = <int>[];
      final parallelSamples = <int>[];
      for (var run = 0; run < 25; run += 1) {
        var stopwatch = Stopwatch()..start();
        await coordinator.loadSequential(
          user: user,
          logs: records,
          schedules: records,
          recoverySessions: records,
          medicationEvents: records,
        );
        stopwatch.stop();
        sequentialSamples.add(stopwatch.elapsedMicroseconds);

        stopwatch = Stopwatch()..start();
        await coordinator.loadParallel(
          user: user,
          logs: records,
          schedules: records,
          recoverySessions: records,
          medicationEvents: records,
        );
        stopwatch.stop();
        parallelSamples.add(stopwatch.elapsedMicroseconds);
      }

      final sequentialP95 = _percentile(sequentialSamples, 0.95);
      final parallelP95 = _percentile(parallelSamples, 0.95);
      final reduction = 1 - (parallelP95 / sequentialP95);
      expect(reduction, greaterThanOrEqualTo(0.70));
      // ignore: avoid_print
      print(
        'PARKIWELL_SYNC_METRIC sequential_p95_ms='
        '${(sequentialP95 / 1000).toStringAsFixed(2)} parallel_p95_ms='
        '${(parallelP95 / 1000).toStringAsFixed(2)} reduction_pct='
        '${(reduction * 100).toStringAsFixed(1)}',
      );
    },
  );
}

int _percentile(List<int> values, double percentile) {
  final sorted = List<int>.from(values)..sort();
  final index = (sorted.length * percentile).ceil().clamp(1, sorted.length) - 1;
  return sorted[index];
}
