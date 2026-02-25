import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../di/injection.dart';
import '../../../domain/usecases/get_total_count.dart';
import '../../../domain/usecases/save_count.dart';
import '../../../domain/usecases/reset_session_count.dart';
import '../../../services/sound_service.dart';
import 'bloc/counter_bloc.dart';
import 'bloc/counter_event.dart';
import 'bloc/counter_state.dart';
import 'widgets/counter_display.dart';
import 'widgets/camera_preview_widget.dart';

class CounterScreen extends StatelessWidget {
  const CounterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CounterBloc(
        getTotalCount: getIt<GetTotalCount>(),
        saveCount: getIt<SaveCount>(),
        resetSessionCount: getIt<ResetSessionCount>(),
        soundService: getIt<SoundService>(),
      )..add(const CounterStarted()),
      child: const _CounterScreenContent(),
    );
  }
}

class _CounterScreenContent extends StatefulWidget {
  const _CounterScreenContent();

  @override
  State<_CounterScreenContent> createState() => _CounterScreenContentState();
}

class _CounterScreenContentState extends State<_CounterScreenContent>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Сохраняем при закрытии экрана
    context.read<CounterBloc>().add(const CounterSaved());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      context.read<CounterBloc>().add(const CounterSaved());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Counter'),
        actions: [
          BlocBuilder<CounterBloc, CounterState>(
            builder: (context, state) {
              if (state is! CounterLoaded) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.self_improvement),
                tooltip: 'Prostration',
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  context.read<CounterBloc>().add(const CounterIncremented());
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset Session',
            onPressed: () => _showResetDialog(context),
          ),
        ],
      ),
      body: BlocBuilder<CounterBloc, CounterState>(
        builder: (context, state) {
          if (state is CounterLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is CounterError) {
            return Center(
              child: Text(
                'Error: ${state.message}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (state is CounterLoaded) {
            return _buildLoadedContent(context, state);
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildLoadedContent(BuildContext context, CounterLoaded state) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Счётчик
            CounterDisplay(
              totalCount: state.totalCount,
              sessionCount: state.sessionCount,
            ),
            const SizedBox(height: 12),

            // Камера всегда активна
            Expanded(
              child: CameraPreviewWidget(
                onProstrationDetected: () {
                  HapticFeedback.mediumImpact();
                  context.read<CounterBloc>().add(const CounterIncremented());
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Camera is detecting prostrations automatically',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showResetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Session'),
        content: const Text(
            'Reset session count? Total count will not be affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<CounterBloc>().add(const SessionReset());
              Navigator.pop(dialogContext);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
