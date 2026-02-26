import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../../../../ml/pose_detector_service.dart';
import '../../../../ml/prostration_classifier.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../services/sound_service.dart';

/// Виджет предпросмотра камеры с MoveNet pose detection
class CameraPreviewWidget extends StatefulWidget {
  final VoidCallback onProstrationDetected;

  const CameraPreviewWidget({
    super.key,
    required this.onProstrationDetected,
  });

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget> {
  CameraController? _controller;
  PoseDetectorService? _poseDetectorService;
  final SoundService _soundService = SoundService();

  bool _isInitialized = false;
  String? _error;

  HeadInfo? _headInfo;

  // Флаг: звук калибровки-старт уже запущен
  bool _calibrationStartSoundPlayed = false;

  // Прогресс воспроизведения calibration-end аудио (0.0..1.0)
  double _calibrationEndAudioProgress = 0.0;
  Timer? _audioProgressTimer;

  // Логи диагностики
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  bool _showLogs = false;
  static const int _maxLogs = 200;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _logs.add(message);
      if (_logs.length > _maxLogs) _logs.removeAt(0);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No cameras available');
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _addLog('Камера: ${camera.name}, '
          'направление: ${camera.lensDirection.name}, '
          'sensorOrientation: ${camera.sensorOrientation}°');

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();

      _addLog('Камера инициализирована: '
          '${_controller!.value.previewSize?.width.toInt()}x'
          '${_controller!.value.previewSize?.height.toInt()}');

      _poseDetectorService = PoseDetectorService(
        onProstrationDetected: widget.onProstrationDetected,
        onCalibrationCompleted: _onCalibrationCompleted,
        onHeadInfoUpdated: (info) {
          if (mounted) {
            setState(() => _headInfo = info);
            // Запускаем звук старта калибровки при первом определении позы
            if (!_calibrationStartSoundPlayed &&
                info.phase == ProstrationPhase.calibrating &&
                info.isDetected) {
              _calibrationStartSoundPlayed = true;
              _soundService.playCalibrationStart();
            }
          }
        },
        onLog: _addLog,
      );

      await _controller!.startImageStream((image) {
        _poseDetectorService?.processImage(
          image,
          camera.sensorOrientation,
        );
      });

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      setState(() => _error = 'Camera error: $e');
      _addLog('ОШИБКА камеры: $e');
    }
  }

  /// Вызывается когда классификатор зафиксировал Точку X (5 сек стабильности)
  void _onCalibrationCompleted() {
    if (!mounted) return;
    // Запускаем звук завершения калибровки
    // Когда звук закончится — уведомляем классификатор начать фазу standing
    _soundService.playCalibrationEnd(
      onComplete: _onCalibrationAudioFinished,
    );
    // Запускаем таймер для отображения прогресса аудио
    // Оцениваем длительность аудио (~3-5 сек), обновляем каждые 100мс
    _startAudioProgressTimer();
  }

  void _startAudioProgressTimer() {
    _calibrationEndAudioProgress = 0.0;
    const totalMs = 4000; // предполагаемая длительность аудио в мс
    const stepMs = 100;
    int elapsed = 0;

    _audioProgressTimer?.cancel();
    _audioProgressTimer =
        Timer.periodic(const Duration(milliseconds: stepMs), (timer) {
      elapsed += stepMs;
      if (mounted) {
        setState(() {
          _calibrationEndAudioProgress = (elapsed / totalMs).clamp(0.0, 1.0);
        });
      }
      if (elapsed >= totalMs) {
        timer.cancel();
      }
    });
  }

  void _onCalibrationAudioFinished() {
    _audioProgressTimer?.cancel();
    if (mounted) {
      setState(() => _calibrationEndAudioProgress = 1.0);
    }
    _poseDetectorService?.onCalibrationAudioFinished();
  }

  @override
  void dispose() {
    _audioProgressTimer?.cancel();
    _controller?.stopImageStream();
    _controller?.dispose();
    _poseDetectorService?.dispose();
    _soundService.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _copyDiagnostics() async {
    final diagnostics =
        _poseDetectorService?.getDiagnostics() ?? '(сервис не инициализирован)';
    final logsText = _logs.join('\n');
    final text = '$diagnostics\n\n=== Логи ===\n$logsText';
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Диагностика скопирована в буфер обмена'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Color _getHeadBoxColor(ProstrationPhase phase) {
    switch (phase) {
      case ProstrationPhase.calibrating:
        return Colors.yellow;
      case ProstrationPhase.calibrationComplete:
        return Colors.teal;
      case ProstrationPhase.standing:
        return Colors.green;
      case ProstrationPhase.down:
        return Colors.orange;
    }
  }

  String _getPhaseLabel(ProstrationPhase phase, bool isCalibrated) {
    switch (phase) {
      case ProstrationPhase.calibrating:
        return 'Калибровка...';
      case ProstrationPhase.calibrationComplete:
        return 'Калибровка завершена';
      case ProstrationPhase.standing:
        return 'Стоит';
      case ProstrationPhase.down:
        return 'Простирание...';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final headInfo = _headInfo;
    final phase = headInfo?.phase ?? ProstrationPhase.calibrating;
    final isCalibrated = headInfo?.standingY != null;
    final boxColor = _getHeadBoxColor(phase);
    final calibProgress = headInfo?.calibrationProgress ?? 0.0;

    return Column(
      children: [
        // Статус-бар
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: boxColor.withValues(alpha: 0.15),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: boxColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getPhaseLabel(phase, isCalibrated),
                    style: TextStyle(
                      color: boxColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (headInfo != null && headInfo.isDetected)
                    Text(
                      '${headInfo.source == BodyTrackingSource.shoulders ? 'Плечи' : headInfo.source == BodyTrackingSource.hips ? 'Бёдра' : headInfo.source == BodyTrackingSource.lastKnown ? 'Память' : ''} '
                      '${headInfo.source != BodyTrackingSource.lastKnown ? '${(headInfo.confidence * 100).toStringAsFixed(0)}%' : ''}',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _showLogs = !_showLogs),
                    child: Icon(
                      _showLogs ? Icons.bug_report : Icons.bug_report_outlined,
                      size: 20,
                      color: _showLogs ? Colors.amber : Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Превью камеры
        Expanded(
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Камера
                AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: CameraPreview(_controller!),
                ),

                // Квадрат отслеживания точки тела
                if (headInfo != null && headInfo.isDetected)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return CustomPaint(
                        painter: HeadBoxPainter(
                          headInfo: headInfo,
                          color: boxColor,
                          canvasSize:
                              Size(constraints.maxWidth, constraints.maxHeight),
                        ),
                      );
                    },
                  ),

                // Оверлей калибровки (фаза calibrating)
                if (phase == ProstrationPhase.calibrating && !_showLogs)
                  _CalibrationOverlay(calibrationProgress: calibProgress),

                // Оверлей завершения калибровки (фаза calibrationComplete)
                if (phase == ProstrationPhase.calibrationComplete && !_showLogs)
                  _CalibrationCompleteOverlay(
                    audioProgress: _calibrationEndAudioProgress,
                  ),

                // Панель логов
                if (_showLogs) _buildLogsPanel(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogsPanel() {
    return Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: Colors.black,
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: Colors.green, size: 16),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('Диагностика',
                        style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                  GestureDetector(
                    onTap: _copyDiagnostics,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.green.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy, color: Colors.green, size: 14),
                          SizedBox(width: 4),
                          Text('Копировать',
                              style:
                                  TextStyle(color: Colors.green, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _logs.clear()),
                    child: const Icon(Icons.clear_all,
                        color: Colors.grey, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _logScrollController,
                padding: const EdgeInsets.all(6),
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  Color textColor = Colors.grey[400]!;
                  if (log.contains('ОШИБКА') || log.contains('Error')) {
                    textColor = Colors.red[300]!;
                  } else if (log.contains('загружена') ||
                      log.contains('ЗАСЧИТАНО') ||
                      log.contains('ЗАВЕРШЕНА')) {
                    textColor = Colors.green[300]!;
                  } else if (log.contains('Ошибка')) {
                    textColor = Colors.orange[300]!;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(log,
                        style: TextStyle(
                            color: textColor,
                            fontSize: 10,
                            fontFamily: 'monospace')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Оверлей во время калибровки (5 секунд стабильности)
class _CalibrationOverlay extends StatelessWidget {
  final double calibrationProgress;

  const _CalibrationOverlay({required this.calibrationProgress});

  @override
  Widget build(BuildContext context) {
    final progressPercent = (calibrationProgress * 100).toInt();
    final remaining = AppConstants.calibrationDurationSeconds -
        (calibrationProgress * AppConstants.calibrationDurationSeconds).floor();

    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Встаньте прямо перед камерой\nи не двигайтесь 5 секунд',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                // Прогресс-бар
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: calibrationProgress,
                    minHeight: 6,
                    backgroundColor: Colors.white24,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.yellow),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  calibrationProgress < 0.05
                      ? 'Ожидание...'
                      : '$progressPercent% • осталось ${remaining}с',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Оверлей после завершения калибровки (воспроизведение аудио)
class _CalibrationCompleteOverlay extends StatelessWidget {
  final double audioProgress;

  const _CalibrationCompleteOverlay({required this.audioProgress});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Калибровка завершена!\nМожете начинать простирания',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: audioProgress,
                minHeight: 6,
                backgroundColor: Colors.white24,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.volume_up, color: Colors.tealAccent, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Воспроизведение...',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Рисует квадрат вокруг отслеживаемой точки тела
class HeadBoxPainter extends CustomPainter {
  final HeadInfo headInfo;
  final Color color;
  final Size canvasSize;

  HeadBoxPainter({
    required this.headInfo,
    required this.color,
    required this.canvasSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!headInfo.isDetected) return;

    final cx = headInfo.normalizedX! * size.width;
    final cy = headInfo.normalizedY! * size.height;
    final boxHalf = size.width * AppConstants.headBoxSize;

    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: boxHalf * 2,
      height: boxHalf * 2,
    );

    // Используем пунктир если temporal smoothing (lastKnown)
    final isLastKnown = headInfo.source == BodyTrackingSource.lastKnown;
    final strokeWidth = isLastKnown ? 1.5 : 2.5;

    final paint = Paint()
      ..color = color.withValues(alpha: isLastKnown ? 0.5 : 1.0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawRect(rect, paint);

    // Уголки квадрата
    final cornerPaint = Paint()
      ..color = color.withValues(alpha: isLastKnown ? 0.4 : 1.0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isLastKnown ? 2.0 : 4.0
      ..strokeCap = StrokeCap.round;

    final cornerLen = boxHalf * 0.35;
    canvas.drawLine(
        rect.topLeft, rect.topLeft + Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(
        rect.topLeft, rect.topLeft + Offset(0, cornerLen), cornerPaint);
    canvas.drawLine(
        rect.topRight, rect.topRight + Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(
        rect.topRight, rect.topRight + Offset(0, cornerLen), cornerPaint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + Offset(0, -cornerLen), cornerPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(-cornerLen, 0),
        cornerPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(0, -cornerLen),
        cornerPaint);

    // Центральная точка
    final dotPaint = Paint()
      ..color = color.withValues(alpha: isLastKnown ? 0.4 : 1.0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), isLastKnown ? 2 : 3, dotPaint);

    // Горизонтальная пунктирная линия Точки X
    if (headInfo.standingY != null) {
      final standingPy = headInfo.standingY! * size.height;
      final linePaint = Paint()
        ..color = Colors.green.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      _drawDashedLine(
        canvas,
        Offset(0, standingPy),
        Offset(size.width, standingPy),
        linePaint,
        dashWidth: 8,
        dashGap: 4,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint,
      {double dashWidth = 5, double dashGap = 3}) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = (end - start).distance;
    final unitX = dx / len;
    final unitY = dy / len;

    double drawn = 0;
    bool drawing = true;
    while (drawn < len) {
      final segLen = drawing ? dashWidth : dashGap;
      final segEnd = (drawn + segLen).clamp(0.0, len);
      if (drawing) {
        canvas.drawLine(
          Offset(start.dx + unitX * drawn, start.dy + unitY * drawn),
          Offset(start.dx + unitX * segEnd, start.dy + unitY * segEnd),
          paint,
        );
      }
      drawn = segEnd;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(HeadBoxPainter oldDelegate) =>
      oldDelegate.headInfo != headInfo || oldDelegate.color != color;
}
