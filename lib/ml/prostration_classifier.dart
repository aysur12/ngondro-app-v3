import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../core/constants/app_constants.dart';

/// Фазы простирания
enum ProstrationPhase {
  standing,
  goingDown,
  prostrated,
  gettingUp,
}

/// Классификатор простираний на основе конечного автомата
class ProstrationClassifier {
  ProstrationPhase _currentPhase = ProstrationPhase.standing;

  ProstrationPhase get currentPhase => _currentPhase;

  /// Анализирует позу и возвращает true если простирание завершено
  bool analyzePose(Pose pose) {
    final torsoAngle = _calculateTorsoAngle(pose);
    if (torsoAngle == null) return false;

    switch (_currentPhase) {
      case ProstrationPhase.standing:
        // Начинаем наклоняться
        if (torsoAngle > AppConstants.standingAngleThreshold) {
          _currentPhase = ProstrationPhase.goingDown;
        }
        break;

      case ProstrationPhase.goingDown:
        if (torsoAngle > AppConstants.goingDownAngleThreshold) {
          // Достигли горизонтали - простираемся
          _currentPhase = ProstrationPhase.prostrated;
        } else if (torsoAngle < AppConstants.standingAngleThreshold) {
          // Поднялись не до конца - сброс
          _currentPhase = ProstrationPhase.standing;
        }
        break;

      case ProstrationPhase.prostrated:
        if (torsoAngle < AppConstants.gettingUpAngleThreshold) {
          // Начинаем подниматься
          _currentPhase = ProstrationPhase.gettingUp;
        }
        break;

      case ProstrationPhase.gettingUp:
        if (torsoAngle < AppConstants.standingAngleThreshold) {
          // Полностью поднялись — простирание засчитано!
          _currentPhase = ProstrationPhase.standing;
          return true;
        } else if (torsoAngle > AppConstants.goingDownAngleThreshold) {
          // Снова наклонились
          _currentPhase = ProstrationPhase.prostrated;
        }
        break;
    }
    return false;
  }

  /// Сброс состояния классификатора
  void reset() {
    _currentPhase = ProstrationPhase.standing;
  }

  /// Вычисляет угол торса к вертикали в градусах
  double? _calculateTorsoAngle(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      return null;
    }

    // Проверяем уверенность определения ключевых точек
    if (leftShoulder.likelihood < AppConstants.minPoseConfidence ||
        rightShoulder.likelihood < AppConstants.minPoseConfidence ||
        leftHip.likelihood < AppConstants.minPoseConfidence ||
        rightHip.likelihood < AppConstants.minPoseConfidence) {
      return null;
    }

    // Центр плеч
    final shoulderMidX = (leftShoulder.x + rightShoulder.x) / 2;
    final shoulderMidY = (leftShoulder.y + rightShoulder.y) / 2;

    // Центр бёдер
    final hipMidX = (leftHip.x + rightHip.x) / 2;
    final hipMidY = (leftHip.y + rightHip.y) / 2;

    // Вектор торса (от бёдер к плечам)
    final dx = shoulderMidX - hipMidX;
    final dy = shoulderMidY - hipMidY;

    // Угол к вертикали (Y-ось направлена вниз в координатах изображения)
    // 0° = стоит прямо, 90° = лежит горизонтально
    final angleRad = math.atan2(dx.abs(), dy.abs());
    final angleDeg = angleRad * 180 / math.pi;

    return angleDeg;
  }
}
