// lib/features/face_recognition/facial_recognition_state.dart
import 'dart:async';
import 'dart:io';
// Removed unnecessary import: import 'package:flutter/foundation.dart'; // For ChangeNotifier
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart'; // For BuildContext in dialogs and Size

import '../../main.dart'; // For global logger
import '../../core/services/network_service.dart'; // Now explicitly used
import '../../core/services/speech_service.dart';
import '../../core/services/face_recognizer_service.dart';

// Helper to prevent excessive processing of camera frames
class _Throttler {
  final int milliseconds;
  DateTime? _lastRun;
  Timer? _timer;

  _Throttler({required this.milliseconds});

  void run(VoidCallback action) {
    if (_lastRun == null ||
        DateTime.now().difference(_lastRun!) > Duration(milliseconds: milliseconds)) {
      _lastRun = DateTime.now();
      action();
    } else {
      _timer?.cancel(); // Cancel previous delayed call if still pending
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

class FacialRecognitionState extends ChangeNotifier {
  final NetworkService _networkService; // Now explicitly used
  final SpeechService _speechService;
  final FaceRecognizerService _faceRecognizerService;
  final Logger _logger = logger; // Use global logger instance

  CameraController? _cameraController;
  FaceDetector? _faceDetector;
  List<CameraDescription> _availableCameras = [];
  int _currentCameraIndex = 0;

  // State properties for UI consumption
  bool _isCameraInitialized = false; // Renamed from _isCameraReady
  String? _cameraInitializationError; // Combines _errorMessage and camera init errors
  List<Face> _detectedFaces = [];
  bool _isLiveFeedActive = false; // Controls if image stream processing is active
  Size _imageSize = Size.zero; // Size of the camera frames
  String _detectedFaceName = ''; // Name of the recognized face
  String? _processingMessage; // Messages like "Registering face...", "Capturing image..."
  bool _isDetecting = false; // Flag to prevent concurrent image processing (replaces _isProcessingFrame)
  bool _isDisposed = false; // Track if the state object itself is disposed

  final _throttler = _Throttler(milliseconds: 100); // Throttle image processing for performance

  // Getters for UI
  CameraController? get cameraController => _cameraController;
  bool get isCameraInitialized => _isCameraInitialized;
  String? get cameraInitializationError => _cameraInitializationError;
  List<Face> get detectedFaces => List.unmodifiable(_detectedFaces); // Return unmodifiable list
  bool get isLiveFeedActive => _isLiveFeedActive;
  Size get imageSize => _imageSize;
  String get detectedFaceName => _detectedFaceName;
  String? get processingMessage => _processingMessage;
  bool get isProcessingAI => _isDetecting; // Expose _isDetecting as isProcessingAI

  // Constructor now requires NetworkService, SpeechService, and FaceRecognizerService
  FacialRecognitionState({
    required NetworkService networkService,
    required SpeechService speechService,
    required FaceRecognizerService faceRecognizerService,
  })  : _networkService = networkService,
        _speechService = speechService,
        _faceRecognizerService = faceRecognizerService {
    _logger.i("FacialRecognitionState initialized.");
    _initFaceDetector();
  }

  // Initialize FaceDetector with appropriate options
  void _initFaceDetector() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableClassification: true,
        enableLandmarks: true,
        minFaceSize: 0.1, // Minimum size of face to detect
        performanceMode: FaceDetectorMode.fast, // Optimized for speed
      ),
    );
    _logger.i("FaceDetector initialized.");
  }

  /// Initializes the camera and starts the live feed if autoStartLive is true.
  Future<void> initCamera({bool autoStartLive = false}) async {
    // If the state object has been disposed, we cannot initialize the camera.
    if (_isDisposed) {
      _logger.w("FacialRecognitionState is disposed, cannot initialize camera.");
      _setCameraInitializationError("Internal error: State is disposed. Please restart the app.");
      return;
    }

    // Check if camera is already initialized and streaming, if so, return early.
    if (_isCameraInitialized && _cameraController != null && _cameraController!.value.isInitialized) {
      // If live feed was intended but not active, activate it.
      if (autoStartLive && !_isLiveFeedActive) {
        _logger.i("Camera already initialized, activating live feed as requested.");
        await toggleLiveFeed(activate: true); // Now correctly awaitable
      } else {
        _logger.i("Camera is already initialized and active. Skipping re-initialization.");
      }
      return;
    }

    _logger.i("Initializing camera...");
    _isCameraInitialized = false;
    _cameraInitializationError = null; // Clear previous errors
    _processingMessage = null; // Clear previous messages
    notifyListeners(); // Notify UI about loading state

    try {
      // Request camera permission
      final status = await Permission.camera.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        _setCameraInitializationError("Camera permission denied. Please enable it in settings.");
        _speechService.speak("Camera permission denied. Please enable it in your device settings.");
        return;
      }

      // Get available cameras
      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        _setCameraInitializationError("No cameras found on this device.");
        _speechService.speak("No cameras found on your device.");
        return;
      }

      // Dispose previous controller if it exists to prevent resource conflicts
      if (_cameraController != null) {
        _logger.d("Disposing previous camera controller before re-initialization.");
        // Use try-catch for dispose to prevent unhandled exceptions during cleanup
        try {
          if (_cameraController!.value.isStreamingImages) {
            await _cameraController!.stopImageStream();
          }
          await _cameraController!.dispose();
        } catch (e, st) {
          _logger.e("Error safely disposing previous camera controller: $e", error: e, stackTrace: st);
        } finally {
          _cameraController = null;
        }
      }

      // Prefer front camera if available, otherwise use the first one
      final CameraDescription camera = _availableCameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => _availableCameras.first,
      );
      _currentCameraIndex = _availableCameras.indexOf(camera); // Update current index

      // Create new CameraController
      _cameraController = CameraController(
        camera,
        ResolutionPreset.low, // Using low for better performance on live feed processing
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420, // Optimal for ML Kit processing on Android
      );

      // Initialize the new camera controller
      await _cameraController!.initialize();
      if (!_cameraController!.value.isInitialized) {
        throw Exception("Camera controller failed to initialize.");
      }

      _isCameraInitialized = true; // Mark as initialized
      _logger.i("Camera initialized successfully. autoStartLive: $autoStartLive");

      // Load face recognition model immediately after camera init
      // Ensure model is loaded before any face recognition attempts
      await _faceRecognizerService.loadModel();
      _logger.i("Face recognition model loaded.");

      // Start live feed if autoStartLive is true
      if (autoStartLive) {
        await toggleLiveFeed(activate: true); // Now correctly awaitable
      }

      notifyListeners(); // Notify UI about successful initialization
    } catch (e, st) {
      _logger.e("Failed to initialize camera: $e", error: e, stackTrace: st);
      _setCameraInitializationError("Failed to initialize camera: ${e.toString()}. Please ensure permissions are granted and try again.");
    }
  }

  /// Disposes the camera controller and stops any active streams.
  Future<void> disposeCamera() async {
    _logger.i("Disposing camera.");
    // If controller is null or already marked as disposed, do nothing
    if (_cameraController == null || _isDisposed) {
      _logger.d("Camera controller is null or already disposed. Skipping disposal.");
      return;
    }

    _isLiveFeedActive = false; // Stop live processing flag
    _isDetecting = false; // Stop any ongoing detection
    _throttler.dispose(); // Ensure throttler timer is cancelled to prevent callbacks on disposed objects

    try {
      // Stop image stream if active
      if (_cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      // Dispose the controller
      await _cameraController!.dispose();
      _cameraController = null; // Clear reference
      _isCameraInitialized = false; // Update state
      _logger.i("Camera disposed successfully.");
    } catch (e, st) {
      _logger.e("Error during camera disposal: $e", error: e, stackTrace: st);
      // Don't set error message here as it might be during app close or unexpected errors
    } finally {
      notifyListeners(); // Notify UI about camera state change
    }
  }

  /// Switches between available cameras (front/back).
  Future<void> switchCamera() async {
    if (_availableCameras.length < 2) {
      _logger.i("Only one camera available. Cannot switch.");
      _speechService.speak("Only one camera is available.");
      return;
    }

    _currentCameraIndex = (_currentCameraIndex + 1) % _availableCameras.length;
    _logger.i("Switching camera to index: $_currentCameraIndex");
    await disposeCamera(); // Dispose current camera cleanly
    await initCamera(autoStartLive: _isLiveFeedActive); // Initialize new camera with previous live feed state
    _speechService.speak("Switched camera.");
  }

  /// Toggles the live face detection feed on/off.
  Future<void> toggleLiveFeed({bool? activate}) async { // Changed return type to Future<void>
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _setProcessingMessage("Camera not ready.");
      return;
    }

    final bool targetState = activate ?? !_isLiveFeedActive;

    if (targetState) {
      if (_cameraController!.value.isStreamingImages) {
        _logger.i("Live feed already active.");
        return;
      }
      _logger.i("Starting live feed.");
      try {
        await _cameraController!.startImageStream((CameraImage image) {
          _throttler.run(() {
            _processCameraImage(image);
          });
        });
        _isLiveFeedActive = true;
        _setProcessingMessage("Live feed active.");
        _speechService.speak("Live feed started.");
      } catch (e) {
        _logger.e("Error starting image stream: $e");
        _setProcessingMessage("Failed to start live feed: $e");
        _speechService.speak("Failed to start live feed.");
      }
    } else {
      if (!_cameraController!.value.isStreamingImages) {
        _logger.i("Live feed already inactive.");
        return;
      }
      _logger.i("Stopping live feed.");
      try {
        await _cameraController!.stopImageStream();
        _isLiveFeedActive = false;
        _detectedFaces = []; // Clear detected faces when stopping live feed
        _detectedFaceName = ''; // Clear detected name
        _setProcessingMessage("Live feed stopped.");
        _speechService.speak("Live feed stopped.");
      } catch (e) {
        _logger.e("Error stopping image stream: $e");
        _setProcessingMessage("Failed to stop live feed: $e");
        _speechService.speak("Failed to stop live feed.");
      }
    }
    notifyListeners();
  }

  /// Processes each camera image for face detection and then recognition.
  Future<void> _processCameraImage(CameraImage image) async {
    // Prevent processing if not active, already detecting, disposed, or detector not ready
    if (!_isLiveFeedActive || _isDetecting || _isDisposed || _faceDetector == null) return;

    // Check network connectivity before attempting AI recognition that might use it
    if (!_networkService.isOnline) { // Explicitly use _networkService
      _setProcessingMessage("Offline. Cannot perform face recognition.");
      _logger.w("FacialRecognitionState: Offline, skipping AI recognition.");
      _isDetecting = false; // Reset processing flag
      notifyListeners();
      return;
    }


    _isDetecting = true; // Set flag to prevent concurrent processing
    _detectedFaces = []; // Clear previous detections
    _detectedFaceName = ''; // Clear previous name
    notifyListeners(); // Notify UI that processing has started (e.g., show a loading indicator)

    try {
      // Set the image size once based on the first frame if not already set
      if (_imageSize == Size.zero) {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
      }

      // Determine the rotation for ML Kit's InputImage based on device orientation
      final InputImageRotation rotation = _cameraController!.value.deviceOrientation.rotationToInputImageRotation();

      // Create InputImage from camera image bytes
      final InputImage inputImage = InputImage.fromBytes(
        bytes: image.planes[0].bytes, // For YUV420_888/NV21, usually only the first plane is needed for ML Kit
        metadata: InputImageMetadata(
          size: _imageSize,
          rotation: rotation,
          format: InputImageFormat.nv21, // Specify NV21 format as common for Android YUV420_888
          bytesPerRow: image.planes[0].bytesPerRow, // Bytes per row of the image plane
        ),
      );

      _detectedFaces = await _faceDetector!.processImage(inputImage);
      _logger.d("Detected ${_detectedFaces.length} faces.");

      if (_detectedFaces.isNotEmpty) {
        // For simplicity, recognize the first detected face
        final Face firstFace = _detectedFaces.first;
        // Use the injected FaceRecognizerService to recognize the face
        final String? recognizedName = await _faceRecognizerService.recognizeFace(firstFace, inputImage);
        if (recognizedName != null && recognizedName.isNotEmpty) {
          _detectedFaceName = recognizedName;
          _speechService.speak("Recognized $recognizedName");
        } else {
          _detectedFaceName = 'Unknown';
          _speechService.speak("Unknown face detected.");
        }
      } else {
        _detectedFaceName = ''; // No faces, clear previous name
      }
    } catch (e) {
      _logger.e("Error processing camera image or detecting faces: $e");
      _setProcessingMessage("Live processing error: $e");
    } finally {
      _isDetecting = false; // Reset processing flag
      notifyListeners(); // Notify UI about updated faces/name
    }
  }

  /// Captures a single image and attempts to recognize faces in it.
  Future<void> captureAndRecognize(BuildContext context) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _setProcessingMessage("Camera not ready.");
      _speechService.speak("Camera not ready to capture.");
      return;
    }
    if (_isDetecting) {
      _setProcessingMessage("Already processing a frame. Please wait.");
      return;
    }

    _setProcessingMessage("Capturing image...");
    _speechService.speak("Capturing image.");
    setIsProcessingAI(true); // Indicate processing is active
    _detectedFaceName = ''; // Clear previous name
    notifyListeners();

    XFile? file; // To store the captured image file
    bool wasLive = _isLiveFeedActive; // Declare here for scope

    try {
      // Temporarily stop live feed to ensure a clean capture without conflicts
      if (wasLive) await toggleLiveFeed(activate: false); // Now correctly awaitable

      file = await _cameraController!.takePicture(); // Capture the photo
      _logger.i("Image captured: ${file.path}");

      // Check network connectivity before AI call
      if (!_networkService.isOnline) {
        _setProcessingMessage("Offline. Cannot perform face recognition.");
        _speechService.speak("Cannot recognize face while offline.");
        return; // Exit without further processing
      }

      final inputImage = InputImage.fromFilePath(file.path); // Create InputImage from file
      final List<Face> faces = await _faceDetector!.processImage(inputImage); // Detect faces

      if (faces.isNotEmpty) {
        _setProcessingMessage("Recognizing face...");
        final String? recognizedName = await _faceRecognizerService.recognizeFace(faces.first, inputImage);
        if (recognizedName != null && recognizedName.isNotEmpty) {
          _detectedFaceName = recognizedName;
          _speechService.speak("Recognized $recognizedName.");
        } else {
          _detectedFaceName = 'Unknown';
          _speechService.speak("Unknown face detected.");
        }
      } else {
        _detectedFaceName = '';
        _setProcessingMessage("No faces detected in captured image.");
        _speechService.speak("No faces detected in the image.");
      }
    } catch (e) {
      _logger.e("Error capturing or recognizing image: $e");
      _setProcessingMessage("Error: ${e.toString()}");
      _speechService.speak("Failed to capture and recognize image.");
    } finally {
      setIsProcessingAI(false); // End processing
      // Clean up the temporary image file
      if (file != null) {
        try {
          // Check if the file still exists before attempting to delete
          if (await File(file.path).exists()) {
            await File(file.path).delete();
            _logger.d("Temporary image file deleted: ${file.path}");
          }
        } catch (deleteError) {
          _logger.e("Error deleting temporary image file: $deleteError"); // Corrected to just log
        }
      }
      // Re-enable live feed if it was active before capture
      if (wasLive) await toggleLiveFeed(activate: true); // Now correctly awaitable
      notifyListeners();
    }
  }

  /// Registers a new face with a provided name by capturing an image.
  Future<void> registerFace(BuildContext context) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _setProcessingMessage("Camera not ready.");
      _speechService.speak("Camera not ready to register face.");
      return;
    }
    if (_isDetecting) {
      _setProcessingMessage("Already processing a frame. Please wait.");
      return;
    }

    _setProcessingMessage("Capturing image for registration...");
    _speechService.speak("Capturing image for registration.");
    setIsProcessingAI(true); // Indicate processing is active
    _detectedFaceName = ''; // Clear previous name
    notifyListeners();

    XFile? file;
    bool wasLive = _isLiveFeedActive; // Declare here for scope

    try {
      if (wasLive) await toggleLiveFeed(activate: false); // Now correctly awaitable

      file = await _cameraController!.takePicture();
      _logger.i("Image captured for registration: ${file.path}");

      // Check network connectivity before AI call
      if (!_networkService.isOnline) {
        _setProcessingMessage("Offline. Cannot register face.");
        _speechService.speak("Cannot register face while offline.");
        return; // Exit without further processing
      }

      final inputImage = InputImage.fromFilePath(file.path);
      final List<Face> faces = await _faceDetector!.processImage(inputImage);

      if (faces.isNotEmpty) {
        final Face faceToRegister = faces.first;
        await _promptForFaceName(context, faceToRegister, inputImage);
      } else {
        _setProcessingMessage("No face detected in captured image. Cannot register.");
        _speechService.speak("No face detected in the image. Please try again.");
      }
    } catch (e) {
      _logger.e("Error capturing image for registration: $e");
      _setProcessingMessage("Error: ${e.toString()}");
      _speechService.speak("Failed to capture image for registration.");
    } finally {
      setIsProcessingAI(false); // End processing
      if (file != null) {
        try {
          if (await File(file.path).exists()) {
            await File(file.path).delete();
            _logger.d("Temporary registration image file deleted: ${file.path}");
          }
        } catch (deleteError) {
          _logger.e("Error deleting temporary registration image file: $deleteError"); // Corrected to just log
        }
      }
      if (wasLive) await toggleLiveFeed(activate: true); // Now correctly awaitable
      notifyListeners();
    }
  }

  /// Shows a dialog to prompt the user for a name to register the face.
  Future<void> _promptForFaceName(BuildContext context, Face face, InputImage inputImage) async {
    // Guard against context being unmounted if this method is called after an async operation
    // and the calling widget (e.g., FacialRecognitionPage) is popped.
    if (!context.mounted) {
      _logger.w("Context not mounted in _promptForFaceName, cancelling operation.");
      return;
    }

    String? name = await showDialog<String>(
      context: context,
      barrierDismissible: false, // User must interact with buttons
      builder: (BuildContext dialogContext) {
        final TextEditingController nameController = TextEditingController();
        return AlertDialog(
          title: const Text('Register Face'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: "Enter name for this face",
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()), // Allow submitting with Enter
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _setProcessingMessage("Face registration cancelled.");
                _speechService.speak("Face registration cancelled.");
              },
            ),
            ElevatedButton(
              child: const Text('Register'),
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  Navigator.of(dialogContext).pop(nameController.text.trim());
                } else {
                  // The use of dialogContext here is safe as it's within the dialog's builder.
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text("Name cannot be empty.")),
                  );
                  _speechService.speak("Name cannot be empty for registration.");
                }
              },
            ),
          ],
        );
      },
    );

    if (name != null && name.isNotEmpty) {
      _setProcessingMessage("Registering '$name'...");
      _speechService.speak("Registering $name.");
      setIsProcessingAI(true); // Start processing indicator for registration
      notifyListeners();
      try {
        await _faceRecognizerService.registerFace(name, face, inputImage);
        _setProcessingMessage("Face for '$name' registered successfully.");
        _speechService.speak("Face for $name registered successfully.");
        _detectedFaceName = name; // Display the newly registered name
      } catch (e) {
        _logger.e("Error registering face: $e");
        _setProcessingMessage("Failed to register face: ${e.toString()}");
        _speechService.speak("Failed to register face.");
      } finally {
        setIsProcessingAI(false); // End processing indicator
        notifyListeners();
      }
    } else {
      _logger.d("No name provided for face registration.");
      // Message already handled in dialog
    }
  }

  // Helper for setting camera initialization errors
  void _setCameraInitializationError(String? error) {
    _cameraInitializationError = error;
    notifyListeners();
  }

  // Helper for setting general processing messages (e.g., "Capturing...", "Processing...")
  void _setProcessingMessage(String? message) {
    if (_processingMessage != message) { // Only update if message is different
      _processingMessage = message;
      notifyListeners();
    }
  }

  // General setter for isProcessingAI flag (used for both live and capture processing)
  void setIsProcessingAI(bool status) {
    if (_isDetecting != status) { // Use _isDetecting as the internal flag for processing
      _isDetecting = status;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _logger.i("FacialRecognitionState disposed. Closing detector and disposing camera.");
    _isDisposed = true; // Mark as disposed
    _faceDetector?.close(); // Close the ML Kit FaceDetector
    disposeCamera(); // Ensure camera resources are released
    _throttler.dispose(); // Dispose the throttler's timer
    super.dispose();
  }
}

// Extension to convert DeviceOrientation to ML Kit's InputImageRotation
extension on DeviceOrientation {
  // Explicitly return InputImageRotation to satisfy the analyzer.
  InputImageRotation rotationToInputImageRotation() {
    switch (this) {
      case DeviceOrientation.portraitUp:
        return InputImageRotation.rotation0deg;
      case DeviceOrientation.landscapeLeft:
        return InputImageRotation.rotation90deg;
      case DeviceOrientation.portraitDown:
        return InputImageRotation.rotation180deg;
      case DeviceOrientation.landscapeRight:
        return InputImageRotation.rotation270deg;
    }
    // This part should technically be unreachable for an enum, but some analyzers
    // might require it or a `throw` to ensure all paths return a value.
    // Given the enum is exhaustive, this shouldn't be executed.
    // throw UnsupportedError('Unsupported DeviceOrientation: $this');
  }
}
