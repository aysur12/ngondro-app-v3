class AppConstants {
  // Bell sound trigger interval
  static const int bellInterval = 100;

  // SharedPreferences keys
  static const String keyTotalCount = 'total_count';
  static const String keySessionCount = 'session_count';
  static const String keyLastSessionDate = 'last_session_date';

  // Sound asset path
  static const String bellSoundPath = 'sounds/bell.mp3';

  // Pose detection thresholds (degrees)
  static const double standingAngleThreshold = 30.0;
  static const double goingDownAngleThreshold = 70.0;
  static const double gettingUpAngleThreshold = 60.0;

  // Minimum pose confidence
  static const double minPoseConfidence = 0.5;
}
