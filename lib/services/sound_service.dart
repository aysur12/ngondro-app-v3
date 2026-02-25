import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';

/// Сервис для воспроизведения звуковых уведомлений
class SoundService {
  final AudioPlayer _bellPlayer = AudioPlayer();
  final AudioPlayer _voicePlayer = AudioPlayer();

  /// Воспроизводит звук колокольчика
  Future<void> playBell() async {
    try {
      await _bellPlayer.stop();
      await _bellPlayer.play(AssetSource(AppConstants.bellSoundPath));
    } catch (e) {
      // Не критично если звук не воспроизведётся
    }
  }

  /// Воспроизводит голосовое сопровождение калибровки (шаг 1).
  /// Звук "Встаньте прямо и не двигайтесь 5 секунд".
  Future<void> playCalibrationStart() async {
    try {
      await _voicePlayer.stop();
      await _voicePlayer
          .play(AssetSource(AppConstants.calibrationStartSoundPath));
    } catch (e) {
      // Не критично
    }
  }

  /// Воспроизводит голосовое сопровождение завершения калибровки (шаг 2).
  /// Вызывает [onComplete] когда воспроизведение закончилось.
  Future<void> playCalibrationEnd({VoidCallback? onComplete}) async {
    try {
      await _voicePlayer.stop();

      // Подписываемся на событие завершения воспроизведения
      void listener(PlayerState state) {
        if (state == PlayerState.completed) {
          _voicePlayer.onPlayerStateChanged.drain();
          onComplete?.call();
        }
      }

      _voicePlayer.onPlayerStateChanged.listen(listener);
      await _voicePlayer
          .play(AssetSource(AppConstants.calibrationEndSoundPath));
    } catch (e) {
      // Если аудио не воспроизвелось — сразу вызываем колбэк
      onComplete?.call();
    }
  }

  /// Останавливает воспроизведение голосового сопровождения
  Future<void> stopVoice() async {
    try {
      await _voicePlayer.stop();
    } catch (e) {
      // Не критично
    }
  }

  /// Освобождает ресурсы
  Future<void> dispose() async {
    await _bellPlayer.dispose();
    await _voicePlayer.dispose();
  }
}
