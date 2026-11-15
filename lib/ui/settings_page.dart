/// Settings: theme (light / dark), notification sound and notification tools.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../logic/settings_controller.dart';
import '../services/notification_service.dart';
import '../services/sound_service.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings, required this.notifications});

  final SettingsController settings;
  final NotificationService notifications;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String get _permissionText {
    if (!kIsWeb) return 'Notifications are scheduled on this device.';
    switch (widget.notifications.webPermission) {
      case 'granted':
        return 'Chrome notifications are allowed.';
      case 'denied':
        return 'Chrome notifications are blocked. Click the lock icon in the address bar '
            'and allow notifications for this site.';
      case 'default':
        return 'Chrome has not been asked yet. Tap "Allow notifications".';
      default:
        return 'This browser does not support notifications.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return CutePage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Settings')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListenableBuilder(
              listenable: widget.settings,
              builder: (context, _) {
                final s = widget.settings;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    SectionCard(
                      title: 'Appearance',
                      child: SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                                value: ThemeMode.system,
                                icon: Icon(Icons.brightness_auto_rounded),
                                label: Text('Auto')),
                            ButtonSegment(
                                value: ThemeMode.light,
                                icon: Icon(Icons.light_mode_rounded),
                                label: Text('Light')),
                            ButtonSegment(
                                value: ThemeMode.dark,
                                icon: Icon(Icons.dark_mode_rounded),
                                label: Text('Dark')),
                          ],
                          selected: {s.themeMode},
                          onSelectionChanged: (set) => s.setThemeMode(set.first),
                        ),
                      ),
                    ),
                    SectionCard(
                      title: 'Notification sound',
                      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                      child: Column(
                        children: [
                          for (final option in kSounds)
                            ListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              leading:
                              Text(option.emoji, style: const TextStyle(fontSize: 22)),
                              title: Text(option.label,
                                  style: TextStyle(
                                    color: c.text,
                                    fontWeight: s.soundId == option.id
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  )),
                              trailing: s.soundId == option.id
                                  ? Icon(Icons.check_circle_rounded, color: c.primary)
                                  : Icon(Icons.circle_outlined, color: c.subtext),
                              onTap: () {
                                s.setSound(option.id);
                                SoundService.instance.play(option.id);
                              },
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                            child: Text(
                              'Tap a sound to preview it.',
                              style: TextStyle(color: c.subtext, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SectionCard(
                      title: 'Notifications',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_permissionText, style: TextStyle(color: c.subtext, height: 1.4)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              FilledButton.icon(
                                onPressed: () async {
                                  await widget.notifications.requestPermission();
                                  if (mounted) setState(() {});
                                },
                                icon: const Icon(Icons.notifications_active_rounded),
                                label: const Text('Allow notifications'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => widget.notifications.showTest(),
                                icon: const Icon(Icons.send_rounded),
                                label: const Text('Send test'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SectionCard(
                      title: 'About',
                      child: Text(
                        'TaskNest 1.0\nA cute task manager built with Flutter and SQLite.',
                        style: TextStyle(color: c.subtext, height: 1.5),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
