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

  // Параметры камеры для трансформации координат
  int _sensorOrientation = 0;
  bool _isFrontCamera = true;

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
sensorOrientation: $_sensorOrientation°
isFrontCamera: $_isFrontCamera
Обработано кадров: $_frameCount
Ошибок препроцессинга: $_preprocessErrorCount
Ошибок инференса: $_inferenceErrorCount''';
  }

  /// Трансформирует нормализованные координаты MoveNet (в пространстве
  /// сырого кадра камеры) в экранные координаты Flutter CameraPreview.
  ///
  /// MoveNet возвращает (y, x) нормализованные в пространстве кадра YUV420.
  /// Кадр физически повёрнут относительно экрана на [sensorOrientation] градусов.
  /// Flutter CameraPreview компенсирует поворот автоматически.
  /// Также учитывается зеркалирование фронтальной камеры.
  ///
  /// [frameWidth] и [frameHeight] — реальные размеры входного кадра YUV420.
  PoseLandmark _transformLandmark(PoseLandmark raw, int sensorOrientation,
      bool isFrontCamera, int frameWidth, int frameHeight) {
    double tx, ty;

    // Определяем поворот по sensorOrientation.
    // Важно: для портретного режима Android:
    //   sensorOrientation=90  → кадр повёрнут на 90° CCW (или 270° CW)
    //   sensorOrientation=270 → кадр повёрнут на 270° CCW (или 90° CW)
    //
    // Соответствие raw(y,x) → screen(y,x):
    //   0°:   ty=raw.y,       tx=raw.x
    //   90°:  ty=raw.x,       tx=1-raw.y   (90° CCW)
    //   180°: ty=1-raw.y,     tx=1-raw.x
    //   270°: ty=1-raw.x,     tx=raw.y     (270° CCW = 90° CW)
    switch (sensorOrientation) {
      case 90:
        ty = raw.x;
        tx = 1.0 - raw.y;
        break;
      case 180:
        ty = 1.0 - raw.y;
        tx = 1.0 - raw.x;
        break;
      case 270:
        ty = 1.0 - raw.x;
        tx = raw.y;
        break;
      case 0:
      default:
        ty = raw.y;
        tx = raw.x;
        break;
    }

    // Фронтальная камера: CameraPreview зеркалит по горизонтали
    if (isFrontCamera) {
      tx = 1.0 - tx;
    }

    return PoseLandmark(y: ty, x: tx, score: raw.score);
  }

  /// Обрабатывает кадр с камеры
  Future<void> processImage(CameraImage cameraImage, int sensorOrientation,
      {bool isFrontCamera = true}) async {
    if (_isProcessing) return;

    // Сохраняем параметры камеры для трансформации
    _sensorOrientation = sensorOrientation;
    _isFrontCamera = isFrontCamera;

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
      // Строим входной тензор [1,256,256,3] как вложенный List
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

      // Парсим точки и сразу трансформируем координаты
      final landmarks = <PoseLandmark>[];
      double maxScore = 0;
      PoseLandmark? rawNose;
      for (int i = 0; i < 17; i++) {
        final y = (output[0][0][i][0] as num).toDouble();
        final x = (output[0][0][i][1] as num).toDouble();
        final score = (output[0][0][i][2] as num).toDouble();
        final raw = PoseLandmark(y: y, x: x, score: score);
        if (i == MoveNetLandmark.nose) rawNose = raw;
        // Трансформируем из пространства сырого кадра в экранное пространство
        final transformed = _transformLandmark(raw, sensorOrientation,
            isFrontCamera, cameraImage.width, cameraImage.height);
        landmarks.add(transformed);
        if (score > maxScore) maxScore = score;
      }

      final nose = landmarks[MoveNetLandmark.nose];

      // Логируем каждые 30 кадров
      if (_frameCount % 30 == 0) {
        _log('Кадр #$_frameCount | '
            'cam: ${cameraImage.width}x${cameraImage.height} | '
            'sensor=${sensorOrientation}° front=$isFrontCamera | '
            'nose_raw: (y=${rawNose?.y.toStringAsFixed(2)}, x=${rawNose?.x.toStringAsFixed(2)}) s=${rawNose?.score.toStringAsFixed(2)} | '
            'nose_screen: (x=${nose.x.toStringAsFixed(2)}, y=${nose.y.toStringAsFixed(2)}) '
            's=${nose.score.toStringAsFixed(2)} | '
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

  /// Создаёт входной тензор [1,256,256,3] из YUV420 изображения.
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

      // [1][256][256][3]
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
