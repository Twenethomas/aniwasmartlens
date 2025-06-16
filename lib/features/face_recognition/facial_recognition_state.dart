// lib/features/face_recognition/facial_recognition_state.dart
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/services.dart' as ui show WriteBuffer;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:logger/logger.dart';
import 'package:flutter/material.dart'; // For BuildContext in dialogs and Size

import '../../main.dart'; // For global logger
import '../../core/services/network_service.dart'; // Now explicitly used
import '../../core/services/speech_service.dart';
import '../../core/services/face_recognizer_service.dart';
import '../../core/services/camera_service.dart'; // NEW: Import CameraService
import '../../core/services/face_database_helper.dart'; // Import Database Helper
import '../../core/utils/throttler.dart'; // NEW: Import Throttler

/// Manages the state for facial recognition, including camera setup,
/// face detection, and communication with the FaceRecognizerService.
class FacialRecognitionState extends ChangeNotifier {
  // Removed CameraController from here, now managed by CameraService
  final CameraService _cameraService; // NEW: Injected CameraService
  final SpeechService _speechService;
  final FaceRecognizerService _faceRecognizerService;
  final NetworkService _networkService; // Injected NetworkService
  // final FaceDatabaseHelper _faceDatabaseHelper; // No longer needed here, FaceRecognizerService handles it

  final Logger _logger = logger; // Using global logger

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: true,
      enableClassification: false,
      enableTracking: false,
      minFaceSize: 0.1, // Detects faces that are at least 10% of the image size
    ),
  );

  final Throttler _throttler = Throttler(
    milliseconds: 1000,
    
  ); // Process frames every 500ms

  // State variables
  bool _isCameraReady = false; // Derived from CameraService
  bool _isDetecting = false; // General processing indicator
  String? _cameraInitializationError; // Error message for camera issues
  String? _processingMessage; // Message for user feedback during processing
  List<Face> _faces = []; // Detected faces
  String? _detectedFaceName; // Recognized face name (nullable)
  bool _isDisposed = false; // Flag to prevent operations on disposed service
  bool _isRegistered =
      false; // Indicates if a face has been successfully registered
  bool _registrationInProgress = false; // Flag for registration process

  // Getters for UI
  bool get isCameraReady => _cameraService.isCameraInitialized;
  bool get isDetecting => _isDetecting;
  String? get cameraInitializationError => _cameraInitializationError;
  String? get processingMessage => _processingMessage;
  List<Face> get faces => _faces;
  String? get detectedFaceName => _detectedFaceName;
  bool get isRegistered => _isRegistered;
  bool get registrationInProgress => _registrationInProgress;

  // Expose FaceRecognizerService
  FaceRecognizerService get faceRecognizerService => _faceRecognizerService;

  FacialRecognitionState({
    required NetworkService networkService,
    required SpeechService speechService,
    required FaceRecognizerService faceRecognizerService,
    required CameraService cameraService, // NEW: CameraService injected
    required FaceDatabaseHelper faceDatabaseHelper, // Still required by constructor for main.dart setup
  }) : _networkService = networkService,
       _speechService = speechService,
       _faceRecognizerService = faceRecognizerService,
       _cameraService = cameraService {
       // _faceDatabaseHelper = faceDatabaseHelper; // Not stored locally anymore
    // Assign injected CameraService
    _cameraService.addListener(
      _onCameraServiceStatusChanged,
    ); // Listen to CameraService changes
    _logger.i("FacialRecognitionState initialized.");
  }

  // NEW: Listener for CameraService status changes
  void _onCameraServiceStatusChanged() {
    // Update internal _isCameraReady based on CameraService's state
    if (_isCameraReady != _cameraService.isCameraInitialized) {
      _isCameraReady = _cameraService.isCameraInitialized;
      notifyListeners();
    }
    // Also update cameraInitializationError if CameraService has one
    if (_cameraInitializationError != _cameraService.cameraErrorMessage) {
      _cameraInitializationError = _cameraService.cameraErrorMessage;
      notifyListeners();
    }
  }

  /// Initializes the camera for facial recognition.
  // Now delegates to CameraService
  Future<void> initCamera() async {
    if (_isDisposed) {
      _logger.w(
        "FacialRecognitionState: initCamera called on disposed service. Aborting.",
      );
      return;
    }

    _logger.i(
      "FacialRecognitionState: Requesting camera initialization from CameraService...",
    );
    await _cameraService.initializeCamera(); // Delegate initialization
    _isCameraReady = _cameraService.isCameraInitialized;
    _setCameraInitializationError(_cameraService.cameraErrorMessage);

    if (_isCameraReady) {
      _logger.i(
        "FacialRecognitionState: Camera initialized via CameraService.",
      );
      // Load faces from DB after camera is ready
      await _faceRecognizerService.loadFacesFromDatabase();
      _logger.i(
        "FacialRecognitionState: Known faces loaded from database.",
      );
    } else {
      _logger.e(
        "FacialRecognitionState: Camera not ready after CameraService initialization.",
      );
    }
    notifyListeners();
  }

  /// Starts the live camera feed for face detection.
  // Now delegates to CameraService
  Future<void> startLiveFeed() async {
    if (_isDisposed) {
      _logger.w(
        "FacialRecognitionState: startLiveFeed called on disposed service. Aborting.",
      );
      return;
    }
    if (!_cameraService.isCameraInitialized) {
      _setCameraInitializationError(
        "Camera not initialized. Please try again.",
      );
      _speechService.speak("Camera not ready.");
      return;
    }
    if (_cameraService.isStreamingImages) {
      // Check CameraService's streaming state
      _logger.i("FacialRecognitionState: Live feed already active.");
      return;
    }

    _logger.i(
      "FacialRecognitionState: Starting live camera feed for face detection.",
    );
    _setProcessingMessage(null); // Clear any old messages
    _setFaces([]); // Clear previous faces
    _setDetectedFaceName(null); // Clear previous name
    setIsProcessingAI(false); // Reset processing flag

    await _cameraService.startImageStream((CameraImage image) {
      // Ensure faces are loaded before processing stream
      if (_faceRecognizerService.knownFaces.isEmpty) { 
        _faceRecognizerService.loadFacesFromDatabase();
      }
      _throttler.run(() {
        if (!_isDisposed) {
          // Ensure state is not disposed before processing
          _processCameraImage(image);
        }
      });
    });
    notifyListeners();
  }

  /// Stops the live camera feed.
  // Now delegates to CameraService
  Future<void> stopLiveFeed() async {
    if (_isDisposed) {
      _logger.w(
        "FacialRecognitionState: stopLiveFeed called on disposed service. Aborting.",
      );
      return;
    }
    _logger.i("FacialRecognitionState: Stopping live camera feed.");
    _throttler.dispose(); // Ensure pending throttled calls are cancelled
    await _cameraService.stopImageStream(); // Delegate stopping
    notifyListeners();
  }

  /// Disposes the camera controller.
  // Now delegates to CameraService
  Future<void> disposeCamera() async {
    _logger.i(
      "FacialRecognitionState: Requesting camera disposal from CameraService.",
    );
    await _cameraService.disposeCamera(); // Delegate disposal
    _isCameraReady = _cameraService.isCameraInitialized;
    notifyListeners();
  }

  /// Processes a single camera image for face detection and recognition.
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isDisposed ||
        !isCameraReady ||
        _cameraService.cameraController == null ||
        !_cameraService.cameraController!.value.isInitialized) {
      _logger.d(
        "FacialRecognitionState: Skipping _processCameraImage due to disposed service or camera not ready.",
      );
      return;
    }
    if (!_networkService.isOnline) {
      _setProcessingMessage("Offline. Face recognition paused.");
      setIsProcessingAI(false);
      return;
    }
    if (_registrationInProgress) {
      // If registration is in progress, do not perform live detection
      _logger.d(
        "FacialRecognitionState: Skipping live detection during registration.",
      );
      return;
    }
    if (_isDetecting) {
      // Avoid re-entry if already processing
      _logger.d(
        "FacialRecognitionState: Already detecting faces, skipping frame.",
      );
      return;
    }

    setIsProcessingAI(true); // Indicate processing is active
    _setProcessingMessage("Detecting faces...");

    InputImage? inputImage;
    try {
      final camera = _cameraService.cameraController!.description;
      final InputImageRotation mlKitRotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation)!;

      final bytes = _concatenatePlanes(image.planes);
      final format =
          InputImageFormat.nv21; // Assuming YUV420 for Android, adjust for iOS

      inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: mlKitRotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final List<Face> detectedFaces = await _faceDetector.processImage(
        inputImage,
      );
      _setFaces(detectedFaces);

      if (detectedFaces.isNotEmpty) {
        _setProcessingMessage("Analyzing faces...");
        final recognizedName = await _faceRecognizerService.recognizeFace(
          detectedFaces.first,
          inputImage,
        ); // Assuming one face for simplicity
        _setDetectedFaceName(recognizedName);

        if (recognizedName != null) {
          _speechService.speak("Hello, $recognizedName!");
          _setProcessingMessage("Face recognized: $recognizedName");
        } else {
          _speechService.speak("Unrecognized face detected.");
          _setProcessingMessage("Unrecognized face.");
        }
      } else {
        _setProcessingMessage("No face detected.");
        _setDetectedFaceName(null);
      }
    } catch (e, stackTrace) {
      _logger.e(
        "FacialRecognitionState: Error processing camera image: $e",
        error: e,
        stackTrace: stackTrace,
      );
      _setProcessingMessage("Error processing image: ${e.toString()}");
      _setFaces([]);
      _setDetectedFaceName(null);
    } finally {
      setIsProcessingAI(false); // Processing finished
    }
  }

  // Helper to concatenate image planes into a single Uint8List for ML Kit
  Uint8List _concatenatePlanes(List<Plane> planes) {
    final allBytes = ui.WriteBuffer();
    for (Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  /// Captures a frame and attempts to register a new face.
  Future<void> captureAndRegisterFace(BuildContext context) async {
    if (_isDisposed) {
      _logger.w(
        "FacialRecognitionState: captureAndRegisterFace called on disposed service. Aborting.",
      );
      return;
    }
    if (!_cameraService.isCameraInitialized) {
      _setCameraInitializationError("Camera not ready for registration.");
      _speechService.speak("Camera not ready. Please wait.");
      return;
    }
    if (_registrationInProgress || isDetecting) {
      _setProcessingMessage("Already capturing or processing a face.");
      _speechService.speak("Please wait for the current operation to finish.");
      return;
    }
    if (!_networkService.isOnline) {
      _setProcessingMessage("Offline. Cannot register face.");
      _speechService.speak("Cannot register face while offline.");
      return;
    }

    _registrationInProgress = true;
    _setProcessingMessage("Capturing image for registration...");
    _speechService.speak("Capturing image.");
    notifyListeners(); // Notify to update UI for registration status

    try {
      await _cameraService.stopImageStream(); // Stop live stream for capture
      final XFile? file =
          await _cameraService
              .takePicture(); // Use CameraService to take picture
      if (file == null) {
        throw Exception("Failed to capture image.");
      }

      _setProcessingMessage("Detecting face for registration...");
      final inputImage = InputImage.fromFilePath(file.path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        _setProcessingMessage(
          "No face detected in the captured image. Please try again.",
        );
        _speechService.speak("No face detected. Please try again.");
        return;
      }
      if (faces.length > 1) {
        _setProcessingMessage(
          "Multiple faces detected. Please ensure only one face is in view.",
        );
        _speechService.speak(
          "Multiple faces detected. Please ensure only one face is in view.",
        );
        return;
      }

      final Face face = faces.first;
      String? name;

      // Use mounted check before showing dialog
      if (!context.mounted) return;

      await showDialog<String>(
        context: context,
        barrierDismissible: false, // User must tap a button
        builder: (BuildContext dialogContext) {
          String inputName = '';
          return AlertDialog(
            title: const Text('Register Face'),
            content: TextField(
              onChanged: (value) {
                inputName = value;
              },
              decoration: const InputDecoration(hintText: "Enter name"),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
              ),
              TextButton(
                child: const Text('Register'),
                onPressed: () {
                  if (inputName.isNotEmpty) {
                    name = inputName;
                    Navigator.of(dialogContext).pop();
                  } else {
                    _speechService.speak(
                      "Name cannot be empty for registration.",
                    );
                  }
                },
              ),
            ],
          );
        },
      );

      if (name != null && name!.isNotEmpty) {
        _setProcessingMessage("Registering '$name'...");
        _speechService.speak("Registering $name.");
        setIsProcessingAI(true); // Start processing indicator for registration
        notifyListeners();
        try {
          await _faceRecognizerService.registerFace(
            name!,
            face,
            inputImage,
          ); // Use name! because it's checked for null and not empty
          _setProcessingMessage("Face for '$name' registered successfully.");
          _speechService.speak("Face for $name registered successfully.");
          _setDetectedFaceName(name); // Use the private setter
          _isRegistered = true; // Set registration flag
        } catch (e) {
          _logger.e("Error registering face: $e");
          _setProcessingMessage("Failed to register face: ${e.toString()}");
          _speechService.speak("Failed to register face.");
        } finally {
          setIsProcessingAI(false); // End processing indicator
        }
      } else {
        _logger.d("No name provided for face registration.");
        _setProcessingMessage("Face registration cancelled.");
        _speechService.speak("Face registration cancelled.");
      }
    } catch (e, stackTrace) {
      _logger.e(
        "Error during capture and register face: $e",
        error: e,
        stackTrace: stackTrace,
      );
      _setProcessingMessage("Error: ${e.toString()}");
      _speechService.speak(
        "An error occurred during registration. Please try again.",
      );
    } finally {
      _registrationInProgress = false; // Registration process finished
      await startLiveFeed(); // Resume live feed after registration attempt
      notifyListeners();
    }
  }

  // Helper for setting camera initialization errors
  void _setCameraInitializationError(String? error) {
    _cameraInitializationError = error;
    notifyListeners();
  }

  // Helper for setting general processing messages (e.g., "Capturing...", "Registering face...")
  void _setProcessingMessage(String? message) {
    _processingMessage = message;
    notifyListeners();
  }

  // Private setter for _detectedFaceName
  void _setDetectedFaceName(String? name) {
    _detectedFaceName = name;
    notifyListeners();
  }

  // Public method to set the processing AI status, allowing external control.
  void setIsProcessingAI(bool status) {
    if (_isDetecting != status && !_isDisposed) {
      _isDetecting = status;
      notifyListeners();
    }
  }

  // Helper to set detected faces
  void _setFaces(List<Face> faces) {
    _faces = faces;
    notifyListeners();
  }

  // Clear detected face name
  void clearDetectedFaceName() {
    _setDetectedFaceName(null);
  }

  @override
  void dispose() {
    _logger.i("FacialRecognitionState disposed.");
    _isDisposed = true; // Set dispose flag immediately

    _throttler.dispose(); // Dispose the throttler to cancel any pending timers

    _cameraService.removeListener(
      _onCameraServiceStatusChanged,
    ); // NEW: Remove camera service listener
    // This state no longer disposes the camera itself, CameraService does.

    // Close the face detector
    _faceDetector
        .close()
        .then((_) {
          // Removed redundant null check
          _logger.i("FacialRecognitionState: FaceDetector closed.");
        })
        .catchError((e) {
          _logger.e("FacialRecognitionState: Error closing FaceDetector: $e");
        });

    super.dispose();
    _logger.i("FacialRecognitionState: Disposal process completed.");
  }
}
