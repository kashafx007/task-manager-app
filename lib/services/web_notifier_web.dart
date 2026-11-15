// Chrome implementation of notifications using the browser Notification API.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// `granted`, `denied`, `default` (not asked yet) or `unsupported`.
String webNotificationPermission() {
  try {
    return web.Notification.permission;
  } catch (_) {
    return 'unsupported';
  }
}

/// Shows Chrome's "Allow notifications?" prompt and returns the answer.
Future<String> requestWebNotificationPermission() async {
  try {
    final result = await web.Notification.requestPermission().toDart;
    return result.toDart;
  } catch (_) {
    return 'unsupported';
  }
}

void showWebNotification(String title, String body) {
  try {
    web.Notification(title, web.NotificationOptions(body: body, icon: 'icons/Icon-192.png'));
  } catch (_) {
    // Ignore: the in-app alert is still shown.
  }
}
