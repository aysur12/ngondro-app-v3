import 'package:equatable/equatable.dart';

abstract class CounterEvent extends Equatable {
  const CounterEvent();

  @override
  List<Object?> get props => [];
}

/// Загрузить счётчик при открытии экрана
class CounterStarted extends CounterEvent {
  const CounterStarted();
}

/// Простирание выполнено (от ручного нажатия или камеры)
class CounterIncremented extends CounterEvent {
  const CounterIncremented();
}

/// Сохранить текущее состояние (при выходе/сворачивании)
class CounterSaved extends CounterEvent {
  const CounterSaved();
}

/// Переключить режим камеры
class CameraModeToggled extends CounterEvent {
  const CameraModeToggled();
}

/// Сбросить счётчик сессии
class SessionReset extends CounterEvent {
  const SessionReset();
}
