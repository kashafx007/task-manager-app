// Used on Android / iOS, where browser notifications do not exist.

String webNotificationPermission() => 'unsupported';

Future<String> requestWebNotificationPermission() async => 'unsupported';

void showWebNotification(String title, String body) {}
