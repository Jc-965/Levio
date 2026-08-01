import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app_logger.dart';

/// Weekly local notifications for medication schedules.
///
/// Schedule entries carry days of the week but no time of day, so all
/// reminders fire at one user-configurable time (default 9:00). Reminders
/// are opt-in from Settings; enabling them requests notification
/// permission.
class MedicationReminderService {
  MedicationReminderService._internal();
  static final MedicationReminderService _instance =
      MedicationReminderService._internal();
  factory MedicationReminderService() => _instance;

  static const String enabledKey = 'medication_reminders_enabled_v1';
  static const String hourKey = 'medication_reminder_hour_v1';
  static const String minuteKey = 'medication_reminder_minute_v1';

  static const List<String> _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AppLogger _logger = AppLogger();
  bool _initialized = false;

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    try {
      tz_data.initializeTimeZones();
      try {
        final localTimezone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(localTimezone));
      } catch (_) {
        // Fall back to the bundled default location; times may be offset
        // but reminders still fire.
      }
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings);
      _initialized = true;
      return true;
    } catch (e) {
      // Plugin unavailable (tests, unsupported platform).
      _logger.warning('Medication reminders unavailable on this platform');
      return false;
    }
  }

  Future<bool> requestPermission() async {
    if (!await _ensureInitialized()) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      return true;
    } catch (e) {
      _logger.warning('Notification permission request failed');
      return false;
    }
  }

  Future<bool> remindersEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  Future<TimeOfDay> reminderTime() async {
    final prefs = await SharedPreferences.getInstance();
    return TimeOfDay(
      hour: prefs.getInt(hourKey) ?? 9,
      minute: prefs.getInt(minuteKey) ?? 0,
    );
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, enabled);
  }

  Future<void> setReminderTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(hourKey, time.hour);
    await prefs.setInt(minuteKey, time.minute);
  }

  /// Parses the stored schedule string ("Everyday" or
  /// "Every Monday, Tuesday") into ISO weekday numbers (1 = Monday).
  static Set<int> weekdaysFromScheduleText(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'no days selected') {
      return const <int>{};
    }
    if (normalized == 'everyday') return {1, 2, 3, 4, 5, 6, 7};
    final days = <int>{};
    for (var i = 0; i < _dayNames.length; i++) {
      if (normalized.contains(_dayNames[i].toLowerCase())) {
        days.add(i + 1);
      }
    }
    return days;
  }

  /// Cancels every pending reminder; used on sign-out and account
  /// deletion so a later device user never sees another person's
  /// medication names.
  Future<void> cancelAll() async {
    if (!await _ensureInitialized()) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      // Surfacing matters: failing to cancel means the next device user
      // could see the previous user's medication names.
      _logger.warning('Unable to cancel medication reminders');
    }
  }

  /// Parses per-dose times stored as "08:00,13:30" into [TimeOfDay]s.
  /// Invalid tokens are dropped; an empty result means the medication uses
  /// the app-wide default reminder time.
  static List<TimeOfDay> doseTimesFromText(String text) {
    final times = <TimeOfDay>[];
    for (final token in text.split(',')) {
      final parts = token.trim().split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null) continue;
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) continue;
      times.add(TimeOfDay(hour: hour, minute: minute));
    }
    return times;
  }

  /// iOS silently drops pending notifications past 64; stay under it with
  /// headroom so no dose reminder ever disappears without a trace.
  static const int maxScheduledReminders = 60;

  /// Expands schedule entries into (name, weekday, time) slots ordered by
  /// how soon each next fires from [now], so capping keeps the reminders a
  /// patient needs first. Pure and testable.
  static List<({String name, int weekday, TimeOfDay time})> planReminderSlots(
    List<List<String>> schedule,
    TimeOfDay fallbackTime,
    DateTime now,
  ) {
    final slots = <({String name, int weekday, TimeOfDay time})>[];
    for (final entry in schedule) {
      if (entry.isEmpty) continue;
      final name = entry[0];
      final daysText = entry.length > 2 ? entry[2] : 'Everyday';
      final doseTimes = doseTimesFromText(entry.length > 3 ? entry[3] : '');
      final times = doseTimes.isEmpty ? [fallbackTime] : doseTimes;
      for (final weekday in weekdaysFromScheduleText(daysText)) {
        for (final time in times) {
          slots.add((name: name, weekday: weekday, time: time));
        }
      }
    }

    int minutesUntil(({String name, int weekday, TimeOfDay time}) slot) {
      var dayDelta = (slot.weekday - now.weekday) % 7;
      final slotMinutes = slot.time.hour * 60 + slot.time.minute;
      final nowMinutes = now.hour * 60 + now.minute;
      if (dayDelta == 0 && slotMinutes <= nowMinutes) dayDelta = 7;
      return dayDelta * 24 * 60 + slotMinutes - nowMinutes;
    }

    slots.sort((a, b) => minutesUntil(a).compareTo(minutesUntil(b)));
    return slots;
  }

  /// Rebuilds all pending reminders from the current schedule list. Each
  /// entry is `[name, details, daysText]` with an optional fourth element
  /// of comma-separated per-dose times; medications without their own
  /// times fall back to the app-wide reminder time.
  Future<void> syncFromSchedule(List<List<String>> schedule) async {
    if (!await _ensureInitialized()) return;
    try {
      await _plugin.cancelAll();
      if (!await remindersEnabled()) return;

      final fallbackTime = await reminderTime();
      final slots = planReminderSlots(schedule, fallbackTime, DateTime.now());
      if (slots.length > maxScheduledReminders) {
        _logger.warning(
          'Reminder plan exceeds the platform pending limit; scheduling the '
          'soonest $maxScheduledReminders of ${slots.length} slots',
        );
      }
      var notificationId = 0;
      for (final slot in slots.take(maxScheduledReminders)) {
        await _scheduleWeekly(
          id: notificationId++,
          // iOS cannot hide the body on the lock screen the way the
          // Android private-visibility channel does, so the body stays
          // generic there; naming the drug would disclose the diagnosis.
          body: Platform.isIOS
              ? 'Time for your scheduled medication'
              : 'Time to take ${slot.name}',
          at: _nextInstanceOf(slot.weekday, slot.time),
        );
      }
    } catch (e) {
      _logger.warning('Unable to schedule medication reminders');
    }
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'medication_reminders',
      'Medication reminders',
      channelDescription: 'Reminders for scheduled medications in ParkiWell',
      importance: Importance.high,
      priority: Priority.high,
      // Keep medication names off the lock screen; naming a Parkinson's
      // drug there discloses the diagnosis to anyone glancing at it.
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Medication timing is clinically minute-sensitive, so exact delivery is
  /// attempted first; devices that deny the exact-alarm permission fall
  /// back to inexact scheduling rather than losing the reminder.
  Future<void> _scheduleWeekly({
    required int id,
    required String body,
    required tz.TZDateTime at,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        'Medication reminder',
        body,
        at,
        _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } on PlatformException {
      await _plugin.zonedSchedule(
        id,
        'Medication reminder',
        body,
        at,
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  tz.TZDateTime _nextInstanceOf(int weekday, TimeOfDay time) {
    var scheduled = tz.TZDateTime.now(tz.local);
    scheduled = tz.TZDateTime(
      tz.local,
      scheduled.year,
      scheduled.month,
      scheduled.day,
      time.hour,
      time.minute,
    );
    while (scheduled.weekday != weekday ||
        scheduled.isBefore(tz.TZDateTime.now(tz.local))) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
