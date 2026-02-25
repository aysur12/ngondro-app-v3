import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../core/constants/app_constants.dart';

/// Фазы простирания
enum ProstrationPhase {
  calibrating, // Идёт калибровка "стоячей" позиции
  standing, // Стоит прямо (верхняя точка)
  goingDown, // Опускается
  prostrated, // Внизу (голова на уровне пола)
  gettingUp, // Поднимается
}

/// Информация о положении головы для отображения
class HeadInfo {
  /// Нормализованные координаты центра головы (0.0..1.0)
  final double? normalizedX;
  final double? normalizedY;

  /// Уверенность определения
  final double confidence;

  /// Текущая фаза простирания
  final ProstrationPhase phase;

  /// Нормализованная Y-позиция "стоячего" положения (после калибровки)
  final double? standingY;

  const HeadInfo({
    this.normalizedX,
    this.normalizedY,
    required this.confidence,
    required this.phase,
    this.standingY,
  });

  bool get isDetected => normalizedX != null && normalizedY != null;
}

/// Классификатор простираний на основе отслеживания положения головы
class ProstrationClassifier {
  ProstrationPhase _currentPhase = ProstrationPhase.calibrating;

  // Калибровка: накапливаем Y-позиции головы в "стоячем" положении
  final List<double> _calibrationSamples = [];
  double? _standingY; // Нормализованная Y-позиция когда человек стоит

  // Защита от двойного засчитывания
  DateTime? _lastProstrationTime;

  ProstrationPhase get currentPhase => _currentPhase;
  double? get standingY => _standingY;
  bool get isCalibrated => _standingY != null;

  /// Анализирует позу и возвращает true если простирание завершено.
  /// [imageWidth] и [imageHeight] — размеры изображения в пикселях.
  bool analyzePose(Pose pose,
      {double imageWidth = 1.0, double imageHeight = 1.0}) {
    final headInfo = _extractHeadPosition(pose, imageWidth, imageHeight);
    if (!headInfo.isDetected) return false;

    final headY = headInfo.normalizedY!;

    // --- Калибровка ---
    if (_currentPhase == ProstrationPhase.calibrating) {
      _calibrationSamples.add(headY);
      if (_calibrationSamples.length >= AppConstants.calibrationFrames) {
        // Берём медиану для устойчивости к выбросам
        _calibrationSamples.sort();
        _standingY = _calibrationSamples[_calibrationSamples.length ~/ 2];
        _currentPhase = ProstrationPhase.standing;
      }
      return false;
    }

    if (_standingY == null) return false;

    // Насколько голова опустилась ниже стоячей позиции
    // (в нормализованных координатах, Y растёт вниз)
    final dropFromStanding = headY - _standingY!;

    switch (_currentPhase) {
      case ProstrationPhase.calibrating:
        break;

      case ProstrationPhase.standing:
        // Голова опустилась ниже порога — начало простирания
        if (dropFromStanding > AppConstants.headDownThreshold) {
          _currentPhase = ProstrationPhase.goingDown;
        }
        break;

      case ProstrationPhase.goingDown:
        if (dropFromStanding > AppConstants.headDownThreshold * 1.5) {
          // Опустился достаточно низко — засчитываем как простёртую позицию
          _currentPhase = ProstrationPhase.prostrated;
        } else if (dropFromStanding < AppConstants.headUpThreshold) {
          // Не успел опуститься — вернулся вверх
          _currentPhase = ProstrationPhase.standing;
        }
        break;

      case ProstrationPhase.prostrated:
        // Начал подниматься
        if (dropFromStanding < AppConstants.headDownThreshold) {
          _currentPhase = ProstrationPhase.gettingUp;
        }
        break;

      case ProstrationPhase.gettingUp:
        if (dropFromStanding < AppConstants.headUpThreshold) {
          // Вернулся в стоячую позицию — простирание засчитано!
          _currentPhase = ProstrationPhase.standing;

          // Проверяем кулдаун
          final now = DateTime.now();
          if (_lastProstrationTime == null ||
              now.difference(_lastProstrationTime!).inMilliseconds >
                  AppConstants.prostrationCooldownMs) {
            _lastProstrationTime = now;
            return true;
          }
        } else if (dropFromStanding > AppConstants.headDownThreshold * 1.5) {
          // Снова опустился
          _currentPhase = ProstrationPhase.prostrated;
        }
        break;
    }

    return false;
  }

  /// Извлекает нормализованное положение головы из позы.
  /// Использует нос как основную точку, fallback на уши.
  HeadInfo _extractHeadPosition(
      Pose pose, double imageWidth, double imageHeight) {
    // Пробуем нос
    final nose = pose.landmarks[PoseLandmarkType.nose];
    if (nose != null && nose.likelihood >= AppConstants.minPoseConfidence) {
      return HeadInfo(
        normalizedX: nose.x / imageWidth,
        normalizedY: nose.y / imageHeight,
        confidence: nose.likelihood,
        phase: _currentPhase,
        standingY: _standingY,
      );
    }

    // Fallback: среднее между ушами
    final leftEar = pose.landmarks[PoseLandmarkType.leftEar];
    final rightEar = pose.landmarks[PoseLandmarkType.rightEar];
    if (leftEar != null &&
        rightEar != null &&
        leftEar.likelihood >= AppConstants.minPoseConfidence &&
        rightEar.likelihood >= AppConstants.minPoseConfidence) {
      return HeadInfo(
        normalizedX: (leftEar.x + rightEar.x) / 2 / imageWidth,
        normalizedY: (leftEar.y + rightEar.y) / 2 / imageHeight,
        confidence: (leftEar.likelihood + rightEar.likelihood) / 2,
        phase: _currentPhase,
        standingY: _standingY,
      );
    }

    return HeadInfo(
      confidence: 0.0,
      phase: _currentPhase,
      standingY: _standingY,
    );
  }

  /// Получить текущую информацию о голове (для отображения)
  HeadInfo? getLastHeadInfo(Pose pose,
      {double imageWidth = 1.0, double imageHeight = 1.0}) {
    return _extractHeadPosition(pose, imageWidth, imageHeight);
  }

  /// Сброс состояния — начинаем калибровку заново
  void reset() {
    _currentPhase = ProstrationPhase.calibrating;
    _calibrationSamples.clear();
    _standingY = null;
    _lastProstrationTime = null;
  }

  /// Сброс только счётчика — без перекалибровки
  void resetCounter() {
    _lastProstrationTime = null;
  }
}
