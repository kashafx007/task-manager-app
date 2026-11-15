/// User settings (theme + notification sound), saved with SharedPreferences.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A notification sound the user can pick.
///
/// [id] matches the file names `assets/sounds/<id>.wav` (used in Chrome and for
/// previews) and `android/app/src/main/res/raw/<id>.wav` (used by Android
/// notification channels). The special id `silent` disables sound.
class SoundOption {
  const SoundOption(this.id, this.label, this.emoji);
  final String id;
  final String label;
  final String emoji;
}

const List<SoundOption> kSounds = [
  SoundOption('chime', 'Chime', '🔔'),
  SoundOption('bell', 'Bell', '🛎️'),
  SoundOption('pop', 'Pop', '🫧'),
  SoundOption('alarm', 'Alarm', '⏰'),
  SoundOption('silent', 'Silent', '🔕'),
];

class SettingsController extends ChangeNotifier {
  static const _themeKey = 'theme_mode';
  static const _soundKey = 'sound_id';

  ThemeMode themeMode = ThemeMode.system;
  String soundId = 'chime';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeIndex = prefs.getInt(_themeKey);
      if (themeIndex != null && themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
        themeMode = ThemeMode.values[themeIndex];
      }
      final savedSound = prefs.getString(_soundKey);
      if (savedSound != null && kSounds.any((s) => s.id == savedSound)) {
        soundId = savedSound;
      }
    } catch (e) {
      debugPrint('Could not load settings: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeKey, mode.index);
    } catch (_) {}
  }

  Future<void> setSound(String id) async {
    soundId = id;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_soundKey, id);
    } catch (_) {}
  }
}
