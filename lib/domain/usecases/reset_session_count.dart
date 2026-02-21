import '../repositories/prostration_repository.dart';

class ResetSessionCount {
  final ProstrationRepository repository;

  const ResetSessionCount(this.repository);

  Future<void> call() {
    return repository.resetSession();
  }
}
