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

/// Индексы ключевых точек MoveNet (17 точек COCO-формата)
class MoveNetLandmark {
  static const int nose = 0;
  static const int leftEye = 1;
  static const int rightEye = 2;
  static const int leftEar = 3;
  static const int rightEar = 4;
  static const int leftShoulder = 5;
  static const int rightShoulder = 6;
  static const int leftElbow = 7;
  static const int rightElbow = 8;
  static const int leftWrist = 9;
  static const int rightWrist = 10;
  static const int leftHip = 11;
  static const int rightHip = 12;
  static const int leftKnee = 13;
  static const int rightKnee = 14;
  static const int leftAnkle = 15;
  static const int rightAnkle = 16;
}

/// Одна ключевая точка тела из MoveNet
class PoseLandmark {
  /// Нормализованная Y (0.0 = верх, 1.0 = низ)
  final double y;

  /// Нормализованная X (0.0 = левый край, 1.0 = правый)
  final double x;

  /// Уверенность (0.0..1.0)
  final double score;

  const PoseLandmark({required this.y, required this.x, required this.score});
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

  /// Анализирует список точек (17 точек MoveNet) и возвращает true если
  /// простирание завершено.
  /// [landmarks] — список из 17 точек [PoseLandmark].
  bool analyzeLandmarks(List<PoseLandmark> landmarks) {
    final bodyInfo = _extractBodyPosition(landmarks);
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

  /// Извлекает нормализованное положение тела из списка точек MoveNet.
  /// Основная точка: плечи (среднее leftShoulder + rightShoulder).
  /// Fallback: бёдра (среднее leftHip + rightHip).
  HeadInfo _extractBodyPosition(List<PoseLandmark> landmarks) {
    if (landmarks.length < 17) {
      return HeadInfo(
        confidence: 0.0,
        phase: _currentPhase,
        standingY: _standingY,
        source: BodyTrackingSource.none,
      );
    }

    // Пробуем плечи
    final leftShoulder = landmarks[MoveNetLandmark.leftShoulder];
    final rightShoulder = landmarks[MoveNetLandmark.rightShoulder];

    if (leftShoulder.score >= AppConstants.minPoseConfidence &&
        rightShoulder.score >= AppConstants.minPoseConfidence) {
      return HeadInfo(
        normalizedX: (leftShoulder.x + rightShoulder.x) / 2,
        normalizedY: (leftShoulder.y + rightShoulder.y) / 2,
        confidence: (leftShoulder.score + rightShoulder.score) / 2,
        phase: _currentPhase,
        standingY: _standingY,
        source: BodyTrackingSource.shoulders,
      );
    }

    // Fallback: бёдра
    final leftHip = landmarks[MoveNetLandmark.leftHip];
    final rightHip = landmarks[MoveNetLandmark.rightHip];

    if (leftHip.score >= AppConstants.minPoseConfidence &&
        rightHip.score >= AppConstants.minPoseConfidence) {
      return HeadInfo(
        normalizedX: (leftHip.x + rightHip.x) / 2,
        normalizedY: (leftHip.y + rightHip.y) / 2,
        confidence: (leftHip.score + rightHip.score) / 2,
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
  HeadInfo getLastHeadInfo(List<PoseLandmark> landmarks) {
    return _extractBodyPosition(landmarks);
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
