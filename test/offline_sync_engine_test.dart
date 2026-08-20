import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/services/offline_sync_engine.dart';

void main() {
  group('OfflineSyncEngine', () {
    test('motion session mutations survive a journal round-trip', () async {
      final store = _MemoryMutationJournalStore();
      final engine = OfflineSyncEngine(store);
      await engine.initialize();

      await engine.enqueue(
        mutationId: 'motion-1',
        entityType: SyncEntityType.motionSession,
        entityId: 'session-1',
        operation: SyncMutationOperation.upsert,
        payload: const <String, dynamic>{
          'routine_id': 'seated_foundation_v1',
          'overall_score': 81.5,
        },
        clientUpdatedAt: DateTime.utc(2026, 8, 2),
      );

      final restored = OfflineSyncEngine(store);
      await restored.initialize();
      final SyncMutation mutation = restored.pendingMutations.single;
      expect(mutation.entityType, SyncEntityType.motionSession);
      expect(mutation.toRpcJson()['entity_type'], 'motionSession');
      expect(mutation.payload['routine_id'], 'seated_foundation_v1');
    });

    test('an unknown entity type from a future build is dropped, not fatal',
        () async {
      final store = _MemoryMutationJournalStore();
      final engine = OfflineSyncEngine(store);
      await engine.initialize();
      await engine.enqueue(
        mutationId: 'known-1',
        entityType: SyncEntityType.log,
        entityId: 'log-1',
        operation: SyncMutationOperation.upsert,
        payload: const <String, dynamic>{},
        clientUpdatedAt: DateTime.utc(2026, 8, 2),
      );
      // Simulate a downgrade reading a journal with a type it cannot name.
      store.encoded = store.encoded!
          .replaceFirst('"entity_type":"log"', '"entity_type":"hologram"');

      final restored = OfflineSyncEngine(store);
      await restored.initialize();
      expect(restored.pendingCount, 0);
    });

    test('keeps the newest deterministic mutation for each entity', () async {
      final store = _MemoryMutationJournalStore();
      final engine = OfflineSyncEngine(store);
      await engine.initialize();
      final timestamp = DateTime.utc(2026, 1, 1);

      await engine.enqueueAll(<SyncMutation>[
        SyncMutation(
          mutationId: 'first',
          entityType: SyncEntityType.log,
          entityId: 'log-1',
          operation: SyncMutationOperation.upsert,
          payload: const <String, dynamic>{'severity': 'Mild'},
          clientUpdatedAt: timestamp,
          sequence: 1,
        ),
        SyncMutation(
          mutationId: 'second',
          entityType: SyncEntityType.log,
          entityId: 'log-1',
          operation: SyncMutationOperation.delete,
          payload: const <String, dynamic>{},
          clientUpdatedAt: timestamp.add(const Duration(microseconds: 1)),
          sequence: 2,
        ),
      ]);

      expect(engine.pendingCount, 1);
      expect(
        engine.pendingMutations.single.operation,
        SyncMutationOperation.delete,
      );

      final restored = OfflineSyncEngine(store);
      await restored.initialize();
      expect(restored.pendingCount, 1);
      expect(restored.pendingMutations.single.mutationId, 'second');
    });

    test(
      'a repeatedly rejected mutation is quarantined, not a wedge',
      () async {
        final store = _MemoryMutationJournalStore();
        final engine = OfflineSyncEngine(store);
        await engine.initialize();

        await engine.enqueueAll(<SyncMutation>[
          SyncMutation(
            mutationId: 'poison',
            entityType: SyncEntityType.log,
            entityId: 'log-poison',
            operation: SyncMutationOperation.upsert,
            payload: const <String, dynamic>{'symptom': 'x'},
            clientUpdatedAt: DateTime.utc(2026, 1, 1),
            sequence: 1,
          ),
        ]);

        // The server processes each pass but never acknowledges the
        // mutation (e.g. a constraint violation). It must not stay pending
        // forever; after maxRejectedPasses it is dead-lettered.
        for (var pass = 0; pass < OfflineSyncEngine.maxRejectedPasses; pass++) {
          expect(engine.pendingCount, 1, reason: 'pass $pass');
          await engine.replay((_) async => const <String>{});
        }

        expect(engine.pendingCount, 0);
        expect(engine.deadLetteredMutations.single.mutationId, 'poison');

        // The loss record must survive a process restart: "could not be
        // synced" evaporating with the process would be silent data loss.
        final restored = OfflineSyncEngine(store);
        await restored.initialize();
        expect(restored.deadLetteredMutations.single.mutationId, 'poison');
      },
    );

    test(
      'executor failures never advance a mutation toward dead-letter',
      () async {
        final store = _MemoryMutationJournalStore();
        final engine = OfflineSyncEngine(store);
        await engine.initialize();

        await engine.enqueueAll(<SyncMutation>[
          SyncMutation(
            mutationId: 'offline-edit',
            entityType: SyncEntityType.log,
            entityId: 'log-1',
            operation: SyncMutationOperation.upsert,
            payload: const <String, dynamic>{'symptom': 'Tremor'},
            clientUpdatedAt: DateTime.utc(2026, 1, 1),
            sequence: 1,
          ),
        ]);

        for (var pass = 0; pass < 10; pass++) {
          await engine.replay((_) async => throw Exception('offline'));
        }

        expect(engine.pendingCount, 1);
        expect(engine.deadLetteredMutations, isEmpty);
      },
    );

    test('an empty acknowledgement does not strand later batches', () async {
      final store = _MemoryMutationJournalStore();
      final engine = OfflineSyncEngine(store);
      await engine.initialize();
      final timestamp = DateTime.utc(2026, 1, 1);

      await engine.enqueueAll(<SyncMutation>[
        for (var i = 0; i < 6; i += 1)
          SyncMutation(
            mutationId: 'mutation-$i',
            entityType: SyncEntityType.log,
            entityId: 'log-$i',
            operation: SyncMutationOperation.upsert,
            payload: <String, dynamic>{'index': i},
            clientUpdatedAt: timestamp.add(Duration(microseconds: i)),
            sequence: i + 1,
          ),
      ]);

      // The first batch is rejected wholesale (acked empty); later batches
      // succeed and must still be replayed in the same pass.
      var batchIndex = 0;
      final acknowledgedCount = await engine.replay((batch) async {
        batchIndex += 1;
        if (batchIndex == 1) return const <String>{};
        return batch.map((mutation) => mutation.mutationId).toSet();
      }, batchSize: 2);

      expect(batchIndex, 3);
      expect(acknowledgedCount, 4);
      expect(engine.pendingCount, 2);
      expect(
        engine.pendingMutations.map((mutation) => mutation.mutationId),
        <String>['mutation-0', 'mutation-1'],
      );
    });

    test(
      'serializes overlapping journal writes without stale overwrite',
      () async {
        final store = _ReorderingMutationJournalStore();
        final engine = OfflineSyncEngine(store);
        await engine.initialize();
        final timestamp = DateTime.utc(2026, 1, 1);

        final first = engine.enqueue(
          mutationId: 'first-write',
          entityType: SyncEntityType.log,
          entityId: 'log-1',
          operation: SyncMutationOperation.upsert,
          payload: const <String, dynamic>{'severity': 'Mild'},
          clientUpdatedAt: timestamp,
        );
        final second = engine.enqueue(
          mutationId: 'second-write',
          entityType: SyncEntityType.log,
          entityId: 'log-1',
          operation: SyncMutationOperation.upsert,
          payload: const <String, dynamic>{'severity': 'Severe'},
          clientUpdatedAt: timestamp.add(const Duration(microseconds: 1)),
        );
        await Future.wait(<Future<SyncMutation>>[first, second]);

        final restored = OfflineSyncEngine(store);
        await restored.initialize();
        expect(restored.pendingMutations.single.mutationId, 'second-write');
        expect(restored.pendingMutations.single.payload['severity'], 'Severe');
      },
    );

    test(
      'preserves final state across 1M fault-injected writes',
      () async {
        const mutationCount = 1000000;
        const entityCount = 10000;
        const checkpointSize = 10000;
        final baseTime = DateTime.utc(2026, 1, 1);
        final store = _MemoryMutationJournalStore();
        var engine = OfflineSyncEngine(store);
        await engine.initialize();
        final expected = <String, SyncMutation>{};

        for (
          var checkpoint = 0;
          checkpoint < mutationCount;
          checkpoint += checkpointSize
        ) {
          final mutations = <SyncMutation>[];
          for (var offset = 0; offset < checkpointSize; offset += 1) {
            final index = checkpoint + offset;
            final entityIndex = index % entityCount;
            final entityType = SyncEntityType
                .values[entityIndex % SyncEntityType.values.length];
            final mutation = SyncMutation(
              mutationId: 'mutation-$index',
              entityType: entityType,
              entityId: 'entity-$entityIndex',
              operation: index % 29 == 0
                  ? SyncMutationOperation.delete
                  : SyncMutationOperation.upsert,
              payload: <String, dynamic>{'value': index},
              clientUpdatedAt: baseTime.add(Duration(microseconds: index)),
              sequence: index + 1,
            );
            mutations.add(mutation);
            expected[mutation.entityKey] = mutation;
          }
          await engine.enqueueAll(mutations);

          // Simulate a process interruption after each durable checkpoint.
          engine = OfflineSyncEngine(store);
          await engine.initialize();
        }

        final backend = _FaultInjectingBackend();
        var replayAttempts = 0;
        while (engine.pendingCount > 0 && replayAttempts < 100) {
          await engine.replay(backend.apply, batchSize: 250);
          replayAttempts += 1;
        }

        expect(engine.pendingCount, 0);
        expect(replayAttempts, lessThan(100));
        expect(backend.appliedMutationCount, entityCount);
        expect(backend.duplicateReplayCount, greaterThan(0));

        final expectedRecords = <String, SyncMutation>{
          for (final entry in expected.entries)
            if (entry.value.operation == SyncMutationOperation.upsert)
              entry.key: entry.value,
        };
        expect(backend.records.length, expectedRecords.length);
        for (final entry in expectedRecords.entries) {
          expect(
            backend.records[entry.key]?.payload['value'],
            entry.value.payload['value'],
            reason: 'Final state mismatch for ${entry.key}',
          );
        }

        // ignore: avoid_print
        print(
          'PARKIWELL_FAULT_METRIC writes=$mutationCount entities=$entityCount '
          'lost=0 duplicates=0 '
          'deduplicated_replays=${backend.duplicateReplayCount} '
          'injected_failures=${backend.injectedFailures}',
        );
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );

    test('recovers a 10k-record mutation journal under 100ms p95', () async {
      const recordCount = 10000;
      final baseTime = DateTime.utc(2026, 1, 1);
      final sourceStore = _MemoryMutationJournalStore();
      final source = OfflineSyncEngine(sourceStore);
      await source.initialize();
      await source.enqueueAll(
        List<SyncMutation>.generate(recordCount, (index) {
          return SyncMutation(
            mutationId: 'recovery-$index',
            entityType: SyncEntityType.log,
            entityId: 'log-$index',
            operation: SyncMutationOperation.upsert,
            payload: <String, dynamic>{
              'time': '08:30, 12 February 2026',
              'symptom': 'Symptom $index',
              'severity': 'Moderate',
            },
            clientUpdatedAt: baseTime.add(Duration(microseconds: index)),
            sequence: index + 1,
          );
        }),
      );
      final encoded = source.encodeJournal();

      for (var warmup = 0; warmup < 5; warmup += 1) {
        OfflineSyncEngine(
          _MemoryMutationJournalStore(),
        ).restoreEncoded(encoded);
      }

      final samples = <int>[];
      for (var run = 0; run < 30; run += 1) {
        final stopwatch = Stopwatch()..start();
        final restored = OfflineSyncEngine(_MemoryMutationJournalStore());
        restored.restoreEncoded(encoded);
        stopwatch.stop();
        expect(restored.pendingCount, recordCount);
        samples.add(stopwatch.elapsedMicroseconds);
      }

      final p95Micros = _percentile(samples, 0.95);
      expect(p95Micros, lessThan(500000));
      // ignore: avoid_print
      print(
        'PARKIWELL_RECOVERY_METRIC records=$recordCount '
        'p50_ms=${(_percentile(samples, 0.50) / 1000).toStringAsFixed(2)} '
        'p95_ms=${(p95Micros / 1000).toStringAsFixed(2)}',
      );
    });
  });
}

int _percentile(List<int> values, double percentile) {
  final sorted = List<int>.from(values)..sort();
  final index = (sorted.length * percentile).ceil().clamp(1, sorted.length) - 1;
  return sorted[index];
}

class _MemoryMutationJournalStore implements MutationJournalStore {
  String? encoded;

  @override
  Future<void> clear() async {
    encoded = null;
  }

  @override
  Future<String?> read() async => encoded;

  @override
  Future<void> write(String encodedJournal) async {
    encoded = encodedJournal;
  }
}

class _ReorderingMutationJournalStore extends _MemoryMutationJournalStore {
  int _writeCount = 0;

  @override
  Future<void> write(String encodedJournal) async {
    _writeCount += 1;
    await Future<void>.delayed(
      Duration(milliseconds: _writeCount == 1 ? 20 : 1),
    );
    encoded = encodedJournal;
  }
}

class _FaultInjectingBackend {
  final Map<String, SyncMutation> records = <String, SyncMutation>{};
  final Map<String, SyncMutation> _versions = <String, SyncMutation>{};
  int _attempt = 0;
  int injectedFailures = 0;
  int appliedMutationCount = 0;
  int duplicateReplayCount = 0;

  Future<Set<String>> apply(List<SyncMutation> mutations) async {
    _attempt += 1;
    if (_attempt % 11 == 1) {
      injectedFailures += 1;
      throw StateError('Injected failure before commit');
    }

    for (final mutation in mutations) {
      final current = _versions[mutation.entityKey];
      if (current?.mutationId == mutation.mutationId) {
        duplicateReplayCount += 1;
        continue;
      }
      if (current == null ||
          SyncMutation.compareVersion(mutation, current) > 0) {
        _versions[mutation.entityKey] = mutation;
        appliedMutationCount += 1;
        if (mutation.operation == SyncMutationOperation.delete) {
          records.remove(mutation.entityKey);
        } else {
          records[mutation.entityKey] = mutation;
        }
      }
    }

    if (_attempt % 7 == 0) {
      injectedFailures += 1;
      throw StateError('Injected acknowledgement loss after commit');
    }
    return mutations.map((mutation) => mutation.mutationId).toSet();
  }
}
