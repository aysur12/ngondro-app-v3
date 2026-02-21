import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../domain/entities/prostration_count.dart';
import '../../../../domain/usecases/get_total_count.dart';
import '../../../../domain/usecases/save_count.dart';
import '../../../../domain/usecases/reset_session_count.dart';
import '../../../../services/sound_service.dart';
import 'counter_event.dart';
import 'counter_state.dart';

class CounterBloc extends Bloc<CounterEvent, CounterState> {
  final GetTotalCount _getTotalCount;
  final SaveCount _saveCount;
  final ResetSessionCount _resetSessionCount;
  final SoundService _soundService;

  CounterBloc({
    required GetTotalCount getTotalCount,
    required SaveCount saveCount,
    required ResetSessionCount resetSessionCount,
    required SoundService soundService,
  })  : _getTotalCount = getTotalCount,
        _saveCount = saveCount,
        _resetSessionCount = resetSessionCount,
        _soundService = soundService,
        super(const CounterInitial()) {
    on<CounterStarted>(_onCounterStarted);
    on<CounterIncremented>(_onCounterIncremented);
    on<CounterSaved>(_onCounterSaved);
    on<CameraModeToggled>(_onCameraModeToggled);
    on<SessionReset>(_onSessionReset);
  }

  Future<void> _onCounterStarted(
    CounterStarted event,
    Emitter<CounterState> emit,
  ) async {
    emit(const CounterLoading());
    try {
      final count = await _getTotalCount();
      emit(CounterLoaded(
        totalCount: count.totalCount,
        sessionCount: count.sessionCount,
      ));
    } catch (e) {
      emit(CounterError(e.toString()));
    }
  }

  Future<void> _onCounterIncremented(
    CounterIncremented event,
    Emitter<CounterState> emit,
  ) async {
    final currentState = state;
    if (currentState is! CounterLoaded) return;

    final newTotal = currentState.totalCount + 1;
    final newSession = currentState.sessionCount + 1;
    final isMilestone = newTotal % AppConstants.bellInterval == 0;

    // Автосохранение при каждом 100-м простирании
    if (isMilestone) {
      await _soundService.playBell();
      await _saveCount(ProstrationCount(
        totalCount: newTotal,
        sessionCount: newSession,
      ));
    }

    emit(currentState.copyWith(
      totalCount: newTotal,
      sessionCount: newSession,
      isBellPlayed: isMilestone,
    ));

    // Сбрасываем флаг колокола после испускания состояния
    if (isMilestone) {
      emit(currentState.copyWith(
        totalCount: newTotal,
        sessionCount: newSession,
        isBellPlayed: false,
      ));
    }
  }

  Future<void> _onCounterSaved(
    CounterSaved event,
    Emitter<CounterState> emit,
  ) async {
    final currentState = state;
    if (currentState is! CounterLoaded) return;

    await _saveCount(ProstrationCount(
      totalCount: currentState.totalCount,
      sessionCount: currentState.sessionCount,
    ));
  }

  Future<void> _onCameraModeToggled(
    CameraModeToggled event,
    Emitter<CounterState> emit,
  ) async {
    final currentState = state;
    if (currentState is! CounterLoaded) return;

    emit(currentState.copyWith(
      isCameraMode: !currentState.isCameraMode,
    ));
  }

  Future<void> _onSessionReset(
    SessionReset event,
    Emitter<CounterState> emit,
  ) async {
    final currentState = state;
    if (currentState is! CounterLoaded) return;

    await _resetSessionCount();
    emit(currentState.copyWith(sessionCount: 0));
  }

  @override
  Future<void> close() async {
    // Сохраняем при закрытии BLoC
    final currentState = state;
    if (currentState is CounterLoaded) {
      await _saveCount(ProstrationCount(
        totalCount: currentState.totalCount,
        sessionCount: currentState.sessionCount,
      ));
    }
    await _soundService.dispose();
    return super.close();
  }
}
