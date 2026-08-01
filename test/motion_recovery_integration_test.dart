import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/singleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Singleton singleton;

  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    singleton = Singleton();
  });

  setUp(() {
    singleton.recoverySessions.clear();
    singleton.weeklyPhysicalExerciseGoal = 4;
    singleton.weeklySpeechExerciseGoal = 4;
  });

  group('motion coach recovery integration', () {
    test('a completed session counts as a physical recovery session', () async {
      await singleton.recordMotionCoachSession(
        routineId: 'seated_foundation',
        title: 'Motion coach: Seated foundation',
      );

      expect(singleton.recoverySessions, hasLength(1));
      final Map<String, dynamic> session = singleton.recoverySessions.single;
      expect(session['type'], Singleton.recoveryTypePhysical);
      expect(
        session['video_id'],
        '${Singleton.motionSessionIdPrefix}seated_foundation',
      );
      expect(session['title'], 'Motion coach: Seated foundation');
      expect(singleton.weeklyPhysicalExerciseSessions, 1);
    });

    test('rejects blank identity and future completion times', () async {
      await singleton.recordMotionCoachSession(routineId: '  ', title: 'x');
      await singleton.recordMotionCoachSession(routineId: 'r', title: '  ');
      await singleton.recordMotionCoachSession(
        routineId: 'seated_foundation',
        title: 'Motion coach: Seated foundation',
        completedAt: DateTime.now().add(const Duration(hours: 2)),
      );

      expect(singleton.recoverySessions, isEmpty);
    });

    test('motion sessions survive a snapshot round trip', () async {
      // Backup export/import funnels through the same normalization as the
      // startup cache hydration and cloud restore; before motion ids were
      // allowed through it, this round trip silently dropped the session.
      await singleton.recordMotionCoachSession(
        routineId: 'full_body',
        title: 'Motion coach: Full body',
      );
      final String backup = singleton.exportBackupJson();
      singleton.recoverySessions.clear();

      expect(await singleton.importBackupJson(backup), isTrue);

      expect(
        singleton.recoverySessions.where(
          (Map<String, dynamic> session) =>
              session['video_id'] ==
              '${Singleton.motionSessionIdPrefix}full_body',
        ),
        hasLength(1),
      );
      expect(singleton.weeklyPhysicalExerciseSessions, 1);
    });

    test(
      'YouTube sessions still normalize through the same round trip',
      () async {
        await singleton.recordPhysicalExerciseSession('AZV3_NfcpVs');
        final String backup = singleton.exportBackupJson();
        singleton.recoverySessions.clear();

        expect(await singleton.importBackupJson(backup), isTrue);
        expect(
          singleton.recoverySessions.where(
            (Map<String, dynamic> session) =>
                session['video_id'] == 'AZV3_NfcpVs',
          ),
          hasLength(1),
        );
      },
    );
  });
}
