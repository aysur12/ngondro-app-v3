import 'package:shared_preferences/shared_preferences.dart';
import 'package:ngondro_app/core/constants/app_constants.dart';
import 'package:ngondro_app/domain/entities/prostration_count.dart';

abstract class CounterLocalDataSource {
  Future<ProstrationCount> getCount();
  Future<void> saveCount(ProstrationCount count);
  Future<void> resetSession();
}

class CounterLocalDataSourceImpl implements CounterLocalDataSource {
  final SharedPreferences _prefs;

  const CounterLocalDataSourceImpl(this._prefs);

  @override
  Future<ProstrationCount> getCount() async {
    final totalCount = _prefs.getInt(AppConstants.keyTotalCount) ?? 0;
    final sessionCount = _prefs.getInt(AppConstants.keySessionCount) ?? 0;
    final lastSessionDate = _prefs.getString(AppConstants.keyLastSessionDate);

    return ProstrationCount(
      totalCount: totalCount,
      sessionCount: sessionCount,
      lastSessionDate: lastSessionDate,
    );
  }

  @override
  Future<void> saveCount(ProstrationCount count) async {
    await _prefs.setInt(AppConstants.keyTotalCount, count.totalCount);
    await _prefs.setInt(AppConstants.keySessionCount, count.sessionCount);
    if (count.lastSessionDate != null) {
      await _prefs.setString(
          AppConstants.keyLastSessionDate, count.lastSessionDate!);
    }
  }

  @override
  Future<void> resetSession() async {
    await _prefs.setInt(AppConstants.keySessionCount, 0);
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await _prefs.setString(AppConstants.keyLastSessionDate, dateStr);
  }
}
