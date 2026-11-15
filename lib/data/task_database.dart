/// SQLite persistence layer.
///
/// Schema (version 1):
///
/// ```
/// tasks    (id, title, description, category, due_date, repeat_type,
///           repeat_days, repeat_interval, reminder_minutes, is_completed,
///           completed_at, created_at)
/// subtasks (id, task_id -> tasks.id, title, is_done)
/// ```
///
/// Dates are stored as milliseconds since epoch. The same code runs on Android
/// (native SQLite) and on Chrome (SQLite WASM) - only the [DatabaseFactory]
/// differs, and it is chosen by the conditional import below.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../models/task.dart';
import 'db_factory_stub.dart'
    if (dart.library.js_interop) 'db_factory_web.dart'
    if (dart.library.io) 'db_factory_io.dart';

class TaskDatabase {
  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final dbFactory = getDatabaseFactory();
    final dir = await dbFactory.getDatabasesPath();
    final path = p.join(dir, 'tasknest.db');
    return dbFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tasks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              category TEXT NOT NULL DEFAULT 'Personal',
              due_date INTEGER NOT NULL,
              repeat_type INTEGER NOT NULL DEFAULT 0,
              repeat_days TEXT NOT NULL DEFAULT '',
              repeat_interval INTEGER NOT NULL DEFAULT 1,
              reminder_minutes INTEGER NOT NULL DEFAULT 0,
              is_completed INTEGER NOT NULL DEFAULT 0,
              completed_at INTEGER,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE subtasks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              task_id INTEGER NOT NULL,
              title TEXT NOT NULL,
              is_done INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE CASCADE
            )
          ''');
        },
      ),
    );
  }

  /// Loads every task together with its subtasks.
  Future<List<Task>> loadAll() async {
    final db = await _database;
    final taskRows = await db.query('tasks', orderBy: 'due_date ASC');
    final subRows = await db.query('subtasks', orderBy: 'id ASC');

    final byTask = <int, List<Subtask>>{};
    for (final row in subRows) {
      final taskId = row['task_id'] as int;
      byTask.putIfAbsent(taskId, () => <Subtask>[]).add(Subtask.fromMap(row));
    }
    return taskRows
        .map((row) => Task.fromMap(row, byTask[row['id'] as int] ?? <Subtask>[]))
        .toList();
  }

  /// Inserts [task] and its subtasks. Assigns the new ids to the objects.
  Future<void> insertTask(Task task) async {
    final db = await _database;
    await db.transaction((txn) async {
      task.id = await txn.insert('tasks', task.toMap());
      for (final s in task.subtasks) {
        s.id = await txn.insert('subtasks', s.toMap(task.id!));
      }
    });
  }

  /// Updates only the task row (not the subtasks).
  Future<void> updateTaskRow(Task task) async {
    final db = await _database;
    await db.update('tasks', task.toMap(), where: 'id = ?', whereArgs: [task.id]);
  }

  /// Updates the task row and replaces its subtasks with the current list.
  Future<void> updateTaskWithSubtasks(Task task) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.update('tasks', task.toMap(), where: 'id = ?', whereArgs: [task.id]);
      await txn.delete('subtasks', where: 'task_id = ?', whereArgs: [task.id]);
      for (final s in task.subtasks) {
        s.id = await txn.insert('subtasks', s.toMap(task.id!));
      }
    });
  }

  Future<void> setSubtaskDone(Subtask subtask) async {
    if (subtask.id == null) return;
    final db = await _database;
    await db.update(
      'subtasks',
      {'is_done': subtask.done ? 1 : 0},
      where: 'id = ?',
      whereArgs: [subtask.id],
    );
  }

  /// Unchecks every subtask of a task (used when a repeating task resets).
  Future<void> resetSubtasks(int taskId) async {
    final db = await _database;
    await db.update('subtasks', {'is_done': 0}, where: 'task_id = ?', whereArgs: [taskId]);
  }

  Future<void> deleteTask(int id) async {
    final db = await _database;
    await db.transaction((txn) async {
      await txn.delete('subtasks', where: 'task_id = ?', whereArgs: [id]);
      await txn.delete('tasks', where: 'id = ?', whereArgs: [id]);
    });
  }
}
