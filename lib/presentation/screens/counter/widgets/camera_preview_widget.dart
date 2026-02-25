import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../../../ml/pose_detector_service.dart';
import '../../../../ml/prostration_classifier.dart';
import '../../../../core/constants/app_constants.dart';

/// Виджет предпросмотра камеры с ML pose detection и отображением головы
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

  @override
  void initState() {
    super.initState();
    _initCamera();
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

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();

      _poseDetectorService = PoseDetectorService(
        onProstrationDetected: widget.onProstrationDetected,
        onHeadInfoUpdated: (info) {
          if (mounted) {
            setState(() => _headInfo = info);
          }
        },
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
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _poseDetectorService?.dispose();
    super.dispose();
  }

  /// Цвет квадрата головы в зависимости от фазы простирания
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
              if (headInfo != null && headInfo.isDetected)
                Text(
                  'Уверенность: ${(headInfo.confidence * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
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

                // Наложение: зелёный квадрат вокруг головы
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
                if (!isCalibrated)
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Рисует квадрат вокруг головы человека
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
