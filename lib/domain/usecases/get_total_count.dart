import '../entities/prostration_count.dart';
import '../repositories/prostration_repository.dart';

class GetTotalCount {
  final ProstrationRepository repository;

  const GetTotalCount(this.repository);

  Future<ProstrationCount> call() {
    return repository.getCount();
  }
}
