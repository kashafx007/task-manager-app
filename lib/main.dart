/// TaskNest - entry point.
///
/// Sets up the settings, notification service, SQLite database and task
/// controller, then starts the app with the light/dark themes.
library;

import 'package:flutter/material.dart';

import 'data/task_database.dart';
import 'logic/settings_controller.dart';
import 'logic/task_controller.dart';
import 'services/notification_service.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

/// Lets non-UI code (reminders) show an in-app alert.
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = SettingsController();
  await settings.load();

  final notifications = NotificationService(settings);
  await notifications.init();


  final controller = TaskController(TaskDatabase(), notifications);

  runApp(TaskNestApp(
    settings: settings,
    controller: controller,
    notifications: notifications,
  ));
}

class TaskNestApp extends StatelessWidget {
  const TaskNestApp({
    super.key,
    required this.settings,
    required this.controller,
    required this.notifications,
  });

  final SettingsController settings;
  final TaskController controller;
  final NotificationService notifications;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'TaskNest',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: messengerKey,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: settings.themeMode,
          home: HomePage(
            controller: controller,
            settings: settings,
            notifications: notifications,
          ),
        );
      },
    );
  }
}
