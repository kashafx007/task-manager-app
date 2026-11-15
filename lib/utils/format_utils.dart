/// Small date/time helpers used across the app.
///
/// The project deliberately avoids the `intl` package so that there are fewer
/// dependencies to keep in sync; these helpers cover everything we display.
library;

const List<String> _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Strips the time part, keeping only year-month-day (local time).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// True when both dates fall on the same calendar day.
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Adds [n] calendar days while keeping the hour/minute (safe across DST).
DateTime addDays(DateTime d, int n) =>
    DateTime(d.year, d.month, d.day + n, d.hour, d.minute);

/// `1` (Monday) .. `7` (Sunday) -> `Mon` .. `Sun`.
String weekdayShort(int weekday) => _weekdayShort[weekday - 1];

/// Example: `Sun, 15 Nov 2026`.
String formatDate(DateTime d) =>
    '${_weekdayShort[d.weekday - 1]}, ${d.day} ${_monthShort[d.month - 1]} ${d.year}';

/// Example: `15 Nov`.
String formatShortDate(DateTime d) => '${d.day} ${_monthShort[d.month - 1]}';

/// Example: `1:05 PM`.
String formatTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${d.hour >= 12 ? 'PM' : 'AM'}';
}

/// `Today`, `Tomorrow`, `Yesterday` or a short date such as `20 Nov`.
String friendlyDate(DateTime d, DateTime now) {
  final diff = dateOnly(d).difference(dateOnly(now)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return formatShortDate(d);
}

/// Compact timestamp for file names, e.g. `20261115_1304`.
String fileStamp(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}';
}
