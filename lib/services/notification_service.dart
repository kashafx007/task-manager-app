/// Reminders for upcoming tasks.
///
/// * **Android** - real local notifications scheduled with
///   `flutter_local_notifications` (they fire even when the app is closed).
///   Every task gets one notification at its due time and, optionally, an early
///   reminder. Repeating tasks are scheduled for the next 14 days and the
///   schedule is refreshed every time the app starts or a task changes.
/// * **Chrome (web)** - browsers cannot schedule notifications for a closed
///   page, so while the TaskNest tab is open a timer in `TaskController`
///   calls [checkWebDue] every few seconds. When a reminder is due it shows a
///   browser notification, plays the chosen sound and shows an in-app alert.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../logic/settings_controller.dart';
import '../models/task.dart';
import '../utils/format_utils.dart';
import 'sound_service.dart';
import 'web_notifier_stub.dart' if (dart.library.js_interop) 'web_notifier_web.dart';

class NotificationService {
  NotificationService(this.settings);

  final SettingsController settings;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// Keys of reminders already shown in this browser session (web only).
  final Set<String> _fired = <String>{};

  /// Called whenever an alert should also be shown inside the app.
  void Function(String title, String body)? onAlert;

  // ------------------------------------------------------------------ setup

  Future<void> init() async {
    if (kIsWeb) return;
    try {
      tzdata.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: android));
      _ready = true;
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  /// Chrome permission state: `granted`, `denied`, `default` or `unsupported`.
  String get webPermission => kIsWeb ? webNotificationPermission() : 'n/a';

  /// Asks for notification permission. Returns true when granted.
  Future<bool> requestPermission() async {
    try {
      if (kIsWeb) {
        final result = await requestWebNotificationPermission();
        return result == 'granted';
      }
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return false;
      final granted = await android.requestNotificationsPermission();
      await android.requestExactAlarmsPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('Permission request failed: $e');
      return false;
    }
  }

  // -------------------------------------------------------- Android: schedule

  NotificationDetails _details(String soundId) {
    final silent = soundId == 'silent';
    return NotificationDetails(
      android: AndroidNotificationDetails(
        // Android fixes a channel's sound once created, so each sound gets
        // its own channel.
        'tasknest_$soundId',
        silent ? 'Task reminders (silent)' : 'Task reminders ($soundId)',
        channelDescription: 'Reminders for upcoming tasks',
        importance: Importance.max,
        priority: Priority.high,
        playSound: !silent,
        sound: silent ? null : RawResourceAndroidNotificationSound(soundId),
        enableVibration: true,
      ),
    );
  }

  Future<AndroidScheduleMode> _scheduleMode() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final canExact = await android?.canScheduleExactNotifications();
      if (canExact == true) return AndroidScheduleMode.exactAllowWhileIdle;
    } catch (_) {}
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  Future<void> _zoned(int id, String title, String body, DateTime when, AndroidScheduleMode mode) {
    // Scheduling with an absolute instant (UTC) means we do not need to know
    // the device's time-zone name.
    final scheduled = tz.TZDateTime.from(when, tz.UTC);
    return _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      _details(settings.soundId),
      androidScheduleMode: mode,
    );
  }

  /// Cancels every notification that belongs to a task.
  /// Notification ids are `taskId * 100 + slot` (slot 0..79).
  Future<void> cancelForTask(int taskId) async {
    if (kIsWeb || !_ready) return;
    try {
      for (var slot = 0; slot < 80; slot++) {
        await _plugin.cancel(taskId * 100 + slot);
      }
    } catch (e) {
      debugPrint('cancelForTask failed: $e');
    }
  }

  /// (Re)schedules the notifications of one task.
  Future<void> scheduleTask(Task t, {bool cancelFirst = true}) async {
    if (kIsWeb || !_ready || t.id == null) return;
    try {
      if (cancelFirst) await cancelForTask(t.id!);
      if (t.completed && !t.isRepeating) return;

      final now = DateTime.now();
      final occurrences = occurrencesBetween(t, now, now.add(const Duration(days: 14)));
      final mode = await _scheduleMode();

      var k = 0;
      for (final due in occurrences) {
        if (k >= 40) break;
        final base = t.id! * 100 + k * 2;
        if (due.isAfter(now)) {
          await _zoned(base + 1, _dueTitle, _dueBody(t, due), due, mode);
        }
        if (t.reminderMinutes > 0) {
          final early = due.subtract(Duration(minutes: t.reminderMinutes));
          if (early.isAfter(now)) {
            await _zoned(
              base,
              _earlyTitle,
              _earlyBody(t, due),
              early,
              mode,
            );
          }
        }
        k++;
      }
    } catch (e) {
      debugPrint('scheduleTask failed: $e');
    }
  }

  /// Rebuilds all scheduled notifications (called at start-up).
  Future<void> rescheduleAll(List<Task> tasks) async {
    if (kIsWeb || !_ready) return;
    try {
      await _plugin.cancelAll();
      for (final t in tasks) {
        await scheduleTask(t, cancelFirst: false);
      }
    } catch (e) {
      debugPrint('rescheduleAll failed: $e');
    }
  }

  // -------------------------------------------------------------- Chrome: poll

  /// Chrome only: shows reminders that are due right now. Called by a timer.
  void checkWebDue(List<Task> tasks) {
    if (!kIsWeb) return;
    final now = DateTime.now();
    const window = Duration(minutes: 5);

    for (final t in tasks) {
      if (t.id == null) continue;
      if (t.completed && !t.isRepeating) continue;

      final occurrences = occurrencesBetween(
        t,
        now.subtract(window),
        now.add(const Duration(days: 1)),
      );
      for (final due in occurrences) {
        // Reminder at the due time.
        final dueKey = '${t.id}|${due.millisecondsSinceEpoch}|due';
        if (!due.isAfter(now) && now.difference(due) < window && _fired.add(dueKey)) {
          _alertWeb(_dueTitle, _dueBody(t, due));
        }
        // Optional early reminder.
        if (t.reminderMinutes > 0) {
          final early = due.subtract(Duration(minutes: t.reminderMinutes));
          final earlyKey = '${t.id}|${due.millisecondsSinceEpoch}|early';
          if (!early.isAfter(now) &&
              now.isBefore(due) &&
              now.difference(early) < window &&
              _fired.add(earlyKey)) {
            _alertWeb(_earlyTitle, _earlyBody(t, due));
          }
        }
      }
    }
  }

  void _alertWeb(String title, String body) {
    if (webNotificationPermission() == 'granted') {
      showWebNotification(title, body);
    }
    SoundService.instance.play(settings.soundId);
    onAlert?.call(title, body);
  }

  // ---------------------------------------------------------------- messages

  static const String _dueTitle = 'Task Reminder';
  static const String _earlyTitle = 'Upcoming Task';

  /// "3:30 PM" for today, "20 Nov at 3:30 PM" for another day.
  String _whenText(DateTime due) => sameDay(due, DateTime.now())
      ? formatTime(due)
      : '${formatShortDate(due)} at ${formatTime(due)}';

  String _leadText(int minutes) {
    switch (minutes) {
      case 60:
        return 'in 1 hour';
      case 1440:
        return 'in 1 day';
      default:
        return 'in $minutes minutes';
    }
  }

  String _dueBody(Task t, DateTime due) =>
      'Your task "${t.title}" is scheduled for ${formatTime(due)}. '
          'Please complete or submit it on time.';

  String _earlyBody(Task t, DateTime due) =>
      'Your task "${t.title}" is due at ${_whenText(due)} '
          '(${_leadText(t.reminderMinutes)}). Please plan to complete it on time.';

  // -------------------------------------------------------------------- test

  /// Sends a test notification so the user can check sound and permissions.
  Future<void> showTest() async {
    if (kIsWeb) {
      _alertWeb('Test Notification', 'TaskNest reminders are enabled and working correctly.');
      return;
    }
    if (_ready) {
      try {
        await _plugin.show(
          999999999,
          'Test Notification',
          'TaskNest reminders are enabled and working correctly.',
          _details(settings.soundId),
        );
      } catch (e) {
        debugPrint('Test notification failed: $e');
      }
    }
    onAlert?.call('Test Notification', 'TaskNest reminders are enabled and working correctly.');
  }
}