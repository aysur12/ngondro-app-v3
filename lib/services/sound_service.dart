import 'package:audioplayers/audioplayers.dart';
import '../core/constants/app_constants.dart';

/// Сервис для воспроизведения звуковых уведомлений
class SoundService {
  final AudioPlayer _audioPlayer = AudioPlayer();

  /// Воспроизводит звук колокольчика
  Future<void> playBell() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource(AppConstants.bellSoundPath));
    } catch (e) {
      // Не критично если звук не воспроизведётся
    }
  }

  /// Освобождает ресурсы
  Future<void> dispose() async {
    await _audioPlayer.dispose();
  }
}
