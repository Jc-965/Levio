/// The single parser/formatter for the legacy log timestamp format
/// ("HH:mm, d Month yyyy"). Three private copies of this logic used to
/// drift independently; every reader and writer now goes through here.
library;

const List<String> logMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

final Map<String, int> _monthToIndex = {
  for (var i = 0; i < logMonthNames.length; i++) logMonthNames[i]: i + 1,
};

DateTime? parseLogTimestamp(String value) {
  final parts = value.split(',');
  if (parts.length != 2) return null;

  final timeSegments = parts.first.trim().split(':');
  final dateSegments = parts.last.trim().split(' ');
  if (timeSegments.length != 2 || dateSegments.length != 3) return null;

  final hour = int.tryParse(timeSegments[0]);
  final minute = int.tryParse(timeSegments[1]);
  final day = int.tryParse(dateSegments[0]);
  final month = _monthToIndex[dateSegments[1]];
  final year = int.tryParse(dateSegments[2]);
  if (hour == null ||
      minute == null ||
      day == null ||
      month == null ||
      year == null) {
    return null;
  }
  return DateTime(year, month, day, hour, minute);
}

String formatLogTimestamp(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$hour:$minute, $day ${logMonthNames[value.month - 1]} ${value.year}';
}
