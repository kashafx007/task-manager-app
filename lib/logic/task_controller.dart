/// The brain of the app: holds the task list in memory, talks to SQLite and
/// the notification service, and tells the UI to rebuild.
///
/// **Instant updates:** every action first changes the in-memory list and calls
/// `notifyListeners()` so the screen updates immediately. Saving to SQLite and
/// scheduling notifications happen afterwards, so they never delay the UI.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/task_database.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import '../utils/format_utils.dart';

class TaskController extends ChangeNotifier {
  TaskController(this._db, this._notifications);

  final TaskDatabase _db;
  final NotificationService _notifications;

  List<Task> _tasks = <Task>[];
  Timer? _ticker;

  bool isLoading = true;
  String? loadError;

  /// Selected category chip (null = all categories).
  String? categoryFilter;

  // ------------------------------------------------------------------ loading

  Future<void> load() async {
    try {
      _tasks = await _db.loadAll();
      await _runMaintenance();
      loadError = null;
    } catch (e, st) {
      debugPrint('Failed to load tasks: $e\n$st');
      loadError = e.toString();
    }
    isLoading = false;
    notifyListeners();

    if (loadError == null) {
      unawaited(_notifications.rescheduleAll(_tasks));
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 15), (_) => _onTick());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _onTick() async {
    final changed = await _runMaintenance();
    if (changed) unawaited(_notifications.rescheduleAll(_tasks));
    _notifications.checkWebDue(_tasks);
    notifyListeners(); // refreshes "overdue" labels and the greeting
  }

  /// Housekeeping for repeating tasks:
  ///
  /// 1. A completed repeating task is reset (unchecked, subtasks cleared) once
  ///    its next scheduled day arrives.
  /// 2. An unfinished repeating task whose day has passed is moved forward to
  ///    its next scheduled day.
  Future<bool> _runMaintenance() async {
    final now = DateTime.now();
    final today = dateOnly(now);
    var changed = false;

    for (final t in _tasks) {
      if (!t.isRepeating || t.id == null) continue;

      if (t.completed && !dateOnly(t.dueDate).isAfter(today)) {
        t.completed = false;
        t.completedAt = null;
        for (final s in t.subtasks) {
          s.done = false;
        }
        await _db.updateTaskRow(t);
        await _db.resetSubtasks(t.id!);
        changed = true;
      }

      if (!t.completed && dateOnly(t.dueDate).isBefore(today)) {
        t.dueDate = _rollForward(t, now);
        for (final s in t.subtasks) {
          s.done = false;
        }
        await _db.updateTaskRow(t);
        await _db.resetSubtasks(t.id!);
        changed = true;
      }
    }
    return changed;
  }

  DateTime _rollForward(Task t, DateTime now) {
    var d = t.dueDate;
    var guard = 0;
    while (dateOnly(d).isBefore(dateOnly(now)) && guard < 2000) {
      d = nextOccurrence(t, d);
      guard++;
    }
    return d;
  }

  // -------------------------------------------------------------------- views

  List<Task> _applyFilter(Iterable<Task> source) {
    if (categoryFilter == null) return source.toList();
    return source.where((t) => t.category == categoryFilter).toList();
  }

  /// Tasks due today that are not finished yet, earliest first.
  List<Task> get todayTasks {
    final now = DateTime.now();
    final list = _applyFilter(_tasks.where((t) => !t.completed && sameDay(t.dueDate, now)));
    list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  /// Every task that has a repeat setting (finished or not).
  List<Task> get repeatedTasks {
    final list = _applyFilter(_tasks.where((t) => t.isRepeating));
    list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  /// Finished tasks, most recently completed first.
  List<Task> get completedTasks {
    final list = _applyFilter(_tasks.where((t) => t.completed));
    list.sort((a, b) {
      final ac = a.completedAt ?? a.dueDate;
      final bc = b.completedAt ?? b.dueDate;
      return bc.compareTo(ac);
    });
    return list;
  }

  /// Everything: open tasks by due date first, then finished tasks.
  List<Task> get allTasks {
    final list = _applyFilter(_tasks);
    list.sort((a, b) {
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      return a.dueDate.compareTo(b.dueDate);
    });
    return list;
  }

  /// Unfinished tasks whose due date and time have already passed,
  /// the longest overdue first.
  List<Task> get overdueTasks {
    final now = DateTime.now();
    final list = _applyFilter(_tasks.where((t) => t.isOverdue(now)));
    list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  /// Unfiltered copy used by the export feature.
  List<Task> get rawTasks => List<Task>.unmodifiable(_tasks);

  // Counts for the bottom-bar badges and the header (ignore the category filter).
  int get todayCount {
    final now = DateTime.now();
    return _tasks.where((t) => !t.completed && sameDay(t.dueDate, now)).length;
  }

  int get repeatedCount => _tasks.where((t) => t.isRepeating).length;
  int get overdueCount {
    final now = DateTime.now();
    return _tasks.where((t) => t.isOverdue(now)).length;
  }
  int get completedCount => _tasks.where((t) => t.completed).length;
  int get allCount => _tasks.length;

  /// Tasks finished today (used for the "today's progress" bar).
  int get doneTodayCount {
    final now = DateTime.now();
    return _tasks.where((t) => t.completedAt != null && sameDay(t.completedAt!, now)).length;
  }

  void setCategoryFilter(String? category) {
    categoryFilter = category;
    notifyListeners();
  }

  // ------------------------------------------------------------------ actions

  /// Adds a new task. The list updates immediately; saving happens after.
  Future<void> addTask(Task task) async {
    task.dueDate = alignToSchedule(task);
    _tasks.add(task);
    notifyListeners();
    try {
      await _db.insertTask(task);
      notifyListeners();
      unawaited(_notifications.scheduleTask(task));
    } catch (e) {
      debugPrint('addTask failed: $e');
    }
  }

  /// Replaces an existing task (matched by id) with the edited version.
  Future<void> updateTask(Task edited) async {
    edited.dueDate = alignToSchedule(edited);
    final index = _tasks.indexWhere((t) => t.id == edited.id);
    if (index == -1) return;
    _tasks[index] = edited;
    notifyListeners();
    try {
      await _db.updateTaskWithSubtasks(edited);
      notifyListeners();
      unawaited(_notifications.scheduleTask(edited));
    } catch (e) {
      debugPrint('updateTask failed: $e');
    }
  }

  Future<void> deleteTask(Task task) async {
    _tasks.removeWhere((t) => t.id == task.id);
    notifyListeners();
    final id = task.id;
    if (id == null) return;
    try {
      await _db.deleteTask(id);
      unawaited(_notifications.cancelForTask(id));
    } catch (e) {
      debugPrint('deleteTask failed: $e');
    }
  }

  /// Puts back a task that was just deleted (the "Undo" action).
  Future<void> restoreTask(Task task) async {
    task.id = null;
    for (final s in task.subtasks) {
      s.id = null;
    }
    await addTask(task);
  }

  /// Checks / unchecks a task.
  ///
  /// Completing a repeating task moves its due date to the next scheduled
  /// occurrence; it sits in "Completed" until that day arrives and is then
  /// reset automatically (see [_runMaintenance]).
  Future<void> toggleComplete(Task t) async {
    final now = DateTime.now();
    if (!t.completed) {
      t.completed = true;
      t.completedAt = now;
      if (t.isRepeating) t.dueDate = nextOccurrence(t, t.dueDate);
    } else {
      t.completed = false;
      t.completedAt = null;
      if (t.isRepeating && occursOn(t, now)) {
        t.dueDate = DateTime(now.year, now.month, now.day, t.dueDate.hour, t.dueDate.minute);
      }
    }
    notifyListeners();
    try {
      await _db.updateTaskRow(t);
      unawaited(_notifications.scheduleTask(t));
    } catch (e) {
      debugPrint('toggleComplete failed: $e');
    }
  }

  Future<void> toggleSubtask(Task t, Subtask s) async {
    s.done = !s.done;
    notifyListeners();
    try {
      await _db.setSubtaskDone(s);
    } catch (e) {
      debugPrint('toggleSubtask failed: $e');
    }
  }
}