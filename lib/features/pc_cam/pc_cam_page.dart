import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:flutter/services.dart'; // For DeviceOrientation if you need it for rotation logic
import 'package:logger/logger.dart'; // Import logger
import 'package:permission_handler/permission_handler.dart'; // Import for camera permission

class PcCamPage extends StatefulWidget {
  const PcCamPage({super.key});

  @override
  State<PcCamPage> createState() => _PcCamPageState();
}

class _PcCamPageState extends State<PcCamPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  ObjectDetector? _objectDetector;
  List<DetectedObject> _detectedObjects = [];
  bool _isInitialized = false;
  bool _isDisposed = false; // Flag to track if the controller has been disposed
  Size _imageSize = Size.zero; // Size of the image frames from the camera
  final _throttler = _Throttler(milliseconds: 300);
  final Logger _logger = Logger(); // Page-specific logger

  // For camera switching
  List<CameraDescription> _availableCameras = [];
  int _currentCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(
      this,
    ); // Add observer for lifecycle events
    _initObjectDetector();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeCamera();
      }
    });
  }

  // Initialize the Object Detector
  void _initObjectDetector() {
    _objectDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.stream, // Use stream mode for live detection
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
  }

  Future<void> _initializeCamera() async {
    if (!mounted) {
      _logger.w("Widget not mounted during camera initialization attempt.");
      return;
    }
    if (_isInitialized &&
        _cameraController != null &&
        _cameraController!.value.isInitialized &&
        !_isDisposed) {
      _logger.i("Camera already initialized, skipping re-initialization.");
      return;
    }

    _logger.i("Initializing camera...");
    setState(() {
      _isInitialized = false; // Show loading
      _isDisposed = false; // Reset disposed flag on successful initialization
    });

    // Add a small delay to allow previous camera instances to fully release resources
    await Future.delayed(const Duration(milliseconds: 500));

    final status = await Permission.camera.request();
    if (status.isGranted) {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        _logger.e("No cameras found on this device.");
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No cameras found.')));
        }
        return;
      }

      // Dispose existing controller if it exists and is initialized
      if (_cameraController != null) {
        await _disposeCamera(); // Use the robust dispose method
        _cameraController = null;
      }

      _cameraController = CameraController(
        _availableCameras[_currentCameraIndex],
        ResolutionPreset.medium, // Changed to medium for consistency
        enableAudio: false,
        imageFormatGroup:
            ImageFormatGroup.yuv420, // Optimal for ML Kit processing
      );

      try {
        await _cameraController!.initialize();
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
          _isDisposed = false;
        });
        _logger.i("Camera initialized successfully.");

        // Start image stream for live object detection
        if (!_cameraController!.value.isStreamingImages) {
          _cameraController!.startImageStream((CameraImage image) {
            _throttler.run(() {
              _processCameraImage(image);
            });
          });
        }
      } on CameraException catch (e) {
        _logger.e("Camera initialization failed: ${e.code}: ${e.description}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Camera error: ${e.description}')),
          );
        }
        if (mounted) {
          setState(() {
            _isInitialized = false;
          });
        }
      }
    } else {
      _logger.w("Camera permission denied for PcCamPage.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission denied.')),
        );
        setState(() {
          _isInitialized = false;
        });
      }
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!mounted || _objectDetector == null || _isDisposed) return;

    // Set the image size once
    if (_imageSize == Size.zero) {
      _imageSize = Size(image.width.toDouble(), image.height.toDouble());
    }

    final InputImageRotation rotation;
    switch (image.planes[0].bytesPerRow ~/ image.width) {
      case 1:
        rotation = InputImageRotation.rotation0deg;
        break;
      case 2:
        rotation = InputImageRotation.rotation90deg;
        break;
      case 4:
        rotation = InputImageRotation.rotation180deg;
        break;
      default:
        rotation = InputImageRotation.rotation270deg;
        break;
    }

    final InputImage inputImage = InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: _imageSize,
        rotation: rotation,
        format: InputImageFormat.nv21, // Assuming NV21 format from YUV420
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );

    try {
      final List<DetectedObject> objects = await _objectDetector!.processImage(
        inputImage,
      );
      if (mounted) {
        setState(() {
          _detectedObjects = objects;
        });
      }
    } catch (e) {
      _logger.e("Object detection failed: $e");
    }
  }

  Future<void> _switchCamera() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    setState(() {
      _isInitialized = false; // Set to false to show loading indicator
    });

    await _disposeCamera(); // Use the robust dispose method

    _currentCameraIndex = (_currentCameraIndex + 1) % _availableCameras.length;
    await Future.delayed(const Duration(milliseconds: 500)); // Added delay
    await _initializeCamera(); // Re-initialize with the new camera
  }

  Future<void> _disposeCamera() async {
    if (_cameraController == null || _isDisposed) {
      _logger.d(
        "Camera controller is already null or disposed. Skipping disposal.",
      );
      return;
    }
    _logger.i("Disposing camera controller for PcCamPage.");
    _isDisposed = true;

    if (_cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream().catchError(
        (e) => _logger.e("Error stopping image stream: $e"),
      );
    }
    await _cameraController!.dispose().catchError(
      (e) => _logger.e("Error disposing camera controller: $e"),
    );
    _cameraController = null;
    if (mounted) {
      setState(() {
        _isInitialized = false;
      });
    }
    _logger.i("Camera controller for PcCamPage successfully disposed.");
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.i("AppLifecycleState changed to: $state for PcCamPage.");
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isDisposed) {
      _logger.d(
        "Camera not initialized or already disposed during lifecycle change. Ignoring.",
      );
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _logger.i("App inactive, disposing camera controller.");
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _logger.i("App resumed, re-initializing camera controller.");
      // Added delay before re-initializing
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          await Future.delayed(const Duration(milliseconds: 500));
          _initializeCamera(); // Re-initialize on resume
        }
      });
    }
  }

  @override
  void dispose() {
    _logger.i(
      "PcCamPage disposed, releasing camera and object detector resources.",
    );
    WidgetsBinding.instance.removeObserver(this); // Remove observer
    _disposeCamera(); // Use robust dispose method
    _objectDetector?.close();
    _throttler.dispose(); // Dispose the throttler's timer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Object Detection')),
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_cameraController!)),
          CustomPaint(
            painter: ObjectPainter(_detectedObjects, _imageSize),
            child: Container(),
          ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: _switchCamera,
                child: const Text('Switch Camera'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ObjectPainter extends CustomPainter {
  final List<DetectedObject> detections;
  final Size previewSize;

  ObjectPainter(this.detections, this.previewSize);

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / previewSize.width;
    final scaleY = size.height / previewSize.height;

    final Paint paint =
        Paint()
          ..color =
              Colors
                  .red // Changed to red for better visibility
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0; // Increased stroke width

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

      // Draw background for the text
      final backgroundPaint = Paint()..color = Colors.black54;
      final textRect = Rect.fromLTWH(
        // Ensure text background is visible
        scaledRect.left,
        scaledRect.top - textPainter.height - 5, // 5 pixels padding above text
        textPainter.width + 10, // 10 pixels padding for text width
        textPainter.height + 5, // 5 pixels padding for text height
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(textRect, const Radius.circular(5)),
        backgroundPaint,
      );

      textPainter.paint(
        canvas,
        Offset(
          scaledRect.left + 5,
          scaledRect.top - textPainter.height - 2,
        ), // Position text with padding
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

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
      _timer?.cancel(); // Cancel previous delayed call
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
