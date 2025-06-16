// lib/features/object_detection/object_detection_state.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:logger/logger.dart';

import '../../core/services/camera_service.dart';
import '../../core/utils/throttler.dart';

/// State management for object detection feature, handling camera resource management,
/// object detection processing, and UI state updates.
class ObjectDetectionState extends ChangeNotifier {
  final CameraService _cameraService;
  final Logger _logger = Logger();

  ObjectDetector? _objectDetector;
  List<DetectedObject> _detectedObjects = [];
  Size _imageSize = Size.zero;
  bool _isDetectorProcessing = false;
  bool _isDisposed = false;

  final Throttler _throttler = Throttler(milliseconds: 300);

  // Stream subscription for camera image stream
  StreamSubscription<CameraImage>? _imageStreamSubscription;

  ObjectDetectionState(this._cameraService) {
    _cameraService.addListener(_onCameraServiceStatusChanged);
    _initializeObjectDetector();
  }

  List<DetectedObject> get detectedObjects =>
      List.unmodifiable(_detectedObjects);
  Size get imageSize => _imageSize;
  bool get isDetectorProcessing => _isDetectorProcessing;
  bool get isCameraInitialized => _cameraService.isCameraInitialized;
  bool get isStreamingImages => _cameraService.isStreamingImages;
  String? get cameraErrorMessage => _cameraService.cameraErrorMessage;

  void _onCameraServiceStatusChanged() {
    if (_isDisposed) return;
    notifyListeners();
  }

  Future<void> initializeCamera() async {
    if (_isDisposed) return;
    if (!_cameraService.isCameraInitialized) {
      await _cameraService.initializeCamera();
    }
  }

  Future<void> startImageStream() async {
    if (_isDisposed) return;
    if (!_cameraService.isCameraInitialized) {
      _logger.w("ObjectDetectionState: Camera not initialized.");
      return;
    }
    if (_cameraService.isStreamingImages) {
      _logger.i("ObjectDetectionState: Image stream already active.");
      return;
    }
    _imageStreamSubscription = _cameraService.startImageStream(
      _processCameraImage,
    ) as StreamSubscription<CameraImage>?;
  }

  Future<void> stopImageStream() async {
    if (_isDisposed) return;
    await _imageStreamSubscription?.cancel();
    _imageStreamSubscription = null;
    await _cameraService.stopImageStream();
  }

  Future<void> disposeCamera() async {
    if (_isDisposed) return;
    await stopImageStream();
    await _cameraService.disposeCamera();
  }

  void _initializeObjectDetector() {
    _logger.i("ObjectDetectionState: Initializing object detector.");
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);
  }

  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (_isDetectorProcessing || _isDisposed) return;
    _isDetectorProcessing = true;

    _throttler.run(() async {
      if (_isDisposed) return;

      final cameraController = _cameraService.cameraController;
      if (cameraController == null) {
        _logger.e("ObjectDetectionState: CameraController is null.");
        _isDetectorProcessing = false;
        return;
      }

      final inputImage = _inputImageFromCameraImage(cameraImage);
      if (inputImage == null) {
        _logger.w("ObjectDetectionState: Failed to create InputImage.");
        _isDetectorProcessing = false;
        return;
      }

      try {
        final objects = await _objectDetector!.processImage(inputImage);
        _detectedObjects = objects;
        _imageSize = Size(
          cameraImage.width.toDouble(),
          cameraImage.height.toDouble(),
        );
        notifyListeners();
      } catch (e) {
        _logger.e("ObjectDetectionState: Error processing image: $e");
      } finally {
        _isDetectorProcessing = false;
      }
    });
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final cameraController = _cameraService.cameraController;
    if (cameraController == null) {
      _logger.e(
        "ObjectDetectionState: CameraController is null when creating InputImage.",
      );
      return null;
    }

    final plane = image.planes.first;
    final bytes = plane.bytes;

    final imageFormat =
        cameraController.description.sensorOrientation == 90
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888;

    final inputImageData = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: InputImageRotation.rotation0deg,
      format: imageFormat,
      bytesPerRow: plane.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
  }

  @override
  void dispose() {
    _logger.i("ObjectDetectionState: Disposing.");
    _isDisposed = true;
    _throttler.dispose();
    _objectDetector?.close();
    _cameraService.removeListener(_onCameraServiceStatusChanged);
    disposeCamera();
    super.dispose();
  }
}
