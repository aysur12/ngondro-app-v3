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

/// Источник точки тела, используемой для отслеживания
enum BodyTrackingSource {
  shoulders, // Плечи (основной)
  hips, // Бёдра (fallback)
  none, // Не определено
}

/// Информация о положении тела для отображения
class HeadInfo {
  /// Нормализованные координаты отслеживаемой точки (0.0..1.0)
  final double? normalizedX;
  final double? normalizedY;

  /// Уверенность определения
  final double confidence;

  /// Текущая фаза простирания
  final ProstrationPhase phase;

  /// Нормализованная Y-позиция "стоячего" положения (после калибровки)
  final double? standingY;

  /// Источник точки, по которой идёт отслеживание
  final BodyTrackingSource source;

  const HeadInfo({
    this.normalizedX,
    this.normalizedY,
    required this.confidence,
    required this.phase,
    this.standingY,
    this.source = BodyTrackingSource.none,
  });

  bool get isDetected => normalizedX != null && normalizedY != null;
}

/// Классификатор простираний на основе отслеживания положения плеч/бёдер
class ProstrationClassifier {
  ProstrationPhase _currentPhase = ProstrationPhase.calibrating;

  // Калибровка: накапливаем Y-позиции в "стоячем" положении
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
    final bodyInfo = _extractBodyPosition(pose, imageWidth, imageHeight);
    if (!bodyInfo.isDetected) return false;

    final bodyY = bodyInfo.normalizedY!;

    // --- Калибровка ---
    if (_currentPhase == ProstrationPhase.calibrating) {
      _calibrationSamples.add(bodyY);
      if (_calibrationSamples.length >= AppConstants.calibrationFrames) {
        // Берём медиану для устойчивости к выбросам
        _calibrationSamples.sort();
        _standingY = _calibrationSamples[_calibrationSamples.length ~/ 2];
        _currentPhase = ProstrationPhase.standing;
      }
      return false;
    }

    if (_standingY == null) return false;

    // Насколько точка опустилась ниже стоячей позиции
    // (в нормализованных координатах, Y растёт вниз)
    final dropFromStanding = bodyY - _standingY!;

    switch (_currentPhase) {
      case ProstrationPhase.calibrating:
        break;

      case ProstrationPhase.standing:
        // Точка опустилась ниже порога — начало простирания
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

  /// Извлекает нормализованное положение тела из позы.
  /// Основная точка: плечи (среднее leftShoulder + rightShoulder).
  /// Fallback: бёдра (среднее leftHip + rightHip).
  HeadInfo _extractBodyPosition(
      Pose pose, double imageWidth, double imageHeight) {
    // Пробуем плечи
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

    if (leftShoulder != null &&
        rightShoulder != null &&
        leftShoulder.likelihood >= AppConstants.minPoseConfidence &&
        rightShoulder.likelihood >= AppConstants.minPoseConfidence) {
      return HeadInfo(
        normalizedX: (leftShoulder.x + rightShoulder.x) / 2 / imageWidth,
        normalizedY: (leftShoulder.y + rightShoulder.y) / 2 / imageHeight,
        confidence: (leftShoulder.likelihood + rightShoulder.likelihood) / 2,
        phase: _currentPhase,
        standingY: _standingY,
        source: BodyTrackingSource.shoulders,
      );
    }

    // Fallback: бёдра
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];

    if (leftHip != null &&
        rightHip != null &&
        leftHip.likelihood >= AppConstants.minPoseConfidence &&
        rightHip.likelihood >= AppConstants.minPoseConfidence) {
      return HeadInfo(
        normalizedX: (leftHip.x + rightHip.x) / 2 / imageWidth,
        normalizedY: (leftHip.y + rightHip.y) / 2 / imageHeight,
        confidence: (leftHip.likelihood + rightHip.likelihood) / 2,
        phase: _currentPhase,
        standingY: _standingY,
        source: BodyTrackingSource.hips,
      );
    }

    return HeadInfo(
      confidence: 0.0,
      phase: _currentPhase,
      standingY: _standingY,
      source: BodyTrackingSource.none,
    );
  }

  /// Получить текущую информацию о точке тела (для отображения)
  HeadInfo? getLastHeadInfo(Pose pose,
      {double imageWidth = 1.0, double imageHeight = 1.0}) {
    return _extractBodyPosition(pose, imageWidth, imageHeight);
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
