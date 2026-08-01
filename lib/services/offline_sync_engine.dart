import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum SyncEntityType { log, schedule, recoverySession, medicationEvent }

enum SyncMutationOperation { upsert, delete }

class SyncMutation {
  const SyncMutation({
    required this.mutationId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.clientUpdatedAt,
    required this.sequence,
  });

  final String mutationId;
  final SyncEntityType entityType;
  final String entityId;
  final SyncMutationOperation operation;
  final Map<String, dynamic> payload;
  final DateTime clientUpdatedAt;
  final int sequence;

  String get entityKey => '${entityType.name}:$entityId';

  SyncMutation copyWith({int? sequence}) {
    return SyncMutation(
      mutationId: mutationId,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: Map<String, dynamic>.from(payload),
      clientUpdatedAt: clientUpdatedAt,
      sequence: sequence ?? this.sequence,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mutation_id': mutationId,
      'entity_type': entityType.name,
      'entity_id': entityId,
      'operation': operation.name,
      'payload': payload,
      'client_updated_at': clientUpdatedAt.toUtc().toIso8601String(),
      'sequence': sequence,
    };
  }

  Map<String, dynamic> toRpcJson() => toJson()..remove('sequence');

  static SyncMutation? fromJson(Map<String, dynamic> json) {
    final mutationId = json['mutation_id']?.toString().trim() ?? '';
    final entityId = json['entity_id']?.toString().trim() ?? '';
    final entityType = _enumByName(
      SyncEntityType.values,
      json['entity_type']?.toString(),
    );
    final operation = _enumByName(
      SyncMutationOperation.values,
      json['operation']?.toString(),
    );
    final clientUpdatedAt = DateTime.tryParse(
      json['client_updated_at']?.toString() ?? '',
    );

    if (mutationId.isEmpty ||
        entityId.isEmpty ||
        entityType == null ||
        operation == null ||
        clientUpdatedAt == null) {
      return null;
    }

    final rawPayload = json['payload'];
    return SyncMutation(
      mutationId: mutationId,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : <String, dynamic>{},
      clientUpdatedAt: clientUpdatedAt.toUtc(),
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
    );
  }

  static int compareVersion(SyncMutation a, SyncMutation b) {
    final timestampCompare = a.clientUpdatedAt.compareTo(b.clientUpdatedAt);
    if (timestampCompare != 0) return timestampCompare;

    final sequenceCompare = a.sequence.compareTo(b.sequence);
    if (sequenceCompare != 0) return sequenceCompare;

    return a.mutationId.compareTo(b.mutationId);
  }

  static T? _enumByName<T extends Enum>(Iterable<T> values, String? name) {
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

abstract class MutationJournalStore {
  Future<String?> read();

  Future<void> write(String encodedJournal);

  Future<void> clear();
}

class SharedPreferencesMutationJournalStore implements MutationJournalStore {
  SharedPreferencesMutationJournalStore(
    this.preferences, {
    this.storageKey = 'parkiwell_pending_mutations_v1',
  });

  final Future<SharedPreferences> preferences;
  final String storageKey;

  @override
  Future<String?> read() async {
    final prefs = await preferences;
    return prefs.getString(storageKey);
  }

  @override
  Future<void> write(String encodedJournal) async {
    final prefs = await preferences;
    final stored = await prefs.setString(storageKey, encodedJournal);
    if (!stored) {
      throw StateError('Unable to persist the offline mutation journal.');
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await preferences;
    final removed = await prefs.remove(storageKey);
    if (!removed && prefs.containsKey(storageKey)) {
      throw StateError('Unable to clear the offline mutation journal.');
    }
  }
}

typedef MutationBatchExecutor =
    Future<Set<String>> Function(List<SyncMutation> mutations);

class OfflineSyncEngine {
  OfflineSyncEngine(this._store);

  final MutationJournalStore _store;
  final Map<String, SyncMutation> _pendingByEntity = <String, SyncMutation>{};

  int _nextSequence = 1;
  bool _initialized = false;
  bool _isReplaying = false;
  Future<void> _persistTail = Future<void>.value();

  int get pendingCount => _pendingByEntity.length;
  bool get isReplaying => _isReplaying;

  List<SyncMutation> get pendingMutations {
    final mutations = _pendingByEntity.values.toList();
    mutations.sort(SyncMutation.compareVersion);
    return mutations;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final encoded = await _store.read();
    if (encoded != null && encoded.isNotEmpty) {
      restoreEncoded(encoded);
    }
    _initialized = true;
  }

  Future<SyncMutation> enqueue({
    required String mutationId,
    required SyncEntityType entityType,
    required String entityId,
    required SyncMutationOperation operation,
    Map<String, dynamic> payload = const <String, dynamic>{},
    DateTime? clientUpdatedAt,
  }) async {
    final mutation = SyncMutation(
      mutationId: mutationId,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: Map<String, dynamic>.from(payload),
      clientUpdatedAt: (clientUpdatedAt ?? DateTime.now()).toUtc(),
      sequence: _nextSequence++,
    );
    final SyncMutation? previous = _pendingByEntity[mutation.entityKey];
    _merge(mutation);
    try {
      await _persist();
    } catch (error) {
      // Undo the merge so the in-memory queue never holds a mutation the
      // journal write rejected; otherwise a later unrelated persist would
      // resurrect it and replay it to the backend even though the caller
      // rolled its own state back.
      if (identical(_pendingByEntity[mutation.entityKey], mutation)) {
        if (previous == null) {
          _pendingByEntity.remove(mutation.entityKey);
        } else {
          _pendingByEntity[mutation.entityKey] = previous;
        }
      }
      rethrow;
    }
    return mutation;
  }

  Future<void> enqueueAll(
    Iterable<SyncMutation> mutations, {
    bool persist = true,
  }) async {
    for (final rawMutation in mutations) {
      final mutation = rawMutation.sequence > 0
          ? rawMutation
          : rawMutation.copyWith(sequence: _nextSequence++);
      _nextSequence = mutation.sequence >= _nextSequence
          ? mutation.sequence + 1
          : _nextSequence;
      _merge(mutation);
    }
    if (persist) await _persist();
  }

  /// Server-visible rejection tallies per mutation. Only passes where the
  /// executor succeeded count: an unreachable server must never advance a
  /// mutation toward the dead-letter threshold.
  final Map<String, int> _rejectionCounts = <String, int>{};

  /// Mutations dropped after [maxRejectedPasses] server rejections, kept
  /// for surfacing "N changes could not be synced" to the user.
  final List<SyncMutation> deadLetteredMutations = <SyncMutation>[];

  static const int maxRejectedPasses = 3;

  Future<int> replay(
    MutationBatchExecutor executor, {
    int batchSize = 500,
  }) async {
    if (_isReplaying || _pendingByEntity.isEmpty) return 0;
    if (batchSize <= 0) {
      throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
    }

    _isReplaying = true;
    var acknowledgedCount = 0;
    try {
      final snapshot = pendingMutations;
      for (var offset = 0; offset < snapshot.length; offset += batchSize) {
        final end = (offset + batchSize).clamp(0, snapshot.length);
        final batch = snapshot.sublist(offset, end);
        Set<String> acknowledged;
        try {
          acknowledged = await executor(batch);
        } catch (_) {
          break;
        }

        // An empty acknowledgement (every mutation in the batch rejected,
        // e.g. as stale) must not strand LATER batches; only an executor
        // failure stops the replay loop.
        for (final mutation in batch) {
          if (acknowledged.contains(mutation.mutationId)) {
            _rejectionCounts.remove(mutation.mutationId);
            final current = _pendingByEntity[mutation.entityKey];
            if (current?.mutationId == mutation.mutationId) {
              _pendingByEntity.remove(mutation.entityKey);
              acknowledgedCount += 1;
            }
            continue;
          }
          // The server processed the batch but rejected this mutation
          // (constraint violation, squatted id). Retrying identical input
          // cannot succeed; after a few passes, quarantine it so one bad
          // mutation never wedges sync for the account forever.
          final failures = (_rejectionCounts[mutation.mutationId] ?? 0) + 1;
          _rejectionCounts[mutation.mutationId] = failures;
          if (failures >= maxRejectedPasses) {
            final current = _pendingByEntity[mutation.entityKey];
            if (current?.mutationId == mutation.mutationId) {
              _pendingByEntity.remove(mutation.entityKey);
              deadLetteredMutations.add(mutation);
            }
            _rejectionCounts.remove(mutation.mutationId);
          }
        }
        await _persist();
      }
      return acknowledgedCount;
    } finally {
      _isReplaying = false;
    }
  }

  Future<void> clear() async {
    _pendingByEntity.clear();
    _nextSequence = 1;
    await _schedulePersist(null);
  }

  String encodeJournal() {
    return jsonEncode(<String, dynamic>{
      'version': 1,
      'next_sequence': _nextSequence,
      'mutations': pendingMutations
          .map((mutation) => mutation.toJson())
          .toList(),
    });
  }

  void restoreEncoded(String encodedJournal) {
    final decoded = jsonDecode(encodedJournal);
    if (decoded is! Map) {
      throw const FormatException('Mutation journal must be a JSON object.');
    }

    final journal = Map<String, dynamic>.from(decoded);
    final rawMutations = journal['mutations'];
    _pendingByEntity.clear();
    _nextSequence = 1;

    if (rawMutations is List) {
      for (final rawMutation in rawMutations) {
        if (rawMutation is! Map) continue;
        final mutation = SyncMutation.fromJson(
          Map<String, dynamic>.from(rawMutation),
        );
        if (mutation == null) continue;
        _merge(mutation);
        if (mutation.sequence >= _nextSequence) {
          _nextSequence = mutation.sequence + 1;
        }
      }
    }

    final storedNextSequence = (journal['next_sequence'] as num?)?.toInt();
    if (storedNextSequence != null && storedNextSequence > _nextSequence) {
      _nextSequence = storedNextSequence;
    }
  }

  void _merge(SyncMutation mutation) {
    final current = _pendingByEntity[mutation.entityKey];
    if (current == null || SyncMutation.compareVersion(mutation, current) > 0) {
      _pendingByEntity[mutation.entityKey] = mutation;
    }
  }

  Future<void> _persist() async {
    final encoded = _pendingByEntity.isEmpty ? null : encodeJournal();
    await _schedulePersist(encoded);
  }

  Future<void> _schedulePersist(String? encodedJournal) {
    final previous = _persistTail;
    final completion = () async {
      try {
        await previous;
      } catch (_) {
        // A later snapshot must still be allowed to repair a failed write.
      }
      if (encodedJournal == null) {
        await _store.clear();
      } else {
        await _store.write(encodedJournal);
      }
    }();
    _persistTail = completion;
    return completion;
  }
}
