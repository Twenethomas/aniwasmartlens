// lib/features/pc_cam/screens/object_detection_screen.dart
import 'dart:async';
import 'dart:io';
// import 'dart:ui'; // Removed unnecessary import
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:assist_lens/main.dart'; // For routeObserver and logger
import 'package:assist_lens/core/services/network_service.dart'; // Import NetworkService
import 'package:assist_lens/core/services/gemini_service.dart'; // Import GeminiService
import 'package:assist_lens/core/services/speech_service.dart'; // Import SpeechService

class ObjectDetectionScreen extends StatefulWidget {
  final bool autoStartLive;

  const ObjectDetectionScreen({super.key, this.autoStartLive = false});

  @override
  State<ObjectDetectionScreen> createState() => _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen> with RouteAware {
  CameraController? _cameraController;
  ObjectDetector? _objectDetector;
  List<DetectedObject> _detectedObjects = [];
  String _objectDescription = '';
  String _errorMessage = '';
  bool _isProcessingFrame = false;
  bool _isCameraReady = false;
  bool _isProcessingAI = false; // For Gemini calls
  bool _isSpeaking = false; // Track TTS speaking status

  final Logger _logger = logger; // Use global logger
  late NetworkService _networkService;
  late GeminiService _geminiService;
  late SpeechService _speechService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _networkService = Provider.of<NetworkService>(context, listen: false);
      _geminiService = Provider.of<GeminiService>(context, listen: false);
      _speechService = Provider.of<SpeechService>(context, listen: false);

      _speechService.speakingStatusStream.listen((status) {
        if (mounted) {
          setState(() {
            _isSpeaking = status;
          });
        }
      });

      _initializeDetector();
      if (widget.autoStartLive) {
        _initializeCamera();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) { // Ensure it's a PageRoute before subscribing
      routeObserver.subscribe(this, route);
    } else {
      _logger.w("ObjectDetectionScreen: Cannot subscribe to RouteObserver, current route is not a PageRoute.");
    }
  }

  @override
  void didPush() {
    logger.i("ObjectDetectionScreen: didPush - Page is active. Resuming camera.");
    if (_cameraController != null && !_cameraController!.value.isStreamingImages) {
      _cameraController!.startImageStream(_processCameraImage);
    } else if (_cameraController == null && widget.autoStartLive) {
      _initializeCamera();
    }
    super.didPush();
  }

  @override
  void didPopNext() {
    logger.i("ObjectDetectionScreen: didPopNext - Returning to page. Resuming camera.");
    if (_cameraController != null && !_cameraController!.value.isStreamingImages) {
      _cameraController!.startImageStream(_processCameraImage);
    } else if (_cameraController == null && widget.autoStartLive) {
      _initializeCamera();
    }
    super.didPopNext();
  }

  @override
  void didPushNext() {
    logger.i("ObjectDetectionScreen: didPushNext - Navigating away from page. Pausing camera.");
    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
      _cameraController!.stopImageStream();
    }
    super.didPushNext();
  }

  @override
  void didPop() {
    logger.i("ObjectDetectionScreen: didPop - Page is being popped. Disposing camera.");
    _disposeCamera();
    super.didPop();
  }

  Future<void> _initializeCamera() async {
    _setErrorMessage('');
    setState(() {
      _isCameraReady = false;
      _detectedObjects = [];
      _objectDescription = '';
    });
    try {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          _setErrorMessage("No cameras found.");
          _logger.w("ObjectDetectionScreen: No cameras found.");
          return;
        }

        final camera = cameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        );

        _cameraController = CameraController(
          camera,
          ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
        );

        await _cameraController!.initialize();
        setState(() {
          _isCameraReady = true;
        });
        _logger.i("ObjectDetectionScreen: Camera initialized successfully.");

        await _cameraController!.startImageStream(_processCameraImage);
      } else {
        _setErrorMessage("Camera permission denied.");
        _logger.w("ObjectDetectionScreen: Camera permission denied.");
      }
    } on CameraException catch (e) {
      _setErrorMessage('Error initializing camera: ${e.description}');
      _logger.e('Error initializing camera: $e');
    } catch (e) {
      _setErrorMessage('An unexpected error occurred during camera initialization: $e');
      _logger.e('Unexpected error: $e');
    }
  }

  Future<void> _initializeDetector() async {
    _logger.i("ObjectDetectionScreen: Initializing object detector.");
    final modelPath = await _getModelPath('assets/ml/ssd_mobilenet.tflite');
    // final labelPath = await _getLabelPath('assets/ml/coco_label.txt'); // labelPath is no longer a parameter for LocalObjectDetectorOptions

    final options = LocalObjectDetectorOptions(
      mode: DetectionMode.stream,
      modelPath: modelPath,
      // labelPath: labelPath, // Removed labelPath parameter as per new API
      classifyObjects: true,
      multipleObjects: true,
      confidenceThreshold: 0.5,
    );
    _objectDetector = ObjectDetector(options: options);
  }

  Future<String> _getModelPath(String assetPath) async {
    final path = '${(await getApplicationSupportDirectory()).path}/$assetPath';
    await Directory(path.substring(0, path.lastIndexOf('/'))).create(recursive: true);
    final byteData = await rootBundle.load(assetPath);
    final file = File(path);
    await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    return file.path;
  }

  Future<String> _getLabelPath(String assetPath) async {
    final path = '${(await getApplicationSupportDirectory()).path}/$assetPath';
    final byteData = await rootBundle.load(assetPath);
    final file = File(path);
    await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    return file.path;
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (_isProcessingFrame || !_isCameraReady || _objectDetector == null) return;

    setState(() {
      _isProcessingFrame = true;
      _errorMessage = '';
    });

    final inputImage = _inputImageFromCameraImage(cameraImage);

    if (inputImage == null) {
      setState(() {
        _isProcessingFrame = false;
      });
      return;
    }

    try {
      _detectedObjects = await _objectDetector!.processImage(inputImage);
      _logger.d("Detected objects: ${_detectedObjects.map((obj) => obj.labels.map((l) => l.text)).join(', ')}");

      if (_detectedObjects.isNotEmpty) {
        await _describeDetectedObjects();
      } else {
        setState(() {
          _objectDescription = "No objects detected.";
        });
      }
    } catch (e) {
      _logger.e("Error processing object detection: $e");
      _setErrorMessage("Error detecting objects.");
    } finally {
      setState(() {
        _isProcessingFrame = false;
      });
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }

    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      int rotationCompensation = _cameraController!.description.sensorOrientation;
      if (camera.lensDirection == CameraLensDirection.front) {
        // For front camera, compensate for the mirrored image
        rotationCompensation = (360 - rotationCompensation) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) {
      _logger.e("Failed to get image rotation for object detection.");
      return null;
    }

    final format = Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    final bytes = _concatenatePlanes(image.planes);

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  Future<void> _describeDetectedObjects() async {
    if (_detectedObjects.isEmpty) {
      setState(() {
        _objectDescription = "No objects to describe.";
      });
      return;
    }

    if (!_networkService.isOnline) {
      _setErrorMessage('No internet connection. Cannot describe objects.');
      return;
    }

    setState(() {
      _isProcessingAI = true;
      _objectDescription = 'Asking AI about objects...';
    });

    try {
      final objectNames = _detectedObjects.expand((obj) => obj.labels.map((l) => l.text)).toSet().join(', ');
      final prompt = "Describe the following objects: $objectNames. Provide a concise overview.";
      
      final String description = await _geminiService.getChatResponse([
        {'role': 'user', 'parts': [{'text': prompt}]}
      ]);

      setState(() {
        _objectDescription = description;
      });
      await _speechService.speak(description);
    } catch (e) {
      _setErrorMessage('Failed to describe objects: $e');
      _logger.e('Error describing objects with AI: $e');
    } finally {
      setState(() {
        _isProcessingAI = false;
      });
    }
  }

  void _setErrorMessage(String message) {
    if (mounted) {
      setState(() {
        _errorMessage = message;
      });
    }
  }

  void _disposeCamera() async {
    _logger.i("ObjectDetectionScreen: Disposing camera.");
    if (_cameraController != null) {
      try {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
        }
        await _cameraController!.dispose();
        _cameraController = null;
      } on CameraException catch (e) {
        _logger.e('Error disposing camera: ${e.description}');
        // Optionally set error message on UI
      }
    }
    setState(() {
      _isCameraReady = false;
      _detectedObjects = [];
      _objectDescription = '';
      _isProcessingAI = false;
      _errorMessage = '';
    });
  }

  @override
  void dispose() {
    _disposeCamera();
    _objectDetector?.close();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Object Detection',
          style: GoogleFonts.sourceCodePro(
            color: colorScheme.onPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: colorScheme.primary,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colorScheme.onPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: colorScheme.onPrimary),
            onPressed: () {
              _disposeCamera();
              _initializeCamera();
            },
            tooltip: 'Restart Camera',
          ),
          IconButton(
            icon: Icon(Icons.volume_up_rounded, color: colorScheme.onPrimary),
            onPressed: _objectDescription.isNotEmpty && !_isSpeaking
                ? () async {
                    await _speechService.speak(_objectDescription);
                  }
                : null,
            tooltip: 'Read Description',
          ),
          if (_isSpeaking)
            IconButton(
              icon: Icon(Icons.stop_rounded, color: colorScheme.error),
              onPressed: () => _speechService.stopSpeaking(),
              tooltip: 'Stop Speaking',
            ),
          IconButton(
            icon: Icon(Icons.clear_all_rounded, color: colorScheme.onPrimary),
            onPressed: () {
              setState(() {
                _detectedObjects = [];
                _objectDescription = '';
                _errorMessage = '';
              });
            },
            tooltip: 'Clear Results',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_isCameraReady && _cameraController != null && _cameraController!.value.isInitialized)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            )
          else
            Center(
              child: _errorMessage.isNotEmpty
                  ? Text(
                      _errorMessage,
                      style: textTheme.headlineSmall?.copyWith(color: colorScheme.error),
                      textAlign: TextAlign.center,
                    )
                  : CircularProgressIndicator(color: colorScheme.primary),
            ),
          // Bounding boxes and labels
          ..._detectedObjects.map((obj) {
            final rect = obj.boundingBox;
            final labels = obj.labels.map((l) => l.text).join(', ');
            return Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: CustomPaint(
                painter: BoundingBoxPainter(rect, labels, colorScheme.secondary),
              ),
            );
          }), // Removed unnecessary toList()
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              color: colorScheme.surface.withAlpha(204),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isProcessingAI)
                    LinearProgressIndicator(color: colorScheme.primary)
                  else
                    const SizedBox(height: 4),
                  const SizedBox(height: 8),
                  Text(
                    'Detected Objects:',
                    style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                  Text(
                    _objectDescription.isNotEmpty
                        ? _objectDescription
                        : (_detectedObjects.isEmpty ? 'No objects detected.' : 'Detecting objects...'),
                    style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isCameraReady && !_isProcessingAI && !_isSpeaking
            ? () async {
                _logger.i("User pressed FAB for object description.");
                if (_cameraController != null) {
                  _setErrorMessage('');
                  setState(() {
                    _isProcessingAI = true;
                    _objectDescription = 'Capturing image for detailed description...';
                  });
                  try {
                    final XFile imageFile = await _cameraController!.takePicture();
                    final bytes = await imageFile.readAsBytes();
                    final String base64Image = base64Encode(bytes);
                    final String description = await _geminiService.getVisionResponse(
                      "Describe this image in detail, focusing on all visible objects, their positions, and the overall scene. Be concise and accurate. Provide only the description, without conversational text.",
                      base64Image,
                    );
                    setState(() {
                      _objectDescription = description;
                    });
                    await _speechService.speak(description);
                  } catch (e) {
                    _setErrorMessage('Failed to get detailed description: $e');
                    _logger.e('Error during detailed object description: $e');
                  } finally {
                    setState(() {
                      _isProcessingAI = false;
                    });
                  }
                }
              }
            : null,
        tooltip: 'Describe Scene',
        backgroundColor: _isProcessingAI || _isSpeaking ? colorScheme.primary.withAlpha(128) : colorScheme.primary,
        child: _isProcessingAI
            ? CircularProgressIndicator(color: colorScheme.onPrimary)
            : Icon(Icons.photo_camera_rounded, color: colorScheme.onPrimary),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final Rect boundingBox;
  final String label;
  final Color color;

  BoundingBoxPainter(this.boundingBox, this.label, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRect(boundingBox, paint);

    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: color,
        fontSize: 14.0,
        backgroundColor: Colors.black54,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(boundingBox.left + 4, boundingBox.top + 4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
