// lib/core/services/camera_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../main.dart'; // For global logger

/// A singleton service to manage the CameraController and camera lifecycle
/// across the application. This ensures only one CameraController is active
/// at a time and handles resource management robustly.
class CameraService extends ChangeNotifier {
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  int _currentCameraIndex = 0; // 0 for back, 1 for front (if available)
  bool _isCameraInitialized = false;
  bool _isStreamingImages = false;
  String? _cameraErrorMessage;
  FlashMode _currentFlashMode = FlashMode.off;

  final Logger _logger = logger; // Use the global logger

  // Private constructor for the singleton pattern
  CameraService._privateConstructor() {
    _initCameras(); // Initialize available cameras on service creation
  }

  // The single instance of the CameraService
  static final CameraService _instance = CameraService._privateConstructor();

  // Factory constructor to return the singleton instance
  factory CameraService() {
    return _instance;
  }

  // Getters for external access
  CameraController? get cameraController => _cameraController;
  bool get isCameraInitialized => _isCameraInitialized;
  bool get isStreamingImages => _isStreamingImages;
  String? get cameraErrorMessage => _cameraErrorMessage;
  bool get isFlashOn => _currentFlashMode == FlashMode.torch;

  /// Initializes the list of available cameras on the device.
  Future<void> _initCameras() async {
    _logger.i("CameraService: Discovering available cameras...");
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        _cameraErrorMessage = "No cameras found on this device.";
        _logger.e("CameraService: No cameras available.");
      } else {
        _logger.i("CameraService: Found ${_availableCameras.length} cameras.");
      }
    } catch (e) {
      _cameraErrorMessage = "Failed to get available cameras: $e";
      _logger.e("CameraService: Error getting cameras: $e");
    } finally {
      _postFrameNotifyListeners(); // Notify listeners of camera availability
    }
  }

  /// Initializes the camera controller with a specific lens direction.
  /// Disposes any existing controller before initializing a new one.
  Future<void> initializeCamera({
    CameraLensDirection lensDirection = CameraLensDirection.back,
  }) async {
    _logger.i(
      "CameraService: Attempting to initialize camera with lens direction: $lensDirection",
    );

    // Prevent multiple initializations if already in progress or initialized
    if (_isCameraInitialized &&
        _cameraController != null &&
        _cameraController!.value.isInitialized &&
        _cameraController!.description.lensDirection == lensDirection) {
      _logger.d(
        "CameraService: Camera already initialized and matches requested direction. Skipping initialization.",
      );
      return;
    }
    if (_cameraController != null && !_cameraController!.value.isInitialized) {
      _logger.d(
        "CameraService: Camera controller exists but not initialized. Disposing before re-init.",
      );
      await disposeCamera(); // Ensure a clean slate
    }

    // Reset state before starting new initialization
    _isCameraInitialized = false;
    _isStreamingImages = false;
    _cameraErrorMessage = null;
    _postFrameNotifyListeners(); // Notify immediate state change

    try {
      final status = await Permission.camera.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        _cameraErrorMessage =
            "Camera permission denied. Please enable it in settings.";
        _logger.e("CameraService: Camera permission denied.");
        _postFrameNotifyListeners();
        return;
      }

      // Ensure _availableCameras is populated
      if (_availableCameras.isEmpty) {
        await _initCameras(); // Try to initialize cameras again if empty
        if (_availableCameras.isEmpty) {
          // Check again after attempt
          _cameraErrorMessage =
              "No cameras found on this device after re-check.";
          _logger.e("CameraService: No cameras available after re-check.");
          _postFrameNotifyListeners();
          return;
        }
      }

      // Find the camera that matches the requested lens direction
      CameraDescription? selectedCamera;
      if (_availableCameras.isNotEmpty) {
        selectedCamera = _availableCameras.firstWhere(
          (camera) => camera.lensDirection == lensDirection,
          orElse:
              () =>
                  _availableCameras
                      .first, // Fallback to first available if not found
        );
        _currentCameraIndex = _availableCameras.indexOf(selectedCamera);
      }

      if (selectedCamera == null) {
        _cameraErrorMessage =
            "No suitable camera found for direction: $lensDirection";
        _logger.e(
          "CameraService: No camera found matching requested direction.",
        );
        _postFrameNotifyListeners();
        return;
      }

      // Initialize the new camera controller
      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium, // Adjust resolution as needed
        enableAudio:
            false, // Audio not typically needed for object detection/text reader
        imageFormatGroup: ImageFormatGroup.yuv420, // Common for ML Kit
      );

      await _cameraController!.initialize();
      _isCameraInitialized = true;
      _currentFlashMode =
          _cameraController!.value.flashMode; // Get initial flash mode
      _logger.i(
        "CameraService: Camera initialized successfully: ${selectedCamera.name}",
      );
    } on CameraException catch (e) {
      _cameraErrorMessage = "Failed to initialize camera: ${e.description}";
      _logger.e("CameraService: Camera initialization error: ${e.description}");
      _isCameraInitialized = false; // Ensure state is false on error
    } catch (e) {
      _cameraErrorMessage =
          "An unexpected error occurred during camera initialization: $e";
      _logger.e(
        "CameraService: Unexpected error during camera initialization: $e",
      );
      _isCameraInitialized = false; // Ensure state is false on error
    } finally {
      _postFrameNotifyListeners(); // Always notify after initialization attempt
    }
  }

  /// Starts streaming images from the camera.
  /// [onImageAvailable]: A callback function to receive each camera image.
  /// NOTE: This method is designed to be called by a consumer.
  /// The consumer should also manage its StreamSubscription if using a stream.
  Future<void> startImageStream(
    Function(CameraImage image) onImageAvailable,
  ) async {
    if (!_isCameraInitialized ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      _logger.w("CameraService: Camera not initialized. Cannot start stream.");
      _cameraErrorMessage = "Camera not ready to stream.";
      _postFrameNotifyListeners();
      return;
    }
    if (_isStreamingImages) {
      _logger.i("CameraService: Image stream already active.");
      return;
    }
    _logger.i("CameraService: Starting image stream.");
    try {
      await _cameraController!.startImageStream(onImageAvailable);
      _isStreamingImages = true;
      _cameraErrorMessage =
          null; // Clear any previous errors on successful start
      _logger.i("CameraService: Image stream started successfully.");
    } on CameraException catch (e) {
      _cameraErrorMessage = "Failed to start camera stream: ${e.description}";
      _logger.e("CameraService: Error starting image stream: ${e.description}");
    } catch (e) {
      _cameraErrorMessage =
          "An unexpected error occurred during stream start: $e";
      _logger.e("CameraService: Unexpected error during stream start: $e");
    } finally {
      _postFrameNotifyListeners();
    }
  }

  /// Stops streaming images from the camera.
  Future<void> stopImageStream() async {
    if (!_isStreamingImages ||
        _cameraController == null ||
        !_cameraController!.value.isStreamingImages) {
      _logger.w("CameraService: Image stream not active. Nothing to stop.");
      return;
    }
    _logger.i("CameraService: Stopping image stream.");
    try {
      await _cameraController!.stopImageStream();
      _isStreamingImages = false;
      _cameraErrorMessage = null; // Clear error on successful stop
      _logger.i("CameraService: Image stream stopped successfully.");
    } on CameraException catch (e) {
      _cameraErrorMessage = "Failed to stop camera stream: ${e.description}";
      _logger.e("CameraService: Error stopping image stream: ${e.description}");
    } catch (e) {
      _cameraErrorMessage =
          "An unexpected error occurred during stream stop: $e";
      _logger.e("CameraService: Unexpected error during stream stop: $e");
    } finally {
      _postFrameNotifyListeners();
    }
  }

  /// Takes a single picture and returns the XFile.
  /// Stops any ongoing image stream before taking the picture.
  ///
  /// Returns an [XFile] containing the captured image, or `null` if capture fails.
  Future<XFile?> takePicture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _logger.w("CameraService: Camera not initialized. Cannot take picture.");
      _cameraErrorMessage = "Camera not ready to take picture.";
      _postFrameNotifyListeners();
      return null;
    }

    if (_cameraController!.value.isTakingPicture) {
      _logger.w("CameraService: Already taking a picture.");
      return null;
    }

    _logger.i("CameraService: Attempting to take picture.");
    // Stop any ongoing stream to avoid conflicts during picture capture
    if (_isStreamingImages) {
      await stopImageStream();
    }

    try {
      final XFile file = await _cameraController!.takePicture();
      _logger.i("CameraService: Picture taken successfully: ${file.path}");
      _cameraErrorMessage = null;
      _postFrameNotifyListeners(); // Notify state update after picture taken
      return file;
    } on CameraException catch (e) {
      _cameraErrorMessage = "Failed to take picture: ${e.description}";
      _logger.e("CameraService: Error taking picture: ${e.description}");
      _postFrameNotifyListeners();
      return null;
    } catch (e) {
      _cameraErrorMessage =
          "An unexpected error occurred during picture capture: $e";
      _logger.e("CameraService: Unexpected error during picture capture: $e");
      _postFrameNotifyListeners();
      return null;
    }
  }

  /// Toggles the camera between front and back.
  /// This method serves as the 'switchCamera' functionality.
  Future<void> toggleCamera() async {
    if (_availableCameras.length < 2) {
      _logger.w("CameraService: Only one camera available. Cannot toggle.");
      _cameraErrorMessage = "Only one camera available.";
      _postFrameNotifyListeners();
      return;
    }

    _logger.i("CameraService: Toggling camera...");
    await disposeCamera(); // Dispose current camera before switching

    _currentCameraIndex = (_currentCameraIndex + 1) % _availableCameras.length;
    final CameraDescription newCamera = _availableCameras[_currentCameraIndex];

    _cameraController = CameraController(
      newCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController!.initialize();
      _isCameraInitialized = true;
      _currentFlashMode = _cameraController!.value.flashMode;
      _cameraErrorMessage = null;
      _logger.i(
        "CameraService: Camera toggled successfully to: ${newCamera.lensDirection}",
      );
    } on CameraException catch (e) {
      _cameraErrorMessage = "Failed to toggle camera: ${e.description}";
      _logger.e("CameraService: Error toggling camera: ${e.description}");
    } catch (e) {
      _cameraErrorMessage =
          "An unexpected error occurred during camera toggle: $e";
      _logger.e("CameraService: Unexpected error during camera toggle: $e");
    } finally {
      _postFrameNotifyListeners();
    }
  }

  /// Toggles the flash mode.
  Future<void> toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _logger.w("CameraService: Camera not initialized. Cannot toggle flash.");
      _cameraErrorMessage = "Camera not ready to toggle flash.";
      _postFrameNotifyListeners();
      return;
    }

    try {
      FlashMode newFlashMode;
      if (_currentFlashMode == FlashMode.off) {
        newFlashMode = FlashMode.torch;
      } else {
        newFlashMode = FlashMode.off;
      }
      await _cameraController!.setFlashMode(newFlashMode);
      _currentFlashMode = newFlashMode;
      _logger.i("CameraService: Flash toggled to: $_currentFlashMode");
      _cameraErrorMessage = null;
    } on CameraException catch (e) {
      _cameraErrorMessage = "Failed to toggle flash: ${e.description}";
      _logger.e("CameraService: Error toggling flash: ${e.description}");
    } catch (e) {
      _cameraErrorMessage =
          "An unexpected error occurred during flash toggle: $e";
      _logger.e("CameraService: Unexpected error during flash toggle: $e");
    } finally {
      _postFrameNotifyListeners();
    }
  }

  /// Disposes the current camera controller and releases resources.
  Future<void> disposeCamera() async {
    if (_cameraController == null) {
      _logger.d("CameraService: CameraController is null. Nothing to dispose.");
      return;
    }

    _logger.i("CameraService: Disposing camera controller.");
    try {
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      await _cameraController!.dispose();
      _cameraController = null;
      _isCameraInitialized = false;
      _isStreamingImages = false;
      _cameraErrorMessage = null; // Clear error message on successful disposal
      _logger.i("CameraService: Camera disposed successfully.");
    } on CameraException catch (e) {
      _cameraErrorMessage = "Failed to dispose camera: ${e.description}";
      _logger.e("CameraService: Error disposing camera: ${e.description}");
    } catch (e) {
      _cameraErrorMessage =
          "An unexpected error occurred during camera disposal: $e";
      _logger.e("CameraService: Unexpected error during camera disposal: $e");
    } finally {
      _postFrameNotifyListeners();
    }
  }

  @override
  void dispose() {
    _logger.i("CameraService: Disposing CameraService instance.");
    disposeCamera(); // Ensure camera is disposed when the service is disposed
    super.dispose();
  }

  /// Helper method to call notifyListeners after the current frame.
  void _postFrameNotifyListeners() {
    // Only call notifyListeners if there are active listeners
    if (hasListeners) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Check hasListeners again to prevent errors if listeners are removed
        // before this callback fires.
        if (hasListeners) {
          notifyListeners();
        }
      });
    }
  }
}
