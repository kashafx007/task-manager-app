import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the bundled notification sounds (`assets/sounds/<id>.wav`).
///
/// Used for sound previews in Settings and for alerts while the app is open in
/// Chrome. On Android, real notifications use the sound of their notification
/// channel instead.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final AudioPlayer _player = AudioPlayer();

  Future<void> play(String soundId) async {
    if (soundId == 'silent') return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$soundId.wav'));
    } catch (e) {
      debugPrint('Could not play sound "$soundId": $e');
    }
  }
}
