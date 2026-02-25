import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../../../../ml/pose_detector_service.dart';
import '../../../../ml/prostration_classifier.dart';
import '../../../../core/constants/app_constants.dart';

/// Виджет предпросмотра камеры с ML pose detection и отображением позиции тела
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
  bool _isInitialized = false;
  String? _error;

  HeadInfo? _headInfo;

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
      if (_logs.length > _maxLogs) {
        _logs.removeAt(0);
      }
    });
    // Автоскролл вниз
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

      // Предпочитаем фронтальную камеру для простираний
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _addLog(
          'Камера: ${camera.name}, направление: ${camera.lensDirection.name}, '
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
        onHeadInfoUpdated: (info) {
          if (mounted) {
            setState(() => _headInfo = info);
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

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _poseDetectorService?.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  /// Копирует диагностику в буфер обмена
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

  /// Цвет квадрата в зависимости от фазы простирания
  Color _getHeadBoxColor(ProstrationPhase phase) {
    switch (phase) {
      case ProstrationPhase.calibrating:
        return Colors.yellow;
      case ProstrationPhase.standing:
        return Colors.green;
      case ProstrationPhase.goingDown:
        return Colors.orange;
      case ProstrationPhase.prostrated:
        return Colors.red;
      case ProstrationPhase.gettingUp:
        return Colors.blue;
    }
  }

  /// Текстовый статус фазы
  String _getPhaseLabel(ProstrationPhase phase, bool isCalibrated) {
    if (!isCalibrated) return 'Калибровка...';
    switch (phase) {
      case ProstrationPhase.calibrating:
        return 'Калибровка...';
      case ProstrationPhase.standing:
        return 'Стоит';
      case ProstrationPhase.goingDown:
        return 'Опускается';
      case ProstrationPhase.prostrated:
        return 'Простёрт';
      case ProstrationPhase.gettingUp:
        return 'Поднимается';
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
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
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

    return Column(
      children: [
        // Статус-бар с индикатором фазы
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
                    decoration: BoxDecoration(
                      color: boxColor,
                      shape: BoxShape.circle,
                    ),
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
                      '${headInfo.source == BodyTrackingSource.shoulders ? 'Плечи' : headInfo.source == BodyTrackingSource.hips ? 'Бёдра' : ''} ${(headInfo.confidence * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  const SizedBox(width: 8),
                  // Кнопка показа/скрытия логов
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

        // Превью камеры с наложением
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

                // Наложение: квадрат вокруг отслеживаемой точки тела
                if (headInfo != null && headInfo.isDetected)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return CustomPaint(
                        painter: HeadBoxPainter(
                          headInfo: headInfo,
                          color: boxColor,
                          canvasSize: Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                        ),
                      );
                    },
                  ),

                // Подсказка во время калибровки
                if (!isCalibrated && !_showLogs)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Встаньте прямо перед камерой',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ),
                  ),

                // Панель логов
                if (_showLogs)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black87,
                      child: Column(
                        children: [
                          // Заголовок панели логов
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            color: Colors.black,
                            child: Row(
                              children: [
                                const Icon(Icons.terminal,
                                    color: Colors.green, size: 16),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'Диагностика',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                // Кнопка копирования
                                GestureDetector(
                                  onTap: _copyDiagnostics,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.green.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: Colors.green
                                              .withValues(alpha: 0.5)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.copy,
                                            color: Colors.green, size: 14),
                                        SizedBox(width: 4),
                                        Text(
                                          'Копировать',
                                          style: TextStyle(
                                            color: Colors.green,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Кнопка очистки
                                GestureDetector(
                                  onTap: () => setState(() => _logs.clear()),
                                  child: const Icon(Icons.clear_all,
                                      color: Colors.grey, size: 18),
                                ),
                              ],
                            ),
                          ),
                          // Список логов
                          Expanded(
                            child: ListView.builder(
                              controller: _logScrollController,
                              padding: const EdgeInsets.all(6),
                              itemCount: _logs.length,
                              itemBuilder: (context, index) {
                                final log = _logs[index];
                                Color textColor = Colors.grey[400]!;
                                if (log.contains('ОШИБКА') ||
                                    log.contains('Error')) {
                                  textColor = Colors.red[300]!;
                                } else if (log.contains('загружена') ||
                                    log.contains('ЗАСЧИТАНО')) {
                                  textColor = Colors.green[300]!;
                                } else if (log.contains('Ошибка')) {
                                  textColor = Colors.orange[300]!;
                                }
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 1),
                                  child: Text(
                                    log,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Рисует квадрат вокруг отслеживаемой точки тела (плечи или бёдра)
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

    // Размер квадрата: пропорционален ширине холста
    final boxHalf = size.width * AppConstants.headBoxSize;

    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: boxHalf * 2,
      height: boxHalf * 2,
    );

    // Рисуем квадрат
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawRect(rect, paint);

    // Уголки квадрата (акцент)
    final cornerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final cornerLen = boxHalf * 0.35;

    // Верхний левый
    canvas.drawLine(
        rect.topLeft, rect.topLeft + Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(
        rect.topLeft, rect.topLeft + Offset(0, cornerLen), cornerPaint);
    // Верхний правый
    canvas.drawLine(
        rect.topRight, rect.topRight + Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(
        rect.topRight, rect.topRight + Offset(0, cornerLen), cornerPaint);
    // Нижний левый
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(
        rect.bottomLeft, rect.bottomLeft + Offset(0, -cornerLen), cornerPaint);
    // Нижний правый
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(-cornerLen, 0),
        cornerPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + Offset(0, -cornerLen),
        cornerPaint);

    // Центральная точка
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), 3, dotPaint);

    // Горизонтальная линия "стоячей" позиции (если откалибровано)
    if (headInfo.standingY != null) {
      final standingPy = headInfo.standingY! * size.height;
      final linePaint = Paint()
        ..color = Colors.green.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeJoin = StrokeJoin.miter;

      // Пунктирная линия уровня головы в стоячем положении
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
