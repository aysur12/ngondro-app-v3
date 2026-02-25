import '../core/constants/app_constants.dart';

/// Фазы простирания
enum ProstrationPhase {
  calibrating, // Идёт калибровка — человек стоит неподвижно
  calibrationComplete, // Калибровка завершена, воспроизводится аудио
  standing, // Стоит прямо (верхняя точка)
  goingDown, // Опускается
  prostrated, // Внизу (лёжа на полу)
  gettingUp, // Поднимается
}

/// Источник точки тела, используемой для отслеживания
enum BodyTrackingSource {
  shoulders, // Плечи (основной)
  hips, // Бёдра (fallback)
  lastKnown, // Последнее известное положение (temporal smoothing)
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

  /// Нормализованная Y-позиция "стоячего" положения (Точка X, после калибровки)
  final double? standingY;

  /// Источник точки, по которой идёт отслеживание
  final BodyTrackingSource source;

  /// Прогресс калибровки (0.0..1.0) — сколько прошло из 5 секунд
  final double calibrationProgress;

  const HeadInfo({
    this.normalizedX,
    this.normalizedY,
    required this.confidence,
    required this.phase,
    this.standingY,
    this.source = BodyTrackingSource.none,
    this.calibrationProgress = 0.0,
  });

  bool get isDetected => normalizedX != null && normalizedY != null;
}

/// Результат анализа позы
class PoseAnalysisResult {
  /// Простирание засчитано
  final bool prostrationCompleted;

  /// Калибровка только что завершилась (нужно воспроизвести аудио)
  final bool calibrationJustCompleted;

  const PoseAnalysisResult({
    this.prostrationCompleted = false,
    this.calibrationJustCompleted = false,
  });
}

/// Классификатор простираний.
/// Новая логика:
/// 1. Калибровка: 5 секунд стабильности плеч → запоминаем Точку X
/// 2. Temporal smoothing: при потере плеч используем последнее известное Y
/// 3. Простирание: Y вернулся в пределах headUpThreshold от Точки X
class ProstrationClassifier {
  ProstrationPhase _currentPhase = ProstrationPhase.calibrating;

  // Калибровка
  DateTime? _calibrationStableStart; // Когда начался неподвижный период
  double? _calibrationReferenceY; // Y при начале неподвижного периода
  double? _standingY; // Точка X — окончательная стоячая позиция

  // Temporal smoothing — последнее известное положение плеч
  double? _lastKnownY;
  double? _lastKnownX;

  // Защита от двойного засчитывания
  DateTime? _lastProstrationTime;

  ProstrationPhase get currentPhase => _currentPhase;
  double? get standingY => _standingY;
  bool get isCalibrated => _standingY != null;

  /// Вызывается извне когда воспроизведение calibration-end.mp3 завершилось.
  /// После этого начинается фаза standing.
  void onCalibrationAudioFinished() {
    if (_currentPhase == ProstrationPhase.calibrationComplete) {
      _currentPhase = ProstrationPhase.standing;
    }
  }

  /// Анализирует список точек (17 точек MoveNet).
  /// Возвращает [PoseAnalysisResult].
  PoseAnalysisResult analyzeLandmarks(List<PoseLandmark> landmarks) {
    // Пробуем получить реальное положение плеч/бёдер
    final detected = _detectBodyPosition(landmarks);

    // Обновляем temporal smoothing
    if (detected != null) {
      _lastKnownY = detected.y;
      _lastKnownX = detected.x;
    }

    // Определяем Y для анализа
    final double bodyY;

    if (detected != null) {
      bodyY = detected.y;
    } else if (_lastKnownY != null) {
      // Temporal smoothing: используем последнее известное положение
      bodyY = _lastKnownY!;
    } else {
      // Нет данных вообще
      return const PoseAnalysisResult();
    }

    // --- Калибровка ---
    if (_currentPhase == ProstrationPhase.calibrating) {
      return _handleCalibration(bodyY);
    }

    // Ждём окончания аудио
    if (_currentPhase == ProstrationPhase.calibrationComplete) {
      return const PoseAnalysisResult();
    }

    final standingY = _standingY;
    if (standingY == null) return const PoseAnalysisResult();

    // Насколько точка опустилась ниже Точки X
    final dropFromStanding = bodyY - standingY;

    return _updatePhase(dropFromStanding);
  }

  /// Обрабатывает калибровочную фазу.
  /// Проверяет стабильность Y в течение 5 секунд.
  PoseAnalysisResult _handleCalibration(double bodyY) {
    final now = DateTime.now();

    if (_calibrationReferenceY == null) {
      // Первое определение — запоминаем стартовую Y
      _calibrationReferenceY = bodyY;
      _calibrationStableStart = now;
      return const PoseAnalysisResult();
    }

    final delta = (bodyY - _calibrationReferenceY!).abs();

    if (delta > AppConstants.calibrationMovementThreshold) {
      // Человек двинулся — сбрасываем таймер
      _calibrationReferenceY = bodyY;
      _calibrationStableStart = now;
      return const PoseAnalysisResult();
    }

    // Человек стоит неподвижно — проверяем время
    final stableDuration =
        now.difference(_calibrationStableStart!).inMilliseconds / 1000.0;

    if (stableDuration >= AppConstants.calibrationDurationSeconds) {
      // 5 секунд выдержано — фиксируем Точку X
      _standingY = bodyY;
      _currentPhase = ProstrationPhase.calibrationComplete;
      return const PoseAnalysisResult(calibrationJustCompleted: true);
    }

    return const PoseAnalysisResult();
  }

  /// Обновляет фазу на основе текущего опускания от Точки X.
  PoseAnalysisResult _updatePhase(double dropFromStanding) {
    switch (_currentPhase) {
      case ProstrationPhase.calibrating:
      case ProstrationPhase.calibrationComplete:
        break;

      case ProstrationPhase.standing:
        if (dropFromStanding > AppConstants.headDownThreshold) {
          _currentPhase = ProstrationPhase.goingDown;
        }
        break;

      case ProstrationPhase.goingDown:
        if (dropFromStanding > AppConstants.headDownThreshold * 1.5) {
          _currentPhase = ProstrationPhase.prostrated;
        } else if (dropFromStanding < AppConstants.headUpThreshold) {
          _currentPhase = ProstrationPhase.standing;
        }
        break;

      case ProstrationPhase.prostrated:
        if (dropFromStanding < AppConstants.headDownThreshold) {
          _currentPhase = ProstrationPhase.gettingUp;
        }
        break;

      case ProstrationPhase.gettingUp:
        if (dropFromStanding < AppConstants.headUpThreshold) {
          // Вернулся к Точке X — простирание засчитано!
          _currentPhase = ProstrationPhase.standing;

          final now = DateTime.now();
          if (_lastProstrationTime == null ||
              now.difference(_lastProstrationTime!).inMilliseconds >
                  AppConstants.prostrationCooldownMs) {
            _lastProstrationTime = now;
            return const PoseAnalysisResult(prostrationCompleted: true);
          }
        } else if (dropFromStanding > AppConstants.headDownThreshold * 1.5) {
          _currentPhase = ProstrationPhase.prostrated;
        }
        break;
    }

    return const PoseAnalysisResult();
  }

  /// Пытается определить Y/X тела из реальных landmarks.
  /// Возвращает null если ни плечи ни бёдра не видны.
  _DetectedPoint? _detectBodyPosition(List<PoseLandmark> landmarks) {
    if (landmarks.length < 17) return null;

    final leftShoulder = landmarks[MoveNetLandmark.leftShoulder];
    final rightShoulder = landmarks[MoveNetLandmark.rightShoulder];

    if (leftShoulder.score >= AppConstants.minPoseConfidence &&
        rightShoulder.score >= AppConstants.minPoseConfidence) {
      return _DetectedPoint(
        y: (leftShoulder.y + rightShoulder.y) / 2,
        x: (leftShoulder.x + rightShoulder.x) / 2,
        source: BodyTrackingSource.shoulders,
      );
    }

    final leftHip = landmarks[MoveNetLandmark.leftHip];
    final rightHip = landmarks[MoveNetLandmark.rightHip];

    if (leftHip.score >= AppConstants.minPoseConfidence &&
        rightHip.score >= AppConstants.minPoseConfidence) {
      return _DetectedPoint(
        y: (leftHip.y + rightHip.y) / 2,
        x: (leftHip.x + rightHip.x) / 2,
        source: BodyTrackingSource.hips,
      );
    }

    return null;
  }

  /// Получить текущую информацию о точке тела (для отображения)
  HeadInfo getLastHeadInfo(List<PoseLandmark> landmarks) {
    final detected = _detectBodyPosition(landmarks);

    // Прогресс калибровки
    double calibProgress = 0.0;
    if (_currentPhase == ProstrationPhase.calibrating &&
        _calibrationStableStart != null) {
      final elapsed =
          DateTime.now().difference(_calibrationStableStart!).inMilliseconds /
              1000.0;
      calibProgress =
          (elapsed / AppConstants.calibrationDurationSeconds).clamp(0.0, 1.0);
    } else if (_currentPhase != ProstrationPhase.calibrating) {
      calibProgress = 1.0;
    }

    if (detected != null) {
      final lShoulder = landmarks[MoveNetLandmark.leftShoulder];
      final rShoulder = landmarks[MoveNetLandmark.rightShoulder];
      final conf = detected.source == BodyTrackingSource.shoulders
          ? (lShoulder.score + rShoulder.score) / 2
          : (landmarks[MoveNetLandmark.leftHip].score +
                  landmarks[MoveNetLandmark.rightHip].score) /
              2;

      return HeadInfo(
        normalizedX: detected.x,
        normalizedY: detected.y,
        confidence: conf,
        phase: _currentPhase,
        standingY: _standingY,
        source: detected.source,
        calibrationProgress: calibProgress,
      );
    }

    // Temporal smoothing для отображения
    if (_lastKnownY != null && _lastKnownX != null) {
      return HeadInfo(
        normalizedX: _lastKnownX,
        normalizedY: _lastKnownY,
        confidence: 0.0,
        phase: _currentPhase,
        standingY: _standingY,
        source: BodyTrackingSource.lastKnown,
        calibrationProgress: calibProgress,
      );
    }

    return HeadInfo(
      confidence: 0.0,
      phase: _currentPhase,
      standingY: _standingY,
      source: BodyTrackingSource.none,
      calibrationProgress: calibProgress,
    );
  }

  /// Сброс состояния — начинаем калибровку заново
  void reset() {
    _currentPhase = ProstrationPhase.calibrating;
    _calibrationStableStart = null;
    _calibrationReferenceY = null;
    _standingY = null;
    _lastKnownY = null;
    _lastKnownX = null;
    _lastProstrationTime = null;
  }

  /// Сброс только счётчика — без перекалибровки
  void resetCounter() {
    _lastProstrationTime = null;
  }
}

/// Внутренний класс для хранения обнаруженной позиции тела
class _DetectedPoint {
  final double y;
  final double x;
  final BodyTrackingSource source;

  const _DetectedPoint(
      {required this.y, required this.x, required this.source});
}
