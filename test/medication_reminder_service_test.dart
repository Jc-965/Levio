import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/services/medication_reminder_service.dart';

void main() {
  group('doseTimesFromText', () {
    test('parses comma separated times', () {
      final times = MedicationReminderService.doseTimesFromText(
        '08:00,13:30,20:15',
      );
      expect(times.length, 3);
      expect(times[1].hour, 13);
      expect(times[1].minute, 30);
    });

    test('drops invalid tokens and bounds', () {
      final times = MedicationReminderService.doseTimesFromText(
        '25:00,notatime,09:75,07:45',
      );
      expect(times.length, 1);
      expect(times.single.hour, 7);
    });

    test('empty text means no per-dose times', () {
      expect(MedicationReminderService.doseTimesFromText(''), isEmpty);
    });
  });

  group('weekdaysFromScheduleText', () {
    test('everyday maps to all seven weekdays', () {
      expect(MedicationReminderService.weekdaysFromScheduleText('Everyday'), {
        1,
        2,
        3,
        4,
        5,
        6,
        7,
      });
    });

    test('named days map to ISO weekday numbers', () {
      expect(
        MedicationReminderService.weekdaysFromScheduleText(
          'Every Monday, Wednesday, Friday',
        ),
        {1, 3, 5},
      );
    });

    test('weekend selection', () {
      expect(
        MedicationReminderService.weekdaysFromScheduleText(
          'Every Saturday, Sunday',
        ),
        {6, 7},
      );
    });

    test('no days selected yields no reminders', () {
      expect(
        MedicationReminderService.weekdaysFromScheduleText('No days selected'),
        isEmpty,
      );
      expect(MedicationReminderService.weekdaysFromScheduleText(''), isEmpty);
    });
  });
}
