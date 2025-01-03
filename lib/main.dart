import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Real-time Object Detection',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DetectionScreen(),
    );
  }
}

class DetectionScreen extends StatefulWidget {
  const DetectionScreen({super.key});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  late CameraController _cameraController;
  late Interpreter _interpreter;
  List<String>? _labels;
  Map<String, double>? _recognition;
  bool _isDetecting = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModel();
    _loadLabels();
  }

Future<void> _initializeCamera() async {
    try {
      if (cameras.isEmpty) {
        debugPrint('No cameras available');
        return;
      }

      // 후면 카메라 찾기
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        // 해상도는 high로 유지하되 프레임 처리 간격을 조정할 예정
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS 
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      
      if (!mounted) return;

      // 프레임 처리 간격 설정 (초당 2프레임으로 제한)
      int processFrameCount = 0;
      await _cameraController!.startImageStream((image) {
        processFrameCount++;
        if (processFrameCount % 30 == 0) {  // 30fps 기준으로 2fps로 제한
          _processCameraImage(image);
        }
      });
      
      setState(() {});
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }


Future<void> _loadModel() async {
  try {
    final options = InterpreterOptions()
      ..threads = 2;
    
    if (Platform.isAndroid) {
      try {
        final gpuDelegate = GpuDelegateV2();
        options.addDelegate(gpuDelegate);
        debugPrint('Android GPU Delegate added');
      } catch (e) {
        debugPrint('Failed to add Android GPU Delegate: $e');
      }
    }
    
    if (Platform.isIOS) {
      try {
        final gpuDelegate = GpuDelegate();
        options.addDelegate(gpuDelegate);
        debugPrint('iOS GPU Delegate added');
      } catch (e) {
        debugPrint('Failed to add iOS GPU Delegate: $e');
      }
    }

    // YOLO 모델로 변경
    _interpreter = await Interpreter.fromAsset(
      'assets/yolov2_tiny.tflite',
      options: options,
    );
    
    _interpreter.allocateTensors();
    
    final inputShape = _interpreter.getInputTensor(0).shape;
    final outputShape = _interpreter.getOutputTensor(0).shape;
    debugPrint('Model loaded successfully');
    debugPrint('Input shape: $inputShape');
    debugPrint('Output shape: $outputShape');
    
  } catch (e) {
    debugPrint('Failed to load model: $e');
  }
}

  Future<void> _loadLabels() async {
    try {
      final labelText = await DefaultAssetBundle.of(context)
          .loadString('assets/yolov2_tiny.txt');
      _labels = labelText.split('\n');
      debugPrint('Labels loaded successfully: ${_labels?.length} labels');
      debugPrint('First few labels: ${_labels?.take(5).join(", ")}');
    } catch (e) {
      debugPrint('Failed to load labels: $e');
    }
  }


Future<void> _processCameraImage(CameraImage cameraImage) async {
  if (_isDetecting) return;
  _isDetecting = true;

  try {
    final image = Platform.isIOS 
        ? _convertBGRA8888ToImage(cameraImage)
        : _convertYUV420ToImage(cameraImage);
        
    if (image == null) return;

    // YOLO 입력 크기 416x416으로 조정
    final resizedImage = img.copyResize(
      image, 
      width: 416,
      height: 416,
      interpolation: img.Interpolation.linear
    );

    // 입력 텐서 준비 (정규화 추가)
    final inputArray = List.generate(
      1,
      (index) => List.generate(
        416,
        (y) => List.generate(
          416,
          (x) => List.generate(
            3,
            (c) {
              final pixel = resizedImage.getPixel(x, y);
              // YOLO 정규화: 0-255 범위를 0-1 범위로 변환
              return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0][c];
            },
          ),
        ),
      ),
    );

    // 출력 텐서 준비
    final outputArray = List.generate(
      1,
      (index) => List.generate(
        13,
        (y) => List.generate(
          13,
          (x) => List<double>.filled(425, 0.0),
        ),
      ),
    );

    // 모델 실행
    _interpreter.run(inputArray, outputArray);

    // YOLO 출력 처리
    final results = <String, double>{};
    const int numClasses = 80;
    const int numBoxes = 5;
    const double confidenceThreshold = 0.1; // 최소 신뢰도 임계값

    for (var y = 0; y < 13; y++) {
      for (var x = 0; x < 13; x++) {
        for (var b = 0; b < numBoxes; b++) {
          var offset = b * (5 + numClasses);
          var confidence = _sigmoid(outputArray[0][y][x][offset + 4]); // sigmoid 적용

          if (confidence > confidenceThreshold) {
            // 클래스별 확률 계산
            var maxClass = 0;
            var maxProb = 0.0;

            for (var c = 0; c < numClasses; c++) {
              var prob = _sigmoid(outputArray[0][y][x][offset + 5 + c]); // sigmoid 적용
              if (prob > maxProb) {
                maxProb = prob;
                maxClass = c;
              }
            }

            var score = confidence * maxProb;
            if (score > confidenceThreshold && _labels != null && maxClass < _labels!.length) {
              var className = _labels![maxClass];
              if (!results.containsKey(className) || results[className]! < score) {
                results[className] = score;
              }
            }
          }
        }
      }
    }

    // 확률이 높은 순으로 정렬
    final sortedResults = Map.fromEntries(
      results.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value))
    );

    if (mounted) {
      setState(() {
        _recognition = sortedResults;
      });
    }

  } catch (e) {
    debugPrint('Error processing image: $e');
  } finally {
    _isDetecting = false;
  }
}

// Sigmoid 함수 추가
double _sigmoid(double x) {
  return 1.0 / (1.0 + exp(-x));
}

  img.Image? _convertBGRA8888ToImage(CameraImage cameraImage) {
    try {
      final bytes = cameraImage.planes[0].bytes;
      final width = cameraImage.width;
      final height = cameraImage.height;
      
      final image = img.Image(width:width, height:height);
      var pixelIndex = 0;
      
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final b = bytes[pixelIndex];
          final g = bytes[pixelIndex + 1];
          final r = bytes[pixelIndex + 2];
          // alpha 값은 무시
          
          image.setPixelRgba(x, y, r, g, b, 255);
          pixelIndex += 4; // BGRA는 픽셀당 4바이트
        }
      }
      
      return image;
    } catch (e) {
      debugPrint('Error converting BGRA8888 to RGB: $e');
      return null;
    }
  }

  // YUV420 형식을 RGB로 변환
  img.Image? _convertYUV420ToImage(CameraImage cameraImage) {
    try {
      final int width = cameraImage.width;
      final int height = cameraImage.height;
      final int uvRowStride = cameraImage.planes[1].bytesPerRow;
      final int uvPixelStride = cameraImage.planes[1].bytesPerPixel ?? 1;

      final image = img.Image(width:width, height:height);

      for (int x = 0; x < width; x++) {
        for (int y = 0; y < height; y++) {
          final int uvIndex =
              uvPixelStride * (x / 2).floor() +
              uvRowStride * (y / 2).floor();
          final int index = y * width + x;

          final yp = cameraImage.planes[0].bytes[index];
          final up = cameraImage.planes[1].bytes[uvIndex];
          final vp = cameraImage.planes[2].bytes[uvIndex];

          // YUV -> RGB conversion
          int r = (yp + 1.370705 * (vp - 128)).round().clamp(0, 255);
          int g = (yp - 0.698001 * (vp - 128) - 0.337633 * (up - 128)).round().clamp(0, 255);
          int b = (yp + 1.732446 * (up - 128)).round().clamp(0, 255);

          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      return image;
    } catch (e) {
      debugPrint('Error converting YUV420 to RGB: $e');
      return null;
    }
  }
  @override
  void dispose() {
    _cameraController.dispose();
    _interpreter.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraController.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Object Detection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          // 카메라 미리보기
          CameraPreview(_cameraController),
          
          // 결과 표시
          if (_recognition != null && _recognition!.isNotEmpty)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 200, // 결과창 너비
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: _recognition!.entries.take(20).map((entry) {  // 상위 20개만 표시
                  final confidence = entry.value * 100;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '${confidence.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: _getConfidenceColor(confidence),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
  Color _getConfidenceColor(double confidence) {
    if (confidence > 70) return Colors.green;
    if (confidence > 30) return Colors.yellow;
    return Colors.red;
  }
}