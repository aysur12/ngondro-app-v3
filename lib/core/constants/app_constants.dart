class AppConstants {
  // Bell sound trigger interval
  static const int bellInterval = 100;

  // SharedPreferences keys
  static const String keyTotalCount = 'total_count';
  static const String keySessionCount = 'session_count';
  static const String keyLastSessionDate = 'last_session_date';

  // Sound asset path
  static const String bellSoundPath = 'sounds/bell.mp3';

  // Head tracking thresholds (normalized 0.0..1.0, Y-axis: 0=top, 1=bottom)
  // Порог опускания головы: если голова опустилась на X% от высоты кадра ниже
  // стоячей позиции — считаем что человек начал простирание
  static const double headDownThreshold = 0.25;

  // Порог возврата: голова должна вернуться в пределах X% от стоячей позиции
  static const double headUpThreshold = 0.10;

  // Количество кадров для автокалибровки стоячей позиции
  static const int calibrationFrames = 30;

  // Время между засчитыванием простираний (мс) — защита от дублей
  static const int prostrationCooldownMs = 1500;

  // Минимальный уровень уверенности для точек позы
  static const double minPoseConfidence = 0.5;

  // Размер квадрата вокруг головы (в долях от ширины изображения)
  static const double headBoxSize = 0.15;

  // Legacy pose detection thresholds (degrees) — больше не используются
  static const double standingAngleThreshold = 30.0;
  static const double goingDownAngleThreshold = 70.0;
  static const double gettingUpAngleThreshold = 60.0;
}
