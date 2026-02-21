import '../entities/prostration_count.dart';

abstract class ProstrationRepository {
  Future<ProstrationCount> getCount();
  Future<void> saveCount(ProstrationCount count);
  Future<void> resetSession();
}
