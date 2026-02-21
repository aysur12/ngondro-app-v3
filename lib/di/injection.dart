import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/datasources/local/counter_local_datasource.dart';
import '../data/repositories/prostration_repository_impl.dart';
import '../domain/repositories/prostration_repository.dart';
import '../domain/usecases/get_total_count.dart';
import '../domain/usecases/save_count.dart';
import '../domain/usecases/reset_session_count.dart';
import '../services/sound_service.dart';

final GetIt getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // External
  final sharedPreferences = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(sharedPreferences);

  // Data Sources
  getIt.registerSingleton<CounterLocalDataSource>(
    CounterLocalDataSourceImpl(getIt<SharedPreferences>()),
  );

  // Repositories
  getIt.registerSingleton<ProstrationRepository>(
    ProstrationRepositoryImpl(getIt<CounterLocalDataSource>()),
  );

  // Use Cases
  getIt.registerSingleton<GetTotalCount>(
    GetTotalCount(getIt<ProstrationRepository>()),
  );
  getIt.registerSingleton<SaveCount>(
    SaveCount(getIt<ProstrationRepository>()),
  );
  getIt.registerSingleton<ResetSessionCount>(
    ResetSessionCount(getIt<ProstrationRepository>()),
  );

  // Services
  getIt.registerFactory<SoundService>(() => SoundService());
}
