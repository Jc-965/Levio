import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/singleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Characterization tests for the health-record CRUD paths in [Singleton].
///
/// The log/schedule model is positional string lists with parallel ID
/// arrays; these tests pin the alignment invariants so the planned typed
/// model migration has a safety net.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Singleton singleton;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    singleton = Singleton();
    singleton.log.clear();
    singleton.logIDs.clear();
    singleton.schedule.clear();
    singleton.scheduleIDs.clear();
  });

  group('symptom log CRUD', () {
    test(
      'saveLog keeps entries sorted newest-first with aligned ids',
      () async {
        await singleton.saveLog('08:00, 1 July 2026', 'Tremor', '3');
        await singleton.saveLog('09:30, 3 July 2026', 'Stiffness', '2');
        await singleton.saveLog('07:15, 2 July 2026', 'Fatigue', '4');

        expect(singleton.log.length, 3);
        expect(singleton.logIDs.length, 3);
        expect(singleton.log[0][1], 'Stiffness');
        expect(singleton.log[1][1], 'Fatigue');
        expect(singleton.log[2][1], 'Tremor');
        expect(singleton.logIDs.toSet().length, 3);
      },
    );

    test('deleteLog removes the entry and its id at the same index', () async {
      await singleton.saveLog('08:00, 1 July 2026', 'Tremor', '3');
      await singleton.saveLog('09:30, 3 July 2026', 'Stiffness', '2');
      final removedId = singleton.logIDs[0];
      final keptId = singleton.logIDs[1];

      final deleted = await singleton.deleteLog(0);

      expect(deleted, isTrue);
      expect(singleton.log.length, 1);
      expect(singleton.logIDs, [keptId]);
      expect(singleton.logIDs, isNot(contains(removedId)));
      expect(singleton.log[0][1], 'Tremor');
    });

    test('updateLogEntry preserves the entry id and re-sorts', () async {
      await singleton.saveLog('08:00, 1 July 2026', 'Tremor', '3');
      await singleton.saveLog('09:30, 3 July 2026', 'Stiffness', '2');
      final tremorIndex = singleton.log.indexWhere((e) => e[1] == 'Tremor');
      final tremorId = singleton.logIDs[tremorIndex];

      final updated = await singleton.updateLogEntry(
        tremorIndex,
        '10:00, 4 July 2026',
        'Tremor',
        '5',
      );

      expect(updated, isTrue);
      final newIndex = singleton.log.indexWhere((e) => e[1] == 'Tremor');
      expect(newIndex, 0, reason: 'newest entry sorts first');
      expect(singleton.logIDs[newIndex], tremorId);
      expect(singleton.log[newIndex][2], '5');
    });

    test(
      'unparseable timestamps sort to the tail but are never dropped',
      () async {
        await singleton.saveLog('08:00, 1 July 2026', 'Tremor', '3');
        await singleton.saveLog('not a real date', 'Mystery', '1');
        await singleton.saveLog('09:30, 3 July 2026', 'Stiffness', '2');

        expect(
          singleton.log.length,
          3,
          reason: 'bad dates must not be dropped',
        );
        expect(singleton.log.last[1], 'Mystery');
        expect(singleton.logIDs.length, 3);
      },
    );

    test('deleteLog with an out-of-range index is a safe no-op', () async {
      await singleton.saveLog('08:00, 1 July 2026', 'Tremor', '3');

      expect(await singleton.deleteLog(5), isFalse);
      expect(await singleton.deleteLog(-1), isFalse);
      expect(singleton.log.length, 1);
    });
  });

  group('medication schedule CRUD', () {
    test('saveSchedule appends aligned entry and id', () async {
      await singleton.saveSchedule('Levodopa', '100mg', 'Everyday');

      expect(singleton.schedule.single, ['Levodopa', '100mg', 'Everyday']);
      expect(singleton.scheduleIDs.single, isNotEmpty);
    });

    test('per-dose times survive save and backup round-trip', () async {
      await singleton.saveSchedule(
        'Levodopa',
        '100mg',
        'Everyday',
        doseTimes: '08:00,13:00,18:00',
      );

      expect(singleton.schedule.single, [
        'Levodopa',
        '100mg',
        'Everyday',
        '08:00,13:00,18:00',
      ]);

      final backup = singleton.exportBackupJson();
      singleton.schedule.clear();
      singleton.scheduleIDs.clear();
      expect(await singleton.importBackupJson(backup), isTrue);
      expect(singleton.schedule.single.length, 4);
      expect(singleton.schedule.single[3], '08:00,13:00,18:00');
    });

    test('updateScheduleEntry rewrites in place with a stable id', () async {
      await singleton.saveSchedule('Levodopa', '100mg', 'Everyday');
      await singleton.saveSchedule('Amantadine', '50mg', 'Every Monday');
      final id = singleton.scheduleIDs[1];

      final updated = await singleton.updateScheduleEntry(
        1,
        'Amantadine',
        '100mg',
        'Every Monday, Friday',
      );

      expect(updated, isTrue);
      expect(singleton.schedule[1], [
        'Amantadine',
        '100mg',
        'Every Monday, Friday',
      ]);
      expect(singleton.scheduleIDs[1], id);
    });

    test('deleteScheduleEntry removes the matching id', () async {
      await singleton.saveSchedule('Levodopa', '100mg', 'Everyday');
      await singleton.saveSchedule('Amantadine', '50mg', 'Every Monday');
      final keptId = singleton.scheduleIDs[1];

      expect(await singleton.deleteScheduleEntry(0), isTrue);
      expect(singleton.schedule.single[0], 'Amantadine');
      expect(singleton.scheduleIDs.single, keptId);
    });
  });

  group('backup round-trip', () {
    test('export and import preserve logs and schedules', () async {
      await singleton.saveLog('08:00, 1 July 2026', 'Tremor', '3');
      await singleton.saveSchedule('Levodopa', '100mg', 'Everyday');

      final backup = singleton.exportBackupJson();

      singleton.log.clear();
      singleton.logIDs.clear();
      singleton.schedule.clear();
      singleton.scheduleIDs.clear();

      expect(await singleton.importBackupJson(backup), isTrue);
      expect(singleton.log.single[1], 'Tremor');
      expect(singleton.schedule.single[0], 'Levodopa');
      expect(singleton.logIDs.length, singleton.log.length);
    });
  });
}
