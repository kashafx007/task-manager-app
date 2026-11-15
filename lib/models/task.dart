/// Data models for TaskNest: [Task], [Subtask] and the repeat-schedule logic.
library;

import '../utils/format_utils.dart';

/// How a task repeats.
///
/// * [none]     - a normal one-off task.
/// * [daily]    - every day.
/// * [weekly]   - on the weekdays chosen by the user (Mon..Sun).
/// * [interval] - every N days.
enum RepeatType { none, daily, weekly, interval }

/// Categories offered in the UI.
const List<String> kCategories = ['Personal', 'Study', 'Work', 'Health', 'Shopping', 'Other'];

/// A small emoji for every category (used on chips).
const Map<String, String> kCategoryEmoji = {
  'Personal': '🌸',
  'Study': '📚',
  'Work': '💼',
  'Health': '🍓',
  'Shopping': '🛍️',
  'Other': '✨',
};

/// Early-reminder choices in minutes. `0` means "no early reminder"
/// (a notification at the due time is always sent).
const List<int> kReminderOptions = [0, 5, 10, 15, 30, 60, 1440];

/// Short label used on chips in the task form.
String reminderChipLabel(int minutes) {
  switch (minutes) {
    case 0:
      return 'None';
    case 60:
      return '1 hour';
    case 1440:
      return '1 day';
    default:
      return '$minutes min';
  }
}

/// Sentence-style label used in notifications and on task cards.
String reminderLabel(int minutes) {
  switch (minutes) {
    case 0:
      return 'No early reminder';
    case 60:
      return '1 hour before';
    case 1440:
      return '1 day before';
    default:
      return '$minutes min before';
  }
}

/// One checklist item inside a [Task]. Used for progress tracking.
class Subtask {
  Subtask({this.id, required this.title, this.done = false});

  int? id;
  String title;
  bool done;

  factory Subtask.fromMap(Map<String, Object?> m) => Subtask(
        id: m['id'] as int?,
        title: m['title'] as String,
        done: (m['is_done'] as int? ?? 0) == 1,
      );

  Map<String, Object?> toMap(int taskId) => {
        'task_id': taskId,
        'title': title,
        'is_done': done ? 1 : 0,
      };
}

/// A task. The date and time of [dueDate] are both meaningful: the time is
/// used for notifications and for repeating tasks.
class Task {
  Task({
    this.id,
    required this.title,
    this.description = '',
    this.category = 'Personal',
    required this.dueDate,
    this.repeatType = RepeatType.none,
    Set<int>? repeatDays,
    this.repeatInterval = 1,
    this.reminderMinutes = 0,
    this.completed = false,
    this.completedAt,
    DateTime? createdAt,
    List<Subtask>? subtasks,
  })  : repeatDays = repeatDays ?? <int>{},
        createdAt = createdAt ?? DateTime.now(),
        subtasks = subtasks ?? <Subtask>[];

  int? id;
  String title;
  String description;
  String category;
  DateTime dueDate;
  RepeatType repeatType;

  /// Weekdays for [RepeatType.weekly]; uses [DateTime.monday]..[DateTime.sunday].
  Set<int> repeatDays;

  /// Number of days between repeats for [RepeatType.interval].
  int repeatInterval;

  /// Minutes before [dueDate] for the optional early reminder (0 = none).
  int reminderMinutes;

  bool completed;
  DateTime? completedAt;
  final DateTime createdAt;
  List<Subtask> subtasks;

  bool get isRepeating => repeatType != RepeatType.none;

  int get doneSubtasks => subtasks.where((s) => s.done).length;

  /// 0.0 - 1.0 based on subtasks (or on completion when there are none).
  double get progress {
    if (subtasks.isEmpty) return completed ? 1.0 : 0.0;
    return doneSubtasks / subtasks.length;
  }

  bool isOverdue(DateTime now) => !completed && dueDate.isBefore(now);

  /// Human readable repeat description, e.g. `Daily`, `Every Mon, Wed`.
  String get repeatSummary {
    switch (repeatType) {
      case RepeatType.none:
        return 'Does not repeat';
      case RepeatType.daily:
        return 'Daily';
      case RepeatType.weekly:
        final days = repeatDays.toList()..sort();
        if (days.isEmpty) return 'Weekly';
        return 'Every ${days.map(weekdayShort).join(', ')}';
      case RepeatType.interval:
        return repeatInterval == 1 ? 'Every day' : 'Every $repeatInterval days';
    }
  }

  /// A deep copy (subtasks are copied too).
  Task clone() => Task(
        id: id,
        title: title,
        description: description,
        category: category,
        dueDate: dueDate,
        repeatType: repeatType,
        repeatDays: Set<int>.of(repeatDays),
        repeatInterval: repeatInterval,
        reminderMinutes: reminderMinutes,
        completed: completed,
        completedAt: completedAt,
        createdAt: createdAt,
        subtasks: subtasks.map((s) => Subtask(id: s.id, title: s.title, done: s.done)).toList(),
      );

  factory Task.fromMap(Map<String, Object?> m, List<Subtask> subtasks) {
    final days = (m['repeat_days'] as String? ?? '')
        .split(',')
        .where((e) => e.trim().isNotEmpty)
        .map((e) => int.parse(e.trim()))
        .toSet();
    final completedAtMs = m['completed_at'] as int?;
    return Task(
      id: m['id'] as int?,
      title: m['title'] as String,
      description: m['description'] as String? ?? '',
      category: m['category'] as String? ?? 'Personal',
      dueDate: DateTime.fromMillisecondsSinceEpoch(m['due_date'] as int),
      repeatType: RepeatType.values[(m['repeat_type'] as int?) ?? 0],
      repeatDays: days,
      repeatInterval: (m['repeat_interval'] as int?) ?? 1,
      reminderMinutes: (m['reminder_minutes'] as int?) ?? 0,
      completed: (m['is_completed'] as int? ?? 0) == 1,
      completedAt: completedAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(completedAtMs),
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      subtasks: subtasks,
    );
  }

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'description': description,
        'category': category,
        'due_date': dueDate.millisecondsSinceEpoch,
        'repeat_type': repeatType.index,
        'repeat_days': (repeatDays.toList()..sort()).join(','),
        'repeat_interval': repeatInterval,
        'reminder_minutes': reminderMinutes,
        'is_completed': completed ? 1 : 0,
        'completed_at': completedAt?.millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
      };
}

// ---------------------------------------------------------------------------
// Repeat schedule helpers
// ---------------------------------------------------------------------------

DateTime _atTimeOf(Task t, DateTime day) =>
    DateTime(day.year, day.month, day.day, t.dueDate.hour, t.dueDate.minute);

/// The next occurrence of [t] on a calendar day strictly *after* [from]'s day,
/// at the same time of day as [Task.dueDate].
DateTime nextOccurrence(Task t, DateTime from) {
  final base = dateOnly(from);
  switch (t.repeatType) {
    case RepeatType.none:
      return t.dueDate;
    case RepeatType.daily:
      return _atTimeOf(t, addDays(base, 1));
    case RepeatType.weekly:
      if (t.repeatDays.isEmpty) return _atTimeOf(t, addDays(base, 1));
      for (var i = 1; i <= 7; i++) {
        final candidate = addDays(base, i);
        if (t.repeatDays.contains(candidate.weekday)) return _atTimeOf(t, candidate);
      }
      return _atTimeOf(t, addDays(base, 1));
    case RepeatType.interval:
      final step = t.repeatInterval < 1 ? 1 : t.repeatInterval;
      return _atTimeOf(t, addDays(base, step));
  }
}

/// For weekly tasks: moves [Task.dueDate] forward to the first selected
/// weekday on or after it. Other repeat types are returned unchanged.
DateTime alignToSchedule(Task t) {
  if (t.repeatType != RepeatType.weekly || t.repeatDays.isEmpty) return t.dueDate;
  final base = dateOnly(t.dueDate);
  for (var i = 0; i < 7; i++) {
    final candidate = addDays(base, i);
    if (t.repeatDays.contains(candidate.weekday)) return _atTimeOf(t, candidate);
  }
  return t.dueDate;
}

/// Whether a repeating task is scheduled to occur on [day].
bool occursOn(Task t, DateTime day) {
  switch (t.repeatType) {
    case RepeatType.none:
      return sameDay(t.dueDate, day);
    case RepeatType.daily:
    case RepeatType.interval:
      return true;
    case RepeatType.weekly:
      return t.repeatDays.isEmpty || t.repeatDays.contains(day.weekday);
  }
}

/// All due moments of [t] between [start] and [end] (inclusive).
/// A non-repeating task yields at most one moment.
List<DateTime> occurrencesBetween(Task t, DateTime start, DateTime end) {
  final result = <DateTime>[];
  if (!t.isRepeating) {
    if (!t.dueDate.isBefore(start) && !t.dueDate.isAfter(end)) result.add(t.dueDate);
    return result;
  }
  var candidate = t.dueDate;
  var guard = 0;
  while (candidate.isBefore(start) && guard < 4000) {
    candidate = nextOccurrence(t, candidate);
    guard++;
  }
  while (!candidate.isAfter(end) && result.length < 60 && guard < 8000) {
    result.add(candidate);
    candidate = nextOccurrence(t, candidate);
    guard++;
  }
  return result;
}
