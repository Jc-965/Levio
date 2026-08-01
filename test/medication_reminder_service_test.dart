import 'package:flutter_test/flutter_test.dart';
import 'package:parkiwell/services/medication_reminder_service.dart';

void main() {
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
