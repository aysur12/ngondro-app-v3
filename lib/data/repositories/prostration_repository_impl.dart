import '../../domain/entities/prostration_count.dart';
import '../../domain/repositories/prostration_repository.dart';
import '../datasources/local/counter_local_datasource.dart';

class ProstrationRepositoryImpl implements ProstrationRepository {
  final CounterLocalDataSource _localDataSource;

  const ProstrationRepositoryImpl(this._localDataSource);

  @override
  Future<ProstrationCount> getCount() {
    return _localDataSource.getCount();
  }

  @override
  Future<void> saveCount(ProstrationCount count) {
    return _localDataSource.saveCount(count);
  }

  @override
  Future<void> resetSession() {
    return _localDataSource.resetSession();
  }
}
