import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'prostration_classifier.dart';

typedef ProstrationDetectedCallback = void Function();
typedef HeadInfoUpdatedCallback = void Function(HeadInfo info);

/// Сервис для обработки кадров камеры и определения простираний
class PoseDetectorService {
  final PoseDetector _poseDetector;
  final ProstrationClassifier _classifier;
  final ProstrationDetectedCallback onProstrationDetected;
  final HeadInfoUpdatedCallback? onHeadInfoUpdated;

  bool _isProcessing = false;

  PoseDetectorService({
    required this.onProstrationDetected,
    this.onHeadInfoUpdated,
  })  : _poseDetector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.stream,
            model: PoseDetectionModel.base,
          ),
        ),
        _classifier = ProstrationClassifier();

  ProstrationPhase get currentPhase => _classifier.currentPhase;
  bool get isCalibrated => _classifier.isCalibrated;

  /// Обрабатывает кадр с камеры
  Future<void> processImage(
      CameraImage cameraImage, int sensorOrientation) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final inputImage = _buildInputImage(cameraImage, sensorOrientation);
      if (inputImage == null) return;

      final poses = await _poseDetector.processImage(inputImage);

      if (poses.isNotEmpty) {
        final pose = poses.first;
        final imageWidth = cameraImage.width.toDouble();
        final imageHeight = cameraImage.height.toDouble();

        // Анализируем позу и проверяем простирание
        final prostrationCompleted = _classifier.analyzePose(
          pose,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        );

        if (prostrationCompleted) {
          onProstrationDetected();
        }

        // Передаём информацию о голове для отображения зелёного квадрата
        if (onHeadInfoUpdated != null) {
          final headInfo = _classifier.getLastHeadInfo(
            pose,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
          );
          if (headInfo != null) {
            onHeadInfoUpdated!(headInfo);
          }
        }
      } else {
        // Поза не обнаружена — передаём пустой HeadInfo
        if (onHeadInfoUpdated != null) {
          onHeadInfoUpdated!(HeadInfo(
            confidence: 0.0,
            phase: _classifier.currentPhase,
            standingY: _classifier.standingY,
          ));
        }
      }
    } catch (e) {
      // Игнорируем ошибки обработки отдельных кадров
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _buildInputImage(CameraImage image, int sensorOrientation) {
    try {
      final format = InputImageFormatValue.fromRawValue(image.format.raw);
      if (format == null) return null;

      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotationValue.fromRawValue(sensorOrientation) ??
              InputImageRotation.rotation0deg,
          format: format,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  void resetClassifier() {
    _classifier.reset();
  }

  Future<void> dispose() async {
    await _poseDetector.close();
  }
}
