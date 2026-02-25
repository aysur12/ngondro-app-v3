import 'package:equatable/equatable.dart';

abstract class CounterState extends Equatable {
  const CounterState();

  @override
  List<Object?> get props => [];
}

class CounterInitial extends CounterState {
  const CounterInitial();
}

class CounterLoading extends CounterState {
  const CounterLoading();
}

class CounterLoaded extends CounterState {
  final int totalCount;
  final int sessionCount;
  final bool isCameraMode;
  final bool isBellPlayed; // Флаг чтобы UI знал что сыграл колокол

  const CounterLoaded({
    required this.totalCount,
    required this.sessionCount,
    this.isCameraMode = true,
    this.isBellPlayed = false,
  });

  CounterLoaded copyWith({
    int? totalCount,
    int? sessionCount,
    bool? isCameraMode,
    bool? isBellPlayed,
  }) {
    return CounterLoaded(
      totalCount: totalCount ?? this.totalCount,
      sessionCount: sessionCount ?? this.sessionCount,
      isCameraMode: isCameraMode ?? this.isCameraMode,
      isBellPlayed: isBellPlayed ?? this.isBellPlayed,
    );
  }

  @override
  List<Object?> get props =>
      [totalCount, sessionCount, isCameraMode, isBellPlayed];
}

class CounterError extends CounterState {
  final String message;

  const CounterError(this.message);

  @override
  List<Object?> get props => [message];
}
