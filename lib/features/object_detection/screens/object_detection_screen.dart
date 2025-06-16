// lib/features/pc_cam/screens/object_detection_screen.dart
import 'dart:async';
import 'dart:io';
// For base64Encode
// For Uint8List and WriteBuffer
// For WriteBuffer

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:assist_lens/main.dart'; // For routeObserver and logger
import 'package:assist_lens/core/services/network_service.dart';
import 'package:assist_lens/core/services/gemini_service.dart';
import 'package:assist_lens/core/services/speech_service.dart';
import 'package:assist_lens/core/services/camera_service.dart'; // Import CameraService

class ObjectDetectionScreen extends StatefulWidget {
  final bool autoStartLive;

  const ObjectDetectionScreen({super.key, this.autoStartLive = false});

  @override
  State<ObjectDetectionScreen> createState() => _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen>
    with RouteAware, WidgetsBindingObserver {
  late CameraService
  _cameraService; // Use CameraService instead of CameraController
  ObjectDetector? _objectDetector;
  List<DetectedObject> _detectedObjects = [];
  String _objectDescription = '';
  String _errorMessage = '';
  bool _isProcessingFrame = false;
  bool _isProcessingAI = false;
  bool _isSpeaking = false;
  bool _isDisposed = false;

  final Logger _logger = logger;
  final _throttler = _Throttler(milliseconds: 300);

  late NetworkService _networkService;
  late GeminiService _geminiService;
  late SpeechService _speechService;

  Size _imageSize = Size.zero;
  Size get imageSize => _imageSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize services
      _networkService = Provider.of<NetworkService>(context, listen: false);
      _geminiService = Provider.of<GeminiService>(context, listen: false);
      _speechService = Provider.of<SpeechService>(context, listen: false);
      _cameraService = CameraService(); // Get singleton instance

      // Listen to speech service status
      _speechService.speakingStatusStream.listen((status) {
        if (mounted) {
          setState(() {
            _isSpeaking = status;
          });
        }
      });

      // Listen to camera service changes
      _cameraService.addListener(_onCameraServiceChanged);

      _initializeDetector();

      // Initialize camera if autoStartLive is true
      if (widget.autoStartLive) {
        _logger.i(
          "ObjectDetectionScreen: autoStartLive is true, initializing camera immediately.",
        );
        _initializeCamera();
      }
    });
  }

  void _onCameraServiceChanged() {
    if (!mounted) return;

    setState(() {
      _errorMessage = _cameraService.cameraErrorMessage ?? '';
      // Update image size when camera is initialized
      if (_cameraService.isCameraInitialized &&
          _cameraService.cameraController != null) {
        _imageSize =
            _cameraService.cameraController!.value.previewSize ?? Size.zero;
      } else {
        _imageSize = Size.zero;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    } else {
      _logger.w(
        "ObjectDetectionScreen: Cannot subscribe to RouteObserver, current route is not a PageRoute.",
      );
    }
  }

  @override
  void didPush() {
    _logger.i(
      "ObjectDetectionScreen: didPush - Page is active. Re-initializing camera.",
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeCamera();
      }
    });
    super.didPush();
  }

  @override
  void didPopNext() {
    _logger.i(
      "ObjectDetectionScreen: didPopNext - Returning to page. Re-initializing camera.",
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeCamera();
      }
    });
    super.didPopNext();
  }

  @override
  void didPushNext() {
    _logger.i(
      "ObjectDetectionScreen: didPushNext - Navigating away from page. Stopping camera stream.",
    );
    _stopImageStream();
    super.didPushNext();
  }

  @override
  void didPop() {
    _logger.i("ObjectDetectionScreen: didPop - Page is being popped.");
    _stopImageStream();
    super.didPop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.i(
      "AppLifecycleState changed to: $state for ObjectDetectionScreen.",
    );

    if (state == AppLifecycleState.inactive) {
      _logger.i("App inactive, stopping image stream.");
      _stopImageStream();
    } else if (state == AppLifecycleState.resumed) {
      _logger.i("App resumed, restarting image stream.");
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          // A small delay to allow camera resources to be fully released/acquired
          await Future.delayed(const Duration(milliseconds: 500));
          _startImageStream();
        }
      });
    }
  }

  Future<void> _initializeCamera() async {
    if (_isDisposed) {
      _logger.w(
        "ObjectDetectionScreen: Cannot initialize camera, widget is disposed.",
      );
      return;
    }

    // Check if camera is already initialized and streaming
    if (_cameraService.isCameraInitialized &&
        _cameraService.isStreamingImages) {
      _logger.i(
        "ObjectDetectionScreen: Camera already initialized and streaming. Skipping re-initialization.",
      );
      return;
    }

    _setErrorMessage('');
    setState(() {
      _detectedObjects = [];
      _objectDescription = '';
    });

    try {
      // Initialize camera using CameraService
      await _cameraService.initializeCamera();

      // Ensure widget is still mounted before checking camera state and starting stream
      if (!mounted) return;

      if (_cameraService.isCameraInitialized) {
        _logger.i(
          "ObjectDetectionScreen: Camera initialized successfully via CameraService.",
        );
        _startImageStream();
      } else {
        _setErrorMessage(
          _cameraService.cameraErrorMessage ?? "Failed to initialize camera.",
        );
      }
    } catch (e) {
      if (!mounted) return; // Check mounted after async operation
      _setErrorMessage(
        'An unexpected error occurred during camera initialization: $e',
      );
      _logger.e('Unexpected error: $e');
    }
  }

  Future<void> _startImageStream() async {
    if (!mounted ||
        !_cameraService.isCameraInitialized ||
        _cameraService.isStreamingImages) {
      _logger.i(
        "ObjectDetectionScreen: Camera not ready or already streaming.",
      );
      return;
    }

    try {
      await _cameraService.startImageStream((CameraImage image) {
        _throttler.run(() {
          _processCameraImage(image);
        });
      });
      _logger.i("ObjectDetectionScreen: Camera image stream started.");
    } catch (e) {
      if (!mounted) return; // Check mounted after async operation
      _logger.e("Error starting image stream: $e");
      _setErrorMessage("Failed to start live camera feed.");
    }
  }

  Future<void> _stopImageStream() async {
    try {
      await _cameraService.stopImageStream();
      _logger.i("ObjectDetectionScreen: Camera image stream stopped.");
    } catch (e) {
      _logger.e("Error stopping image stream: $e");
    }
  }

  Future<void> _initializeDetector() async {
    _logger.i("ObjectDetectionScreen: Initializing object detector.");
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    // Check mounted early to prevent processing frames if widget is disposed
    if (!mounted ||
        _isDisposed ||
        _isProcessingFrame ||
        !_cameraService.isCameraInitialized ||
        _objectDetector == null) {
      return;
    }

    setState(() {
      _isProcessingFrame = true;
      _errorMessage = '';
    });

    // Update image size if needed
    if (_imageSize == Size.zero && _cameraService.cameraController != null) {
      _imageSize =
          _cameraService.cameraController!.value.previewSize ?? Size.zero;
    }

    final inputImage = _inputImageFromCameraImage(cameraImage);

    if (inputImage == null) {
      if (mounted) {
        // Ensure mounted before setState
        setState(() {
          _isProcessingFrame = false;
        });
      }
      return;
    }

    try {
      _detectedObjects = await _objectDetector!.processImage(inputImage);
      _logger.d(
        "Detected objects: ${_detectedObjects.map((obj) => obj.labels.map((l) => l.text)).join(', ')}",
      );
    } catch (e) {
      _logger.e("Error processing object detection frame: $e");
    } finally {
      if (mounted) {
        // Ensure mounted before setState in finally block
        setState(() {
          _isProcessingFrame = false;
        });
      }
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (!_cameraService.isCameraInitialized ||
        _cameraService.cameraController == null ||
        _isDisposed) {
      return null;
    }

    final camera = _cameraService.cameraController!.description;
    final InputImageRotation mlKitRotation;

    if (Platform.isIOS) {
      mlKitRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation)!;
    } else if (Platform.isAndroid) {
      int rotationCompensation = camera.sensorOrientation;
      // For front camera, compensate for the mirrored preview
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (360 - rotationCompensation) % 360;
      }
      mlKitRotation =
          InputImageRotationValue.fromRawValue(rotationCompensation)!;
    } else {
      mlKitRotation = InputImageRotation.rotation0deg;
    }

    // Determine the correct image format based on platform
    final format =
        Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    final bytes = _concatenatePlanes(image.planes);

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: mlKitRotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final ui.WriteBuffer allBytes = ui.WriteBuffer();
    for (Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  Future<void> _describeCurrentDetectedObjects() async {
    if (_detectedObjects.isEmpty) {
      setState(() {
        _objectDescription = "No objects currently detected to describe.";
      });
      await _speechService.speak("No objects currently detected to describe.");
      return;
    }

    if (!_networkService.isOnline) {
      _setErrorMessage('No internet connection. Cannot describe objects.');
      await _speechService.speak(
        "No internet connection. Cannot describe objects.",
      );
      return;
    }

    if (mounted) {
      // Ensure mounted before setting state
      setState(() {
        _isProcessingAI = true;
        _objectDescription = 'Asking AI about current objects...';
      });
    }

    try {
      final objectNames = _detectedObjects
          .expand((obj) => obj.labels.map((l) => l.text))
          .toSet()
          .join(', ');
      final prompt =
          "Describe the following objects: $objectNames. Provide a concise overview.";

      final String description = await _geminiService.getChatResponse([
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ]);

      if (mounted) {
        setState(() {
          _objectDescription = description;
        });
        await _speechService.speak(description);
      }
    } catch (e, st) {
      if (mounted) {
        // Ensure mounted before setting error message and state
        _setErrorMessage('Failed to describe objects: ${e.toString()}');
        setState(() {
          _objectDescription = "Error describing objects.";
        });
        await _speechService.speak(
          "An error occurred while describing objects. Please try again.",
        );
      }
      _logger.e(
        'Error describing objects with AI: $e',
        error: e,
        stackTrace: st,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingAI = false;
        });
      }
    }
  }

  void _setErrorMessage(String message) {
    if (mounted) {
      setState(() {
        _errorMessage = message;
      });
    }
  }

  @override
  void dispose() {
    _logger.i("ObjectDetectionScreen: Disposing resources.");
    _isDisposed = true; // Set flag early

    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);

    // Remove listener from camera service
    _cameraService.removeListener(_onCameraServiceChanged);

    // Stop image stream but don't dispose the camera service (it's a singleton)
    // The CameraService itself will dispose of its controller when the app closes or is explicitly told to.
    _stopImageStream();

    _objectDetector?.close();
    _throttler.dispose();
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
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colorScheme.onPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: colorScheme.onPrimary),
            onPressed: () => _initializeCamera(),
            tooltip: 'Restart Camera',
          ),
          IconButton(
            icon: Icon(Icons.volume_up_rounded, color: colorScheme.onPrimary),
            onPressed:
                _objectDescription.isNotEmpty && !_isSpeaking
                    ? () async => await _speechService.speak(_objectDescription)
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
          // Add camera switch button
          IconButton(
            icon: Icon(
              Icons.flip_camera_ios_rounded,
              color: colorScheme.onPrimary,
            ),
            onPressed:
                _cameraService.isCameraInitialized
                    ? () async {
                      _logger.i(
                        "ObjectDetectionScreen: Initiating camera switch.",
                      );
                      await _stopImageStream();
                      await _cameraService.toggleCamera();
                      if (mounted && _cameraService.isCameraInitialized) {
                        _logger.i(
                          "ObjectDetectionScreen: Camera switched, attempting to restart stream.",
                        );
                        await _startImageStream();
                      } else if (mounted) {
                        _logger.w(
                          "ObjectDetectionScreen: Camera switch failed or widget unmounted, not restarting stream.",
                        );
                      }
                    }
                    : null,
            tooltip: 'Switch Camera',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_cameraService.isCameraInitialized &&
              _cameraService.cameraController != null)
            Positioned.fill(
              child: CameraPreview(_cameraService.cameraController!),
            )
          else
            Center(
              child:
                  _errorMessage.isNotEmpty
                      ? Text(
                        _errorMessage,
                        style: textTheme.headlineSmall?.copyWith(
                          color: colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      )
                      : CircularProgressIndicator(color: colorScheme.primary),
            ),
          // Bounding boxes and labels
          Positioned.fill(
            child: CustomPaint(
              painter: ObjectBoxPainter(
                _detectedObjects,
                imageSize,
                _cameraService
                        .cameraController
                        ?.description
                        .sensorOrientation ??
                    0,
                _cameraService.cameraController?.description.lensDirection ??
                    CameraLensDirection.back,
                colorScheme.secondary,
              ),
            ),
          ),
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
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    _objectDescription.isNotEmpty
                        ? _objectDescription
                        : (_detectedObjects.isEmpty && !_isProcessingFrame
                            ? 'No objects detected.'
                            : (_isProcessingFrame
                                ? 'Detecting objects...'
                                : 'Ready.')),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed:
            _cameraService.isCameraInitialized &&
                    !_isProcessingAI &&
                    !_isSpeaking
                ? _describeCurrentDetectedObjects
                : null,
        tooltip: 'Describe Detected Objects',
        backgroundColor:
            _isProcessingAI || _isSpeaking
                ? colorScheme.primary.withAlpha(128)
                : colorScheme.primary,
        child:
            _isProcessingAI
                ? CircularProgressIndicator(color: colorScheme.onPrimary)
                : Icon(Icons.camera_alt_rounded, color: colorScheme.onPrimary),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// Separate painter for drawing bounding boxes and labels
class ObjectBoxPainter extends CustomPainter {
  final List<DetectedObject> detections;
  final Size cameraPreviewSize;
  final int sensorOrientation;
  final CameraLensDirection lensDirection;
  final Color boxColor;

  ObjectBoxPainter(
    this.detections,
    this.cameraPreviewSize,
    this.sensorOrientation,
    this.lensDirection,
    this.boxColor,
  );

  @override
  void paint(Canvas canvas, Size widgetSize) {
    if (cameraPreviewSize == Size.zero) return;

    final double scaleX = widgetSize.width / cameraPreviewSize.width;
    final double scaleY = widgetSize.height / cameraPreviewSize.height;

    final Paint paint =
        Paint()
          ..color = boxColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;

    final TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: 16.0,
      fontWeight: FontWeight.bold,
      shadows: [
        Shadow(
          blurRadius: 3.0,
          color: Colors.black.withOpacity(0.8),
          offset: const Offset(1.0, 1.0),
        ),
      ],
    );

    final matrix = Matrix4.identity();
    if (lensDirection == CameraLensDirection.front) {
      // For front camera, mirror the X-axis to correctly display bounding boxes
      matrix.setEntry(0, 0, -1);
      matrix.setEntry(0, 3, widgetSize.width);
    }

    canvas.save();
    canvas.transform(matrix.storage);

    for (var object in detections) {
      final Rect scaledRect = Rect.fromLTRB(
        object.boundingBox.left * scaleX,
        object.boundingBox.top * scaleY,
        object.boundingBox.right * scaleX,
        object.boundingBox.bottom * scaleY,
      );

      canvas.drawRect(scaledRect, paint);

      final label =
          object.labels.isNotEmpty
              ? "${object.labels.first.text} (${(object.labels.first.confidence * 100).toStringAsFixed(1)}%)"
              : "Unknown";

      final textPainter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final backgroundPaint = Paint()..color = Colors.black54;
      final textRect = Rect.fromLTWH(
        scaledRect.left,
        scaledRect.top - textPainter.height - 5,
        textPainter.width + 10,
        textPainter.height + 5,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(textRect, const Radius.circular(5)),
        backgroundPaint,
      );

      textPainter.paint(
        canvas,
        Offset(scaledRect.left + 5, scaledRect.top - textPainter.height - 2),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Throttler class to limit the rate of image processing
class _Throttler {
  final int milliseconds;
  DateTime? _lastRun;
  Timer? _timer;

  _Throttler({required this.milliseconds});

  void run(VoidCallback action) {
    if (_lastRun == null ||
        DateTime.now().difference(_lastRun!) >
            Duration(milliseconds: milliseconds)) {
      _lastRun = DateTime.now();
      action();
    } else {
      _timer?.cancel();
      _timer = Timer(Duration(milliseconds: milliseconds), () {
        _lastRun = DateTime.now();
        action();
      });
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}
