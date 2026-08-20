typedef AsyncLoader<T> = Future<T> Function();

class HealthSyncSnapshot {
  const HealthSyncSnapshot({
    required this.user,
    required this.logs,
    required this.schedules,
    required this.recoverySessions,
    required this.medicationEvents,
    required this.motionSessions,
  });

  final Map<String, dynamic>? user;
  final List<Map<String, dynamic>> logs;
  final List<Map<String, dynamic>> schedules;
  final List<Map<String, dynamic>> recoverySessions;
  final List<Map<String, dynamic>> medicationEvents;
  final List<Map<String, dynamic>> motionSessions;
}

class HealthSyncCoordinator {
  const HealthSyncCoordinator();

  Future<HealthSyncSnapshot> loadParallel({
    required AsyncLoader<Map<String, dynamic>?> user,
    required AsyncLoader<List<Map<String, dynamic>>> logs,
    required AsyncLoader<List<Map<String, dynamic>>> schedules,
    required AsyncLoader<List<Map<String, dynamic>>> recoverySessions,
    required AsyncLoader<List<Map<String, dynamic>>> medicationEvents,
    required AsyncLoader<List<Map<String, dynamic>>> motionSessions,
  }) async {
    final values = await Future.wait<dynamic>(<Future<dynamic>>[
      user(),
      logs(),
      schedules(),
      recoverySessions(),
      medicationEvents(),
      motionSessions(),
    ]);
    return _snapshotFrom(values);
  }

  Future<HealthSyncSnapshot> loadSequential({
    required AsyncLoader<Map<String, dynamic>?> user,
    required AsyncLoader<List<Map<String, dynamic>>> logs,
    required AsyncLoader<List<Map<String, dynamic>>> schedules,
    required AsyncLoader<List<Map<String, dynamic>>> recoverySessions,
    required AsyncLoader<List<Map<String, dynamic>>> medicationEvents,
    required AsyncLoader<List<Map<String, dynamic>>> motionSessions,
  }) async {
    final values = <dynamic>[
      await user(),
      await logs(),
      await schedules(),
      await recoverySessions(),
      await medicationEvents(),
      await motionSessions(),
    ];
    return _snapshotFrom(values);
  }

  HealthSyncSnapshot _snapshotFrom(List<dynamic> values) {
    return HealthSyncSnapshot(
      user: values[0] as Map<String, dynamic>?,
      logs: List<Map<String, dynamic>>.from(values[1] as List),
      schedules: List<Map<String, dynamic>>.from(values[2] as List),
      recoverySessions: List<Map<String, dynamic>>.from(values[3] as List),
      medicationEvents: List<Map<String, dynamic>>.from(values[4] as List),
      motionSessions: List<Map<String, dynamic>>.from(values[5] as List),
    );
  }
}
