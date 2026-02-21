import '../entities/prostration_count.dart';
import '../repositories/prostration_repository.dart';

class SaveCount {
  final ProstrationRepository repository;

  const SaveCount(this.repository);

  Future<void> call(ProstrationCount count) {
    return repository.saveCount(count);
  }
}
