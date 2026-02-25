import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'prostration_classifier.dart';

typedef ProstrationDetectedCallback = void Function();
typedef CalibrationCompletedCallback = void Function();
typedef HeadInfoUpdatedCallback = void Function(HeadInfo info);
typedef LogCallback = void Function(String message);

/// Сервис для обработки кадров камеры с использованием MoveNet Lightning
class PoseDetectorService {
  static const String _modelPath = 'assets/ml/movenet_lightning.tflite';

  /// Размер входного изображения для MoveNet Lightning
  static const int _inputSize = 192;

  Interpreter? _interpreter;
  final ProstrationClassifier _classifier;
  final ProstrationDetectedCallback onProstrationDetected;
  final CalibrationCompletedCallback? onCalibrationCompleted;
  final HeadInfoUpdatedCallback? onHeadInfoUpdated;
  final LogCallback? onLog;

  bool _isProcessing = false;
  bool _isLoaded = false;
  String? _loadError;
  String _tensorInputType = 'unknown';

  // Счётчики для логирования
  int _frameCount = 0;
  int _preprocessErrorCount = 0;
  int _inferenceErrorCount = 0;

  PoseDetectorService({
    required this.onProstrationDetected,
    this.onCalibrationCompleted,
    this.onHeadInfoUpdated,
    this.onLog,
  }) : _classifier = ProstrationClassifier() {
    _loadModel();
  }

  ProstrationPhase get currentPhase => _classifier.currentPhase;
  bool get isCalibrated => _classifier.isCalibrated;
  bool get isLoaded => _isLoaded;
  String? get loadError => _loadError;

  /// Вызывается после завершения воспроизведения calibration-end аудио
  void onCalibrationAudioFinished() {
    _classifier.onCalibrationAudioFinished();
    _log('Аудио калибровки завершено, начинаем отслеживание');
  }

  Future<void> _loadModel() async {
    try {
      _log('Загрузка модели $_modelPath...');
      _interpreter = await Interpreter.fromAsset(_modelPath);
      _isLoaded = true;

      final inputTensor = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);

      final typeStr = inputTensor.type.toString().toLowerCase();
      _tensorInputType = typeStr;

      _log('Модель загружена. '
          'Вход: ${inputTensor.shape} тип=$typeStr | '
          'Выход: ${outputTensor.shape} тип=${outputTensor.type}');
    } catch (e) {
      _loadError = e.toString();
      _log('ОШИБКА загрузки модели: $e');
    }
  }

  void _log(String message) {
    onLog?.call(
        '[${DateTime.now().toIso8601String().substring(11, 23)}] $message');
  }

  /// Диагностическая сводка
  String getDiagnostics() {
    return '''=== Диагностика MoveNet ===
Модель загружена: $_isLoaded
Ошибка загрузки: ${_loadError ?? 'нет'}
Тип входного тензора: $_tensorInputType
Фаза: ${_classifier.currentPhase.name}
Откалибровано: ${_classifier.isCalibrated}
Standing Y (Точка X): ${_classifier.standingY?.toStringAsFixed(3) ?? 'нет'}
Обработано кадров: $_frameCount
Ошибок препроцессинга: $_preprocessErrorCount
Ошибок инференса: $_inferenceErrorCount''';
  }

  /// Обрабатывает кадр с камеры
  Future<void> processImage(
      CameraImage cameraImage, int sensorOrientation) async {
    if (_isProcessing) return;

    if (!_isLoaded || _interpreter == null) {
      if (_frameCount % 30 == 0) {
        _log('Модель не загружена (ошибка: $_loadError)');
      }
      _frameCount++;
      return;
    }

    _isProcessing = true;
    _frameCount++;

    try {
      // Строим входной тензор [1,192,192,3] как вложенный List
      final input = _buildInputTensor(cameraImage);
      if (input == null) {
        _preprocessErrorCount++;
        if (_preprocessErrorCount <= 5 || _preprocessErrorCount % 30 == 0) {
          _log('Ошибка препроцессинга кадра #$_frameCount '
              '(${cameraImage.width}x${cameraImage.height}, '
              'planes: ${cameraImage.planes.length})');
        }
        return;
      }

      // Выходной тензор MoveNet: [1, 1, 17, 3] (y, x, score)
      final output = List.generate(
        1,
        (_) => List.generate(
          1,
          (_) => List.generate(
            17,
            (_) => List.filled(3, 0.0),
          ),
        ),
      );

      _interpreter!.run(input, output);

      // Парсим точки
      final landmarks = <PoseLandmark>[];
      double maxScore = 0;
      for (int i = 0; i < 17; i++) {
        final y = (output[0][0][i][0] as num).toDouble();
        final x = (output[0][0][i][1] as num).toDouble();
        final score = (output[0][0][i][2] as num).toDouble();
        landmarks.add(PoseLandmark(y: y, x: x, score: score));
        if (score > maxScore) maxScore = score;
      }

      final lShoulder = landmarks[MoveNetLandmark.leftShoulder];
      final rShoulder = landmarks[MoveNetLandmark.rightShoulder];

      // Логируем каждые 30 кадров
      if (_frameCount % 30 == 0) {
        _log('Кадр #$_frameCount | '
            'maxScore: ${maxScore.toStringAsFixed(2)} | '
            'lShoulder: (${lShoulder.x.toStringAsFixed(2)}, ${lShoulder.y.toStringAsFixed(2)}) '
            's=${lShoulder.score.toStringAsFixed(2)} | '
            'rShoulder s=${rShoulder.score.toStringAsFixed(2)} | '
            'phase: ${_classifier.currentPhase.name}');
      }

      // Анализируем позу
      final result = _classifier.analyzeLandmarks(landmarks);
      if (result.prostrationCompleted) {
        _log('✓ ПРОСТИРАНИЕ ЗАСЧИТАНО! (кадр #$_frameCount)');
        onProstrationDetected();
      }
      if (result.calibrationJustCompleted) {
        _log('✓ КАЛИБРОВКА ЗАВЕРШЕНА (кадр #$_frameCount), '
            'standingY=${_classifier.standingY?.toStringAsFixed(3)}');
        onCalibrationCompleted?.call();
      }

      // Передаём информацию для отображения
      if (onHeadInfoUpdated != null) {
        final headInfo = _classifier.getLastHeadInfo(landmarks);
        onHeadInfoUpdated!(headInfo);
      }
    } catch (e) {
      _inferenceErrorCount++;
      if (_inferenceErrorCount <= 5 || _inferenceErrorCount % 30 == 0) {
        _log('Ошибка инференса #$_inferenceErrorCount: $e');
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Создаёт входной тензор [1,192,192,3] из YUV420 изображения.
  /// TFLite принимает вложенный List структуру.
  List<List<List<List<int>>>>? _buildInputTensor(CameraImage image) {
    try {
      if (image.planes.length < 3) return null;

      final int width = image.width;
      final int height = image.height;

      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;

      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;

      // [1][192][192][3]
      final input = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (row) => List.generate(
            _inputSize,
            (col) {
              final srcRow =
                  (row * height / _inputSize).floor().clamp(0, height - 1);
              final srcCol =
                  (col * width / _inputSize).floor().clamp(0, width - 1);

              final yIndex = srcRow * yPlane.bytesPerRow + srcCol;
              final yVal = yBytes[yIndex.clamp(0, yBytes.length - 1)];

              final uvRow = srcRow ~/ 2;
              final uvCol = srcCol ~/ 2;
              final uvIndex = uvRow * uvRowStride + uvCol * uvPixelStride;

              final uVal = uBytes[uvIndex.clamp(0, uBytes.length - 1)];
              final vVal = vBytes[uvIndex.clamp(0, vBytes.length - 1)];

              final yD = yVal.toDouble();
              final uD = uVal.toDouble() - 128.0;
              final vD = vVal.toDouble() - 128.0;

              final r = (yD + 1.402 * vD).clamp(0.0, 255.0).toInt();
              final g = (yD - 0.344136 * uD - 0.714136 * vD)
                  .clamp(0.0, 255.0)
                  .toInt();
              final b = (yD + 1.772 * uD).clamp(0.0, 255.0).toInt();

              return [r, g, b];
            },
          ),
        ),
      );

      return input;
    } catch (e) {
      return null;
    }
  }

  void resetClassifier() {
    _classifier.reset();
    _log('Классификатор сброшен, начинаем калибровку заново');
  }

  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
  }
}
