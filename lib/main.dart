import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ============================================================
//  TaskNest - Task Manager
//  Flutter + SQLite (sqflite) + Local Notifications
// ============================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  NotificationService.soundKey = prefs.getString('sound') ?? 'default';
  try {
    await NotificationService().init();
  } catch (_) {
    // The app must still start even if notifications cannot be initialised.
  }
  runApp(TaskApp(initialTheme: prefs.getString('theme') ?? 'system'));
}

// ------------------------- CONSTANTS ------------------------

const List<String> kDayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

class AppColors {
  static const brown = Color(0xFF8A6444);
  static const deepBrown = Color(0xFF4E3828);
  static const tan = Color(0xFFD9C2A3);
  static const cream = Color(0xFFFBF6EE);
  static const blush = Color(0xFFE9B9A8);
}

class TaskCategory {
  final String name;
  final IconData icon;
  final Color color;
  const TaskCategory(this.name, this.icon, this.color);
}

const List<TaskCategory> kCategories = [
  TaskCategory('Personal', Icons.favorite_outline, Color(0xFFC9806B)),
  TaskCategory('Work', Icons.work_outline, Color(0xFF8A6444)),
  TaskCategory('Study', Icons.menu_book_outlined, Color(0xFF7C8F6A)),
  TaskCategory('Health', Icons.spa_outlined, Color(0xFF6E97A3)),
  TaskCategory('Other', Icons.bookmark_border, Color(0xFFA98F7B)),
];

TaskCategory categoryOf(String name) =>
    kCategories.firstWhere((c) => c.name == name, orElse: () => kCategories.last);

/// Early-reminder choices in minutes (0 = no early reminder).
const List<int> kRemindOptions = [0, 5, 10, 15, 30, 60, 120, 1440];

// ------------------------- MODELS ---------------------------

class SubTask {
  String title;
  bool done;
  SubTask(this.title, [this.done = false]);
}

class Task {
  int? id;
  String title;
  String description;
  String category;
  DateTime due;
  int repeatType; // 0 none, 1 daily, 2 selected days
  Set<int> repeatDays; // 1 = Mon ... 7 = Sun
  bool done; // non-repeating tasks
  String? lastDone; // repeating tasks (yyyy-MM-dd)
  bool reminder;
  String? subReset; // day on which subtasks were last reset
  int remindBefore; // minutes before due time (0 = only at due time)
  List<SubTask> subtasks;

  Task({
    this.id,
    required this.title,
    this.description = '',
    this.category = 'Personal',
    required this.due,
    this.repeatType = 0,
    Set<int>? repeatDays,
    this.done = false,
    this.lastDone,
    this.reminder = true,
    this.subReset,
    this.remindBefore = 5,
    List<SubTask>? subtasks,
  })  : repeatDays = repeatDays ?? {},
        subtasks = subtasks ?? [];

  bool get repeats => repeatType != 0;

  bool get isDone => repeats ? lastDone == ymd(DateTime.now()) : done;

  bool get isOverdue => !repeats && !isDone && due.isBefore(DateTime.now());

  bool activeOn(DateTime d) {
    if (repeatType == 1) return true;
    if (repeatType == 2) return repeatDays.contains(d.weekday);
    return ymd(due) == ymd(d);
  }

  double get progress {
    if (isDone) return 1;
    if (subtasks.isEmpty) return 0;
    return subtasks.where((s) => s.done).length / subtasks.length;
  }

  String get repeatText {
    if (repeatType == 1) return 'Daily';
    if (repeatType == 2) {
      final days = repeatDays.toList()..sort();
      return days.map((d) => kDayNames[d - 1]).join(', ');
    }
    return '';
  }

  Map<String, dynamic> toRow() => {
    'title': title,
    'description': description,
    'category': category,
    'due': due.millisecondsSinceEpoch,
    'repeat_type': repeatType,
    'repeat_days': repeatDays.join(','),
    'done': done ? 1 : 0,
    'last_done': lastDone,
    'reminder': reminder ? 1 : 0,
    'sub_reset': subReset,
    'remind_before': remindBefore,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    ...toRow(),
    'subtasks': subtasks.map((s) => {'t': s.title, 'd': s.done}).toList(),
  };

  static Set<int> _days(String? s) => (s ?? '')
      .split(',')
      .where((e) => e.isNotEmpty)
      .map(int.parse)
      .toSet();

  factory Task.fromRow(Map<String, Object?> r) => Task(
    id: r['id'] as int?,
    title: r['title'] as String,
    description: (r['description'] ?? '') as String,
    category: (r['category'] ?? 'Personal') as String,
    due: DateTime.fromMillisecondsSinceEpoch(r['due'] as int),
    repeatType: (r['repeat_type'] ?? 0) as int,
    repeatDays: _days(r['repeat_days'] as String?),
    done: r['done'] == 1,
    lastDone: r['last_done'] as String?,
    reminder: r['reminder'] == 1,
    subReset: r['sub_reset'] as String?,
    remindBefore: (r['remind_before'] ?? 5) as int,
  );

  factory Task.fromJson(Map<String, dynamic> j) {
    final t = Task.fromRow(j);
    t.subtasks = ((j['subtasks'] ?? []) as List)
        .map((e) => SubTask(e['t'] as String, e['d'] as bool))
        .toList();
    return t;
  }
}

// ------------------------ DATABASE --------------------------
// Android / iOS: SQLite (sqflite). Web preview: SharedPreferences fallback.

class TaskDb {
  static Database? _db;
  static List<Task> _web = [];

  static Future<Database> _open() async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'tasks.db'),
      version: 3,
      onCreate: (d, v) async {
        await d.execute('''CREATE TABLE tasks(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          description TEXT,
          category TEXT DEFAULT 'Personal',
          due INTEGER,
          repeat_type INTEGER,
          repeat_days TEXT,
          done INTEGER,
          last_done TEXT,
          reminder INTEGER,
          sub_reset TEXT,
          remind_before INTEGER DEFAULT 5)''');
        await d.execute('''CREATE TABLE subtasks(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id INTEGER,
          title TEXT,
          done INTEGER)''');
      },
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) {
          await d.execute(
              "ALTER TABLE tasks ADD COLUMN category TEXT DEFAULT 'Personal'");
        }
        if (oldV < 3) {
          await d.execute(
              'ALTER TABLE tasks ADD COLUMN remind_before INTEGER DEFAULT 5');
        }
      },
    );
    return _db!;
  }

  static Future<void> _saveWeb() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'web_tasks', _web.map((t) => jsonEncode(t.toJson())).toList());
  }

  static Future<List<Task>> loadAll() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      _web = (prefs.getStringList('web_tasks') ?? [])
          .map((s) => Task.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .toList();
      return List.of(_web);
    }
    final d = await _open();
    final rows = await d.query('tasks');
    final subs = await d.query('subtasks', orderBy: 'id ASC');
    return rows.map((r) {
      final t = Task.fromRow(r);
      t.subtasks = subs
          .where((s) => s['task_id'] == t.id)
          .map((s) => SubTask(s['title'] as String, s['done'] == 1))
          .toList();
      return t;
    }).toList();
  }

  static Future<void> save(Task t) async {
    if (kIsWeb) {
      if (t.id == null) {
        t.id = _web.fold<int>(0, (m, e) => (e.id ?? 0) > m ? e.id! : m) + 1;
      }
      _web.removeWhere((e) => e.id == t.id);
      _web.add(t);
      await _saveWeb();
      return;
    }
    final d = await _open();
    if (t.id == null) {
      t.id = await d.insert('tasks', t.toRow());
    } else {
      await d.update('tasks', t.toRow(), where: 'id = ?', whereArgs: [t.id]);
    }
    await d.delete('subtasks', where: 'task_id = ?', whereArgs: [t.id]);
    for (final s in t.subtasks) {
      await d.insert('subtasks',
          {'task_id': t.id, 'title': s.title, 'done': s.done ? 1 : 0});
    }
  }

  static Future<void> delete(Task t) async {
    if (kIsWeb) {
      _web.removeWhere((e) => e.id == t.id);
      await _saveWeb();
      return;
    }
    final d = await _open();
    await d.delete('subtasks', where: 'task_id = ?', whereArgs: [t.id]);
    await d.delete('tasks', where: 'id = ?', whereArgs: [t.id]);
  }
}

// ---------------------- NOTIFICATIONS -----------------------

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  static String soundKey = 'default'; // default | alarm | ringtone | silent

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (kIsWeb) return;
    tzdata.initializeTimeZones();
    _setLocalZone();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await impl?.requestNotificationsPermission();
    } catch (_) {}
    try {
      await impl?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  /// Picks the time zone that matches the phone's current UTC offset.
  void _setLocalZone() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final offMs = DateTime.now().timeZoneOffset.inMilliseconds;
    try {
      final pref = tz.getLocation('Asia/Karachi');
      if (pref.timeZone(nowMs).offset == offMs) {
        tz.setLocalLocation(pref);
        return;
      }
    } catch (_) {}
    for (final loc in tz.timeZoneDatabase.locations.values) {
      if (loc.timeZone(nowMs).offset == offMs) {
        tz.setLocalLocation(loc);
        return;
      }
    }
  }

  NotificationDetails _details() {
    AndroidNotificationSound? sound;
    var play = true;
    switch (soundKey) {
      case 'alarm':
        sound = const UriAndroidNotificationSound(
            'content://settings/system/alarm_alert');
        break;
      case 'ringtone':
        sound = const UriAndroidNotificationSound(
            'content://settings/system/ringtone');
        break;
      case 'silent':
        play = false;
        break;
    }
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'tasks_$soundKey',
        'Task Reminders ($soundKey)',
        channelDescription: 'Reminders for upcoming tasks',
        importance: Importance.high,
        priority: Priority.high,
        playSound: play,
        sound: sound,
        icon: '@mipmap/ic_launcher',
      ),
    );
  }

  tz.TZDateTime _nextTime(int h, int m) {
    final now = tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, h, m);
    if (d.isBefore(now)) d = d.add(const Duration(days: 1));
    return d;
  }

  tz.TZDateTime _nextWeekday(int weekday, int h, int m) {
    var d = _nextTime(h, m);
    while (d.weekday != weekday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  Future<void> _zone(int id, String title, String body, tz.TZDateTime when,
      {DateTimeComponents? repeat}) async {
    try {
      await _plugin.zonedSchedule(id, title, body, when, _details(),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: repeat);
    } catch (_) {
      // Exact alarms may be blocked on this phone; fall back to an inexact one.
      try {
        await _plugin.zonedSchedule(id, title, body, when, _details(),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: repeat);
      } catch (_) {}
    }
  }

  /// Human readable text for an early-reminder offset, e.g. "10 min".
  static String beforeLabel(int minutes) {
    if (minutes % 1440 == 0) {
      final d = minutes ~/ 1440;
      return d == 1 ? '1 day' : '$d days';
    }
    if (minutes % 60 == 0) {
      final h = minutes ~/ 60;
      return h == 1 ? '1 hour' : '$h hours';
    }
    return '$minutes min';
  }

  // Notification ids: id*100 + slot.
  //   slot 0 / 1..7    -> at due time (once+daily / weekly day)
  //   slot 10 / 11..17 -> early reminder (once+daily / weekly day)
  Future<void> schedule(Task t) async {
    if (kIsWeb || t.id == null) return;
    try {
      await cancel(t);
      if (!t.reminder) return;
      final base = t.id! * 100;
      final h = t.due.hour, m = t.due.minute;
      final early = Duration(minutes: t.remindBefore);
      final hasEarly = t.remindBefore > 0;
      final earlyBody = 'Due in ${beforeLabel(t.remindBefore)}';
      const dueBody = 'Due now';
      final now = tz.TZDateTime.now(tz.local);

      if (t.repeatType == 0) {
        if (t.done || !t.due.isAfter(DateTime.now())) return;
        final due = tz.TZDateTime.from(t.due, tz.local);
        await _zone(base, t.title, dueBody, due);
        if (hasEarly) {
          final e = due.subtract(early);
          if (e.isAfter(now)) await _zone(base + 10, t.title, earlyBody, e);
        }
      } else if (t.repeatType == 1) {
        await _zone(base, t.title, dueBody, _nextTime(h, m),
            repeat: DateTimeComponents.time);
        if (hasEarly) {
          var e = _nextTime(h, m).subtract(early);
          while (!e.isAfter(now)) {
            e = e.add(const Duration(days: 1));
          }
          await _zone(base + 10, t.title, earlyBody, e,
              repeat: DateTimeComponents.time);
        }
      } else {
        for (final day in t.repeatDays) {
          final due = _nextWeekday(day, h, m);
          await _zone(base + day, t.title, dueBody, due,
              repeat: DateTimeComponents.dayOfWeekAndTime);
          if (hasEarly) {
            var e = due.subtract(early);
            while (!e.isAfter(now)) {
              e = e.add(const Duration(days: 7));
            }
            await _zone(base + 10 + day, t.title, earlyBody, e,
                repeat: DateTimeComponents.dayOfWeekAndTime);
          }
        }
      }
    } catch (_) {
      // Never let a notification problem block the app.
    }
  }

  Future<void> cancel(Task t) async {
    if (kIsWeb || t.id == null) return;
    for (var i = 0; i <= 7; i++) {
      await _plugin.cancel(t.id! * 100 + i);
      await _plugin.cancel(t.id! * 100 + 10 + i);
    }
  }

  Future<void> showNow() async {
    if (kIsWeb) return;
    await _plugin.show(999999999, 'Test notification',
        'This is how your task reminders will sound.', _details());
  }
}

// --------------------------- THEME --------------------------

class GinghamPainter extends CustomPainter {
  final Color base;
  final Color stripe;
  const GinghamPainter(this.base, this.stripe);

  @override
  void paint(Canvas canvas, Size size) {
    const s = 26.0;
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final paint = Paint()..color = stripe;
    for (double x = 0; x < size.width; x += s * 2) {
      canvas.drawRect(Rect.fromLTWH(x, 0, s, size.height), paint);
    }
    for (double y = 0; y < size.height; y += s * 2) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, s), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GinghamPainter old) =>
      old.base != base || old.stripe != stripe;
}

class GinghamBackground extends StatelessWidget {
  final Widget child;
  const GinghamBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: CustomPaint(
        painter: dark
            ? const GinghamPainter(Color(0xFF241C17), Color(0x1AD9C2A3))
            : const GinghamPainter(AppColors.cream, Color(0x4DD9C2A3)),
        child: child,
      ),
    );
  }
}

/// A small hand-drawn teddy bear face used in the header and empty screens.
class BearFace extends StatelessWidget {
  final double size;
  const BearFace({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size), painter: _BearPainter());
}

class _BearPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    Offset o(double x, double y) => Offset(s.width * x, s.height * y);
    final w = s.width;
    final fur = Paint()..color = const Color(0xFFC99A6B);
    final dark = Paint()..color = const Color(0xFF8A6444);
    final cream = Paint()..color = const Color(0xFFF6E7D0);
    final ink = Paint()..color = const Color(0xFF4E3828);
    final blush = Paint()..color = const Color(0x66E9887A);
    canvas.drawCircle(o(0.2, 0.2), w * 0.17, fur);
    canvas.drawCircle(o(0.8, 0.2), w * 0.17, fur);
    canvas.drawCircle(o(0.2, 0.2), w * 0.09, cream);
    canvas.drawCircle(o(0.8, 0.2), w * 0.09, cream);
    canvas.drawCircle(o(0.5, 0.56), w * 0.4, fur);
    canvas.drawOval(
        Rect.fromCenter(center: o(0.5, 0.69), width: w * 0.36, height: w * 0.26),
        cream);
    canvas.drawCircle(o(0.36, 0.48), w * 0.04, ink);
    canvas.drawCircle(o(0.64, 0.48), w * 0.04, ink);
    canvas.drawCircle(o(0.27, 0.62), w * 0.06, blush);
    canvas.drawCircle(o(0.73, 0.62), w * 0.06, blush);
    canvas.drawOval(
        Rect.fromCenter(center: o(0.5, 0.62), width: w * 0.13, height: w * 0.09),
        dark);
    final smile = Path()
      ..moveTo(w * 0.42, w * 0.72)
      ..quadraticBezierTo(w * 0.5, w * 0.8, w * 0.58, w * 0.72);
    canvas.drawPath(
        smile,
        Paint()
          ..color = const Color(0xFF4E3828)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.025
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// --------------------------- APP ----------------------------

class TaskApp extends StatefulWidget {
  final String initialTheme; // system | light | dark
  const TaskApp({super.key, required this.initialTheme});

  @override
  State<TaskApp> createState() => _TaskAppState();
}

class _TaskAppState extends State<TaskApp> {
  late String themeKey = widget.initialTheme;

  ThemeMode get _mode => themeKey == 'dark'
      ? ThemeMode.dark
      : themeKey == 'light'
      ? ThemeMode.light
      : ThemeMode.system;

  Future<void> _setTheme(String key) async {
    setState(() => themeKey = key);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', key);
  }

  ThemeData _theme(Brightness b) {
    final isDark = b == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brown,
      brightness: b,
    ).copyWith(
      primary: isDark ? const Color(0xFFE0B98F) : AppColors.brown,
      onPrimary: isDark ? const Color(0xFF2B1D10) : Colors.white,
      secondaryContainer:
      isDark ? const Color(0xFF4A3A2E) : const Color(0xFFEBD9C3),
      onSecondaryContainer: isDark ? const Color(0xFFF1DFC8) : AppColors.deepBrown,
      surface: isDark ? const Color(0xFF2E241E) : const Color(0xFFFFFCF7),
      onSurface: isDark ? const Color(0xFFF3E9DC) : AppColors.deepBrown,
      error: const Color(0xFFC0594A),
    );
    final border = isDark ? const Color(0xFF4A3A2E) : const Color(0xFFEADBC6);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF3A2D25) : const Color(0xFFF6EDE0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF2E241E) : const Color(0xFFFFFCF7),
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerColor: border,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaskNest',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _mode,
      home: HomePage(themeKey: themeKey, onThemeChanged: _setTheme),
    );
  }
}

// --------------------------- HOME ---------------------------

class HomePage extends StatefulWidget {
  final String themeKey;
  final ValueChanged<String> onThemeChanged;
  const HomePage(
      {super.key, required this.themeKey, required this.onThemeChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final List<Task> _tasks = [];
  Timer? _timer;
  String _day = ymd(DateTime.now());
  bool _searching = false;
  final TextEditingController _searchC = TextEditingController();
  final Set<Task> _expanded = {};
  bool _loaded = false;
  int _tab = 0; // 0 Today, 1 Repeated, 2 Completed, 3 All
  String? _category; // null = all categories

  static const _tabs = [
    (Icons.today_outlined, Icons.today, 'Today'),
    (Icons.repeat, Icons.repeat_on, 'Repeated'),
    (Icons.check_circle_outline, Icons.check_circle, 'Completed'),
    (Icons.view_list_outlined, Icons.view_list, 'All'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Refresh every 30 seconds so overdue status and the day change stay current.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchC.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  Future<void> _tick() async {
    if (!mounted || !_loaded) return;
    if (ymd(DateTime.now()) != _day) {
      await _load(); // new day: reset subtasks and reschedule reminders
    } else {
      setState(() {});
    }
  }

  Future<void> _load() async {
    final list = await TaskDb.loadAll();
    final today = ymd(DateTime.now());
    _day = today;
    for (final t in list) {
      // Repeating tasks: subtasks are reset automatically every new day.
      if (t.repeats && t.subReset != today) {
        for (final s in t.subtasks) {
          s.done = false;
        }
        t.subReset = today;
        await TaskDb.save(t);
      }
      await NotificationService().schedule(t);
    }
    if (!mounted) return;
    setState(() {
      _tasks
        ..clear()
        ..addAll(list);
      _loaded = true;
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- filtering ----------
  int _minutes(Task t) => t.due.hour * 60 + t.due.minute;

  List<Task> _visible() {
    final now = DateTime.now();
    final list = _tasks.where((t) {
      if (_category != null && t.category != _category) return false;
      final q = _searchC.text.trim().toLowerCase();
      if (_searching && q.isNotEmpty) {
        if (!t.title.toLowerCase().contains(q) &&
            !t.description.toLowerCase().contains(q)) {
          return false;
        }
      }
      switch (_tab) {
        case 0:
          return !t.isDone && (t.activeOn(now) || t.isOverdue);
        case 1:
          return t.repeats;
        case 2:
          return t.isDone;
        default:
          return true;
      }
    }).toList();
    list.sort((a, b) {
      if (_tab == 0) {
        int key(Task t) => t.isOverdue
            ? t.due.millisecondsSinceEpoch - 100000000000000
            : _minutes(t);
        return key(a).compareTo(key(b));
      }
      if (a.repeats && b.repeats) return _minutes(a) - _minutes(b);
      return a.due.compareTo(b.due);
    });
    return list;
  }

  // ---------- actions ----------
  Future<void> _persist(Task t) async {
    await TaskDb.save(t);
    await NotificationService().schedule(t);
    if (mounted) setState(() {});
  }

  void _setDone(Task t, bool value) {
    if (t.repeats) {
      t.lastDone = value ? ymd(DateTime.now()) : null;
    } else {
      t.done = value;
    }
  }

  Future<void> _toggle(Task t) async {
    final value = !t.isDone;
    _setDone(t, value);
    for (final s in t.subtasks) {
      s.done = value;
    }
    await _persist(t);
    if (value) _snack('Marked as completed');
  }

  Future<void> _toggleSub(Task t, SubTask s) async {
    s.done = !s.done;
    if (t.subtasks.isNotEmpty) {
      _setDone(t, t.subtasks.every((x) => x.done));
    }
    await _persist(t);
  }

  Future<void> _delete(Task t) async {
    setState(() => _tasks.remove(t));
    await NotificationService().cancel(t);
    await TaskDb.delete(t);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Deleted "${t.title}"'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            t.id = null;
            setState(() => _tasks.add(t));
            await _persist(t);
          },
        ),
      ));
  }

  Future<void> _openEditor([Task? existing]) async {
    final result = await Navigator.push<EditorResult>(
      context,
      MaterialPageRoute(builder: (_) => TaskEditorPage(existing: existing)),
    );
    if (result == null) return;
    if (result.delete && existing != null) {
      await _delete(existing);
      return;
    }
    final task = result.task!;
    if (existing != null) {
      final i = _tasks.indexOf(existing);
      if (i >= 0) _tasks[i] = task;
    } else {
      _tasks.add(task);
    }
    await _persist(task);
    _snack(existing == null ? 'Task added' : 'Task updated');
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          themeKey: widget.themeKey,
          onThemeChanged: widget.onThemeChanged,
          onSoundChanged: () async {
            for (final t in _tasks) {
              await NotificationService().schedule(t);
            }
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  // ---------- export ----------
  String _csvCell(String s) => '"${s.replaceAll('"', '""')}"';

  String _statusOf(Task t) => t.isDone ? 'Completed' : 'Pending';

  String _dueText(Task t) {
    final time = DateFormat('h:mm a').format(t.due);
    if (t.repeats) return '${t.repeatText} at $time';
    final now = DateTime.now();
    if (ymd(t.due) == ymd(now)) return 'Today, $time';
    if (ymd(t.due) == ymd(now.add(const Duration(days: 1)))) {
      return 'Tomorrow, $time';
    }
    return DateFormat('d MMM yyyy, h:mm a').format(t.due);
  }

  Future<File> _makeCsv(Directory dir) async {
    final b = StringBuffer(
        'Title,Description,Category,Due,Repeat,Status,Progress\n');
    for (final t in _tasks) {
      b.writeln([
        _csvCell(t.title),
        _csvCell(t.description),
        _csvCell(t.category),
        _csvCell(_dueText(t)),
        _csvCell(t.repeats ? t.repeatText : 'No'),
        _csvCell(_statusOf(t)),
        '${(t.progress * 100).round()}%',
      ].join(','));
    }
    final f = File(p.join(dir.path, 'tasks.csv'));
    return f.writeAsString(b.toString());
  }

  Future<File> _makePdf(Directory dir) async {
    pw.Widget cell(String s, {bool bold = false}) => pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(s,
          style: pw.TextStyle(
              fontSize: 10,
              fontWeight:
              bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        pw.Header(level: 0, child: pw.Text('Task Report')),
        pw.Text(
            'Generated on ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}'),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(),
          children: [
            pw.TableRow(children: [
              cell('Title', bold: true),
              cell('Category', bold: true),
              cell('Due', bold: true),
              cell('Repeat', bold: true),
              cell('Status', bold: true),
              cell('Progress', bold: true),
            ]),
            ..._tasks.map((t) => pw.TableRow(children: [
              cell(t.title),
              cell(t.category),
              cell(_dueText(t)),
              cell(t.repeats ? t.repeatText : 'No'),
              cell(_statusOf(t)),
              cell('${(t.progress * 100).round()}%'),
            ])),
          ],
        ),
      ],
    ));
    final f = File(p.join(dir.path, 'tasks.pdf'));
    return f.writeAsBytes(await doc.save());
  }

  Future<void> _export(String kind) async {
    if (kIsWeb) {
      _snack('Export is available on the Android app.');
      return;
    }
    if (_tasks.isEmpty) {
      _snack('There are no tasks to export.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final files = <XFile>[];
    if (kind == 'csv' || kind == 'email') {
      files.add(XFile((await _makeCsv(dir)).path));
    }
    if (kind == 'pdf' || kind == 'email') {
      files.add(XFile((await _makePdf(dir)).path));
    }
    await Share.shareXFiles(files,
        subject: 'My Tasks', text: 'Task list exported from TaskNest.');
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final list = _visible();
    return Scaffold(
      body: GinghamBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _topBar(),
              if (!_loaded)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else ...[
                _summaryCard(),
                _categoryFilter(),
                Expanded(
                  child: list.isEmpty
                      ? _emptyState()
                      : ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 96),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _taskCard(list[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New task'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
                icon: Icon(t.$1), selectedIcon: Icon(t.$2), label: t.$3),
        ],
      ),
    );
  }

  Widget _topBar() {
    final cs = Theme.of(context).colorScheme;
    if (_searching) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchC,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    hintText: 'Search tasks', prefixIcon: Icon(Icons.search)),
              ),
            ),
            IconButton(
              tooltip: 'Close search',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _searching = false;
                _searchC.clear();
              }),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
      child: Row(
        children: [
          const BearFace(size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6))),
                const SizedBox(height: 2),
                Text(_tabs[_tab].$3,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _searching = true),
          ),
          PopupMenuButton<String>(
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share_outlined),
            onSelected: _export,
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'csv',
                  child: ListTile(
                      leading: Icon(Icons.table_chart_outlined),
                      title: Text('Export as CSV'))),
              PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                      leading: Icon(Icons.picture_as_pdf_outlined),
                      title: Text('Export as PDF'))),
              PopupMenuItem(
                  value: 'email',
                  child: ListTile(
                      leading: Icon(Icons.email_outlined),
                      title: Text('Share via email'))),
            ],
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  Widget _summaryCard() {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todays = _tasks.where((t) => t.activeOn(now)).toList();
    final doneToday = todays.where((t) => t.isDone).length;
    final overdue = _tasks.where((t) => t.isOverdue).length;
    final remaining = todays.length - doneToday;
    final value = todays.isEmpty ? 0.0 : doneToday / todays.length;
    final onGrad = Colors.white;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, const Color(0xFFB98B66)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: value,
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                Text('${(value * 100).round()}%',
                    style: TextStyle(
                        color: onGrad,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  todays.isEmpty
                      ? 'Nothing planned for today'
                      : '$doneToday of ${todays.length} done today',
                  style: TextStyle(
                      color: onGrad,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  (remaining > 0 || overdue > 0)
                      ? [
                    if (remaining > 0) '$remaining remaining',
                    if (overdue > 0) '$overdue overdue',
                  ].join('  -  ')
                      : (todays.isEmpty
                      ? 'Enjoy your free day'
                      : 'All done for today'),
                  style: TextStyle(
                      color: onGrad.withValues(alpha: 0.85), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryFilter() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: _category == null,
              onSelected: (_) => setState(() => _category = null),
            ),
          ),
          for (final c in kCategories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(c.icon, size: 16, color: c.color),
                label: Text(c.name),
                selected: _category == c.name,
                onSelected: (v) => setState(() => _category = v ? c.name : null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    const messages = [
      ('No tasks for today', 'Tap "New task" to plan your day.'),
      ('No repeating tasks',
      'Create a task and set it to repeat daily or on selected days.'),
      ('Nothing completed yet', 'Completed tasks will appear here.'),
      ('No tasks yet', 'Tap "New task" to get started.'),
    ];
    final searchMiss = _searching && _searchC.text.trim().isNotEmpty;
    final m = searchMiss
        ? ('No matching tasks', 'Try a different search word.')
        : messages[_tab];
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BearFace(size: 96),
            const SizedBox(height: 16),
            Text(m.$1,
                style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(m.$2,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _taskCard(Task t) {
    final cs = Theme.of(context).colorScheme;
    final cat = categoryOf(t.category);
    final overdue = t.isOverdue;
    final pct = (t.progress * 100).round();
    final doneSubs = t.subtasks.where((s) => s.done).length;
    final open = _expanded.contains(t);
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Dismissible(
      key: ObjectKey(t),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.only(right: 24),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
            color: cs.error, borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _delete(t),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openEditor(t),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: t.isDone,
                      shape: const CircleBorder(),
                      onChanged: (_) => _toggle(t),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                decoration: t.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: t.isDone ? muted : null,
                              ),
                            ),
                            if (t.description.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(t.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: muted)),
                              ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _pill(cat.icon, cat.name, cat.color),
                                _pill(
                                    t.repeats ? Icons.repeat : Icons.schedule,
                                    overdue
                                        ? 'Overdue - ${_dueText(t)}'
                                        : _dueText(t),
                                    overdue ? cs.error : cs.primary),
                                if (t.reminder)
                                  _pill(
                                      Icons.notifications_active_outlined,
                                      t.remindBefore > 0
                                          ? '${NotificationService.beforeLabel(t.remindBefore)} before'
                                          : 'At due time',
                                      muted),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (t.subtasks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 0, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                                value: t.progress, minHeight: 8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('$doneSubs/${t.subtasks.length}  ($pct%)',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12)),
                        InkResponse(
                          onTap: () => setState(() =>
                          open ? _expanded.remove(t) : _expanded.add(t)),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                                open ? Icons.expand_less : Icons.expand_more),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (open)
                    ...t.subtasks.map((s) => InkWell(
                      onTap: () => _toggleSub(t, s),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 6, 0, 2),
                        child: Row(
                          children: [
                            Icon(
                                s.done
                                    ? Icons.check_box
                                    : Icons.check_box_outline_blank,
                                size: 20,
                                color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(s.title,
                                  style: TextStyle(
                                      decoration: s.done
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: s.done ? muted : null)),
                            ),
                          ],
                        ),
                      ),
                    )),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------ TASK EDITOR -----------------------

class EditorResult {
  final Task? task;
  final bool delete;
  const EditorResult({this.task, this.delete = false});
}

class TaskEditorPage extends StatefulWidget {
  final Task? existing;
  const TaskEditorPage({super.key, this.existing});

  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleC;
  late final TextEditingController _descC;
  final _subC = TextEditingController();
  late DateTime _due;
  late int _repeatType;
  late Set<int> _days;
  late bool _reminder;
  late String _category;
  late int _remindBefore;
  late List<SubTask> _subs;
  bool _daysError = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleC = TextEditingController(text: e?.title ?? '');
    _descC = TextEditingController(text: e?.description ?? '');
    _due = e?.due ?? DateTime.now().add(const Duration(hours: 1));
    _repeatType = e?.repeatType ?? 0;
    _days = {...?e?.repeatDays};
    _reminder = e?.reminder ?? true;
    _category = e?.category ?? 'Personal';
    _remindBefore = e?.remindBefore ?? 5;
    _subs = (e?.subtasks ?? []).map((s) => SubTask(s.title, s.done)).toList();
  }

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    _subC.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (d != null) {
      setState(() =>
      _due = DateTime(d.year, d.month, d.day, _due.hour, _due.minute));
    }
  }

  Future<void> _pickTime() async {
    final tm = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_due));
    if (tm != null) {
      setState(() => _due =
          DateTime(_due.year, _due.month, _due.day, tm.hour, tm.minute));
    }
  }

  void _addSub() {
    final s = _subC.text.trim();
    if (s.isEmpty) return;
    setState(() => _subs.add(SubTask(s)));
    _subC.clear();
  }

  void _save() {
    final okForm = _formKey.currentState!.validate();
    final okDays = !(_repeatType == 2 && _days.isEmpty);
    setState(() => _daysError = !okDays);
    if (!okForm || !okDays) return;
    _addSub(); // include a subtask that was typed but not added yet
    final e = widget.existing;
    final task = Task(
      id: e?.id,
      title: _titleC.text.trim(),
      description: _descC.text.trim(),
      category: _category,
      due: _due,
      repeatType: _repeatType,
      repeatDays: _repeatType == 2 ? {..._days} : <int>{},
      done: e?.done ?? false,
      lastDone: e?.lastDone,
      reminder: _reminder,
      remindBefore: _remindBefore,
      subReset: ymd(DateTime.now()),
      subtasks: _subs,
    );
    Navigator.pop(context, EditorResult(task: task));
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: const Text('This task will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.pop(context, const EditorResult(delete: true));
    }
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit task' : 'New task'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: GinghamBackground(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            children: [
              _section('DETAILS', [
                TextFormField(
                  controller: _titleC,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Title', prefixIcon: Icon(Icons.edit_outlined)),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Please enter a title'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descC,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      prefixIcon: Icon(Icons.notes_outlined)),
                ),
                const SizedBox(height: 14),
                const Text('Category',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final c in kCategories)
                      ChoiceChip(
                        avatar: Icon(c.icon, size: 16, color: c.color),
                        label: Text(c.name),
                        selected: _category == c.name,
                        onSelected: (_) => setState(() => _category = c.name),
                      ),
                  ],
                ),
              ]),
              _section('SCHEDULE', [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Once')),
                    ButtonSegment(value: 1, label: Text('Daily')),
                    ButtonSegment(value: 2, label: Text('Weekly days')),
                  ],
                  selected: {_repeatType},
                  onSelectionChanged: (s) => setState(() {
                    _repeatType = s.first;
                    _daysError = false;
                    if (_repeatType != 0 && _remindBefore > 60) {
                      _remindBefore = 60;
                    }
                  }),
                ),
                const SizedBox(height: 12),
                if (_repeatType == 2) ...[
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (i) {
                      final d = i + 1;
                      return FilterChip(
                        label: Text(kDayNames[i]),
                        selected: _days.contains(d),
                        onSelected: (v) => setState(() {
                          v ? _days.add(d) : _days.remove(d);
                          _daysError = false;
                        }),
                      );
                    }),
                  ),
                  if (_daysError)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Select at least one day',
                          style: TextStyle(color: cs.error, fontSize: 12)),
                    ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    if (_repeatType == 0) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.event_outlined),
                          label: Text(DateFormat('d MMM yyyy').format(_due)),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickTime,
                        icon: const Icon(Icons.schedule),
                        label: Text(DateFormat('h:mm a').format(_due)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remind me'),
                  subtitle: const Text('Notify me when the task is due'),
                  value: _reminder,
                  onChanged: (v) => setState(() => _reminder = v),
                ),
                if (_reminder) ...[
                  const SizedBox(height: 4),
                  Text('Also send an early reminder:',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.6),
                          fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final v in kRemindOptions)
                        if (_repeatType == 0 || v <= 60)
                          ChoiceChip(
                            label: Text(v == 0
                                ? 'No early reminder'
                                : '${NotificationService.beforeLabel(v)} before'),
                            selected: _remindBefore == v,
                            onSelected: (_) =>
                                setState(() => _remindBefore = v),
                          ),
                    ],
                  ),
                ],
              ]),
              _section('SUBTASKS', [
                if (_subs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Break the task into smaller steps to track progress.',
                        style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.6))),
                  ),
                ...List.generate(
                  _subs.length,
                      (i) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.subdirectory_arrow_right),
                    title: Text(_subs[i].title),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _subs.removeAt(i)),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _subC,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _addSub(),
                        decoration:
                        const InputDecoration(hintText: 'Add a subtask'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: 'Add subtask',
                      onPressed: _addSub,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ]),
            ],
          ),
        ),
      ),
      bottomSheet: Container(
        color: cs.surface,
        padding: EdgeInsets.fromLTRB(
            16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton.icon(
            icon: const Icon(Icons.check),
            label: Text(_isEdit ? 'Save changes' : 'Add task'),
            onPressed: _save,
          ),
        ),
      ),
    );
  }
}

// ------------------------- SETTINGS -------------------------

class SettingsPage extends StatefulWidget {
  final String themeKey;
  final ValueChanged<String> onThemeChanged;
  final Future<void> Function() onSoundChanged;
  const SettingsPage({
    super.key,
    required this.themeKey,
    required this.onThemeChanged,
    required this.onSoundChanged,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _theme = widget.themeKey;

  static const _sounds = {
    'default': 'Default notification',
    'alarm': 'Alarm',
    'ringtone': 'Ringtone',
    'silent': 'Silent',
  };

  Future<void> _setSound(String key) async {
    NotificationService.soundKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sound', key);
    await widget.onSoundChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: GinghamBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('APPEARANCE',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'system',
                              icon: Icon(Icons.brightness_auto),
                              label: Text('System')),
                          ButtonSegment(
                              value: 'light',
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Light')),
                          ButtonSegment(
                              value: 'dark',
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Dark')),
                        ],
                        selected: {_theme},
                        onSelectionChanged: (s) {
                          setState(() => _theme = s.first);
                          widget.onThemeChanged(s.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NOTIFICATION SOUND',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
                    const SizedBox(height: 4),
                    ..._sounds.entries.map((e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.value),
                      trailing: NotificationService.soundKey == e.key
                          ? Icon(Icons.check_circle, color: cs.primary)
                          : const Icon(Icons.circle_outlined),
                      onTap: () => _setSound(e.key),
                    )),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play test notification'),
                      onPressed: () {
                        if (kIsWeb) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Notifications are available on Android.')));
                        } else {
                          NotificationService().showNow();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: Icon(Icons.info_outline, color: cs.primary),
                title: const Text('TaskNest'),
                subtitle: const Text('Version 1.0.0  -  Flutter, SQLite'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
