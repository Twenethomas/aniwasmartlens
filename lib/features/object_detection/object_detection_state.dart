// lib/features/object_detection/object_detection_state.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:logger/logger.dart';

import '../../core/services/camera_service.dart';
import '../../core/utils/throttler.dart'; // Ensure this throttler utility is available

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

  // Initialize the throttler once when the state is created.
  // This ensures that the throttler maintains its internal state across calls.
  final Throttler _throttler = Throttler(milliseconds: 300);

  ObjectDetectionState(this._cameraService) {
    _cameraService.addListener(_onCameraServiceStatusChanged);
    _initializeObjectDetector();
  }

  // Getters for external access to the state
  List<DetectedObject> get detectedObjects =>
      List.unmodifiable(_detectedObjects);
  Size get imageSize => _imageSize;
  bool get isDetectorProcessing => _isDetectorProcessing;
  bool get isCameraInitialized => _cameraService.isCameraInitialized;
  bool get isStreamingImages => _cameraService.isStreamingImages;
  String? get cameraErrorMessage => _cameraService.cameraErrorMessage;

  /// Callback from CameraService to notify listeners of state changes.
  void _onCameraServiceStatusChanged() {
    if (_isDisposed) return;
    // Notify listeners that camera service status has changed.
    // UI components can then react to camera initialization, errors, etc.
    notifyListeners();
  }

  /// Initializes the camera via CameraService.
  /// This method is now primarily for the UI to request camera initialization.
  Future<void> initializeCamera() async {
    if (_isDisposed) return;
    if (!_cameraService.isCameraInitialized) {
      await _cameraService.initializeCamera();
    }
  }

  /// Starts streaming images from the camera to the object detector.
  Future<void> startImageStream() async {
    if (_isDisposed) return;
    if (!_cameraService.isCameraInitialized) {
      _logger.w("ObjectDetectionState: Camera not initialized. Cannot start stream.");
      return;
    }
    // CameraService handles checking if it's already streaming, so we just call it.
    // The _processCameraImage callback will be triggered by CameraService.
    await _cameraService.startImageStream(_processCameraImage);
    _logger.i("ObjectDetectionState: Started image stream.");
  }

  /// Stops streaming images from the camera.
  Future<void> stopImageStream() async {
    if (_isDisposed) return;
    await _cameraService.stopImageStream();
    _logger.i("ObjectDetectionState: Stopped image stream.");
  }

  /// Disposes the camera and stops the stream via CameraService.
  Future<void> disposeCamera() async {
    if (_isDisposed) return;
    await stopImageStream();
    await _cameraService.disposeCamera();
    _logger.i("ObjectDetectionState: Disposed camera.");
  }

  /// Initializes the Google ML Kit ObjectDetector.
  void _initializeObjectDetector() {
    _logger.i("ObjectDetectionState: Initializing object detector.");
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
      // You can add confidenceThreshold here if needed, e.g., confidenceThreshold: 0.5,
    );
    _objectDetector = ObjectDetector(options: options);
    _logger.i("ObjectDetectionState: Object detector initialized.");
  }

  /// Processes each camera image frame for object detection.
  /// This method is called by the CameraService's image stream.
  Future<void> _processCameraImage(CameraImage cameraImage) async {
    // Return early if the detector is already processing or if the state is disposed.
    if (_isDetectorProcessing || _isDisposed) {
      _logger.d("ObjectDetectionState: Skipping frame. Detector processing: $_isDetectorProcessing, Disposed: $_isDisposed");
      return;
    }
    _isDetectorProcessing = true; // Set processing flag

    // Use the *initialized* throttler instance to control processing rate.
    _throttler.run(() async {
      // Re-check dispose status inside the throttler's callback, as it might
      // have been disposed while waiting for the throttle delay.
      if (_isDisposed) {
        _isDetectorProcessing = false;
        return;
      }

      final cameraController = _cameraService.cameraController;
      if (cameraController == null) {
        _logger.e("ObjectDetectionState: CameraController is null. Cannot process image.");
        _isDetectorProcessing = false;
        return;
      }

      final inputImage = _inputImageFromCameraImage(cameraImage);
      if (inputImage == null) {
        _logger.w("ObjectDetectionState: Failed to create InputImage. Skipping detection for this frame.");
        _isDetectorProcessing = false;
        return;
      }

      try {
        _logger.d("ObjectDetectionState: Processing image for object detection.");
        final objects = await _objectDetector!.processImage(inputImage);

        // Only update state and notify listeners if the state is still active.
        if (!_isDisposed) {
          _detectedObjects = objects;
          _imageSize = Size(
            cameraImage.width.toDouble(),
            cameraImage.height.toDouble(),
          );
          notifyListeners(); // Notify UI of new detected objects and image size
          _logger.d("ObjectDetectionState: Detected ${objects.length} objects.");
        }
      } catch (e, stack) {
        _logger.e("ObjectDetectionState: Error processing image: $e", error: e, stackTrace: stack);
      } finally {
        _isDetectorProcessing = false; // Reset processing flag
      }
    });
  }

  /// Helper to concatenate image planes into a single Uint8List for ML Kit
  /// This is typically needed for YUV formats like NV21 on Android.
  Uint8List _concatenatePlanes(List<Plane> planes) {
    final allBytes = ui.WriteBuffer();
    for (Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  /// Converts a CameraImage to an ML Kit InputImage format.
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final cameraController = _cameraService.cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      _logger.e(
        "ObjectDetectionState: CameraController not initialized when creating InputImage.",
      );
      return null;
    }

    // Determine the image format based on the platform.
    final InputImageFormat imageFormat;
    if (ui.defaultTargetPlatform == ui.TargetPlatform.android) {
      imageFormat = InputImageFormat.nv21;
    } else if (ui.defaultTargetPlatform == ui.TargetPlatform.iOS) {
      imageFormat = InputImageFormat.bgra8888;
    } else {
      _logger.e("Unsupported platform for CameraImage format.");
      return null;
    }

    // Determine the image rotation based on the camera orientation and device orientation.
    final InputImageRotation rotation;
    // The sensor orientation is typically a fixed value for a given camera.
    // The image rotation might need adjustment based on device orientation,
    // but ML Kit often handles this internally if correct metadata is provided.
    // For simplicity, we use sensor orientation directly for now, with front camera mirroring.
    if (ui.defaultTargetPlatform == ui.TargetPlatform.iOS) {
      // iOS usually provides image frames already correctly oriented.
      rotation =
          InputImageRotationValue.fromRawValue(
            cameraController.description.sensorOrientation,
          )!;
    } else if (ui.defaultTargetPlatform == ui.TargetPlatform.android) {
      // Android often requires rotation compensation.
      int rotationCompensation = cameraController.description.sensorOrientation;
      if (cameraController.description.lensDirection ==
          CameraLensDirection.front) {
        // Front camera image needs mirroring horizontally, which affects rotation.
        // This effectively mirrors the image and applies the correct rotation.
        rotationCompensation = (360 - rotationCompensation) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation)!;
    } else {
      rotation = InputImageRotation.rotation0deg; // Default for other platforms
    }

    // For NV21 (Android), all planes must be passed.
    // For BGRA8888 (iOS), only the first plane's bytes are needed.
    final Uint8List bytes;
    if (imageFormat == InputImageFormat.nv21) {
      bytes = _concatenatePlanes(image.planes);
    } else {
      bytes = image.planes.first.bytes;
    }

    final inputImageData = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      format: imageFormat,
      bytesPerRow: image.planes.first.bytesPerRow,
      rotation: rotation, // Required for some formats like NV21
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
  }

  @override
  void dispose() {
    _logger.i("ObjectDetectionState: Disposing.");
    _isDisposed = true; // Set dispose flag immediately
    _objectDetector?.close(); // Close the ML Kit detector
    _cameraService.removeListener(_onCameraServiceStatusChanged);
    _throttler.dispose(); // Dispose the throttler's timer
    // Ensure camera is disposed when the state is disposed
    // This calls stopImageStream and disposeCamera internally
    disposeCamera();
    super.dispose();
  }
}
