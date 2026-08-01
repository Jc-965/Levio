import 'package:flutter/material.dart';
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

  group('planReminderSlots', () {
    final now = DateTime(2026, 8, 3, 12, 0); // a Monday, noon

    test('orders slots by soonest next occurrence', () {
      final slots = MedicationReminderService.planReminderSlots(
        [
          ['Evening med', '', 'Every Monday', '20:00'],
          ['Afternoon med', '', 'Every Monday', '14:00'],
          ['Tomorrow med', '', 'Every Tuesday', '08:00'],
        ],
        const TimeOfDay(hour: 9, minute: 0),
        now,
      );

      expect(slots[0].name, 'Afternoon med');
      expect(slots[1].name, 'Evening med');
      expect(slots[2].name, 'Tomorrow med');
    });

    test('a slot at the current minute rolls to next week', () {
      final slots = MedicationReminderService.planReminderSlots(
        [
          ['Now med', '', 'Every Monday', '12:00'],
          ['Soon med', '', 'Every Monday', '12:01'],
        ],
        const TimeOfDay(hour: 9, minute: 0),
        now,
      );

      expect(slots.first.name, 'Soon med');
    });

    test('heavy regimens exceed the cap and keep the soonest doses', () {
      // 12 meds x everyday = 84 slots, past the 60-slot cap.
      final schedule = List.generate(
        12,
        (i) => ['Med $i', '', 'Everyday', '0${(i % 9) + 1}:00'],
      );
      final slots = MedicationReminderService.planReminderSlots(
        schedule,
        const TimeOfDay(hour: 9, minute: 0),
        now,
      );

      expect(slots.length, 84);
      expect(
        slots.length > MedicationReminderService.maxScheduledReminders,
        isTrue,
        reason: 'this regimen must trigger the capped path',
      );
      final kept = slots
          .take(MedicationReminderService.maxScheduledReminders)
          .toList();
      // Everything kept fires sooner than everything dropped.
      final dropped = slots
          .skip(MedicationReminderService.maxScheduledReminders)
          .toList();
      int minutesUntil(({String name, int weekday, TimeOfDay time}) s) {
        var d = (s.weekday - now.weekday) % 7;
        final sm = s.time.hour * 60 + s.time.minute;
        final nm = now.hour * 60 + now.minute;
        if (d == 0 && sm <= nm) d = 7;
        return d * 24 * 60 + sm - nm;
      }

      expect(minutesUntil(kept.last) <= minutesUntil(dropped.first), isTrue);
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
