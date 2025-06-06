// lib/features/text_reader/text_reader_state.dart
import 'dart:async';
import 'dart:io';
// import 'dart:math'; // Removed unused import if not explicitly used

import 'package:camera/camera.dart';
import 'package:flutter/material.dart'; // Import for WidgetsBinding.instance.addPostFrameCallback
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'; // Ensure this import is present and correct
import 'package:logger/logger.dart'; // Import logger
import 'package:permission_handler/permission_handler.dart'; // Import permission_handler

import '../../core/services/network_service.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/gemini_service.dart';
import '../../main.dart'; // For global logger

class TextReaderState extends ChangeNotifier {
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  bool _isCameraReady = false;
  String _recognizedText = '';
  String _correctedText = '';
  String _translatedText = '';
  String _detectedLanguage = '';
  bool _isProcessingImage = false;
  bool _isProcessingAI = false;
  bool _isSpeaking = false;
  String _errorMessage = '';
  bool _isFlashOn = false; // Added flash state
  final Logger _logger = logger; // Logger instance

  final SpeechService _speechService;
  final GeminiService _geminiService;
  final NetworkService _networkService; // NetworkService dependency

  // Changed TextScript.latin to TextRecognitionScript.latin and made field final
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  Timer? _debounceTimer; // For debouncing text recognition

  // Getters
  CameraController? get cameraController => _cameraController;
  bool get isCameraReady => _isCameraReady;
  String get recognizedText => _recognizedText;
  String get correctedText => _correctedText;
  String get translatedText => _translatedText;
  String get detectedLanguage => _detectedLanguage;
  bool get isProcessingImage => _isProcessingImage;
  bool get isProcessingAI => _isProcessingAI;
  bool get isSpeaking => _isSpeaking;
  String get errorMessage => _errorMessage;
  bool get isFlashOn => _isFlashOn;

  TextReaderState({
    required SpeechService speechService,
    required GeminiService geminiService,
    required NetworkService networkService,
  })  : _speechService = speechService,
        _geminiService = geminiService,
        _networkService = networkService {
    _speechService.speakingStatusStream.listen((status) {
      if (_isSpeaking != status) {
        _isSpeaking = status;
        notifyListeners();
      }
    });
  }

  // --- State Management Helpers ---
  void _setErrorMessage(String message) {
    if (_errorMessage != message) {
      _errorMessage = message;
      WidgetsBinding.instance.addPostFrameCallback((_) { // Defer notification
        notifyListeners();
      });
    }
  }

  void _setIsProcessingAI(bool status) {
    if (_isProcessingAI != status) {
      _isProcessingAI = status;
      WidgetsBinding.instance.addPostFrameCallback((_) { // Defer notification
        notifyListeners();
      });
    }
  }

  void _setIsProcessingImage(bool status) {
    if (_isProcessingImage != status) {
      _isProcessingImage = status;
      WidgetsBinding.instance.addPostFrameCallback((_) { // Defer notification
        notifyListeners();
      });
    }
  }

  void _setRecognizedText(String text) {
    if (_recognizedText != text) {
      _recognizedText = text;
      WidgetsBinding.instance.addPostFrameCallback((_) { // Defer notification
        notifyListeners();
      });
    }
  }

  void _setCorrectedText(String text) {
    if (_correctedText != text) {
      _correctedText = text;
      WidgetsBinding.instance.addPostFrameCallback((_) { // Defer notification
        notifyListeners();
      });
    }
  }

  void _setTranslatedText(String text) {
    if (_translatedText != text) {
      _translatedText = text;
      WidgetsBinding.instance.addPostFrameCallback((_) { // Defer notification
        notifyListeners();
      });
    }
  }

  void _setDetectedLanguage(String language) {
    if (_detectedLanguage != language) {
      _detectedLanguage = language;
      WidgetsBinding.instance.addPostFrameCallback((_) { // Defer notification
        notifyListeners();
      });
    }
  }

  void _setIsCameraReady(bool status) {
    if (_isCameraReady != status) {
      _isCameraReady = status;
      WidgetsBinding.instance.addPostFrameCallback((_) { // Defer notification
        notifyListeners();
      });
    }
  }

  // --- Camera Control ---
  Future<void> initCamera() async {
    _logger.i("TextReaderState: Initializing camera.");
    _setErrorMessage('');
    _setIsCameraReady(false);
    _setIsProcessingImage(false);

    try {
      final status = await Permission.camera.request();
      if (status.isGranted) {
        _availableCameras = await availableCameras();
        if (_availableCameras.isEmpty) {
          _setErrorMessage("No cameras found.");
          _logger.w("TextReaderState: No cameras found on device.");
          return;
        }

        // Prefer back camera if available, otherwise use the first one
        CameraDescription camera = _availableCameras.firstWhere(
          (cam) => cam.lensDirection == CameraLensDirection.back,
          orElse: () => _availableCameras.first,
        );

        _cameraController = CameraController(
          camera,
          ResolutionPreset.high, // Use high resolution for better OCR
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
        );

        await _cameraController!.initialize();
        _setIsCameraReady(true);
        _logger.i("TextReaderState: Camera initialized successfully.");

        // Start image stream for continuous processing
        _cameraController!.startImageStream(_processCameraImage);
      } else {
        _setErrorMessage("Camera permission denied.");
        _logger.w("TextReaderState: Camera permission denied.");
      }
    } on CameraException catch (e) {
      _setErrorMessage('Error initializing camera: ${e.description} (Code: ${e.code})'); // Include code for better debugging
      _logger.e('Error initializing camera: $e');
    } catch (e) {
      _setErrorMessage('An unexpected error occurred: $e');
      _logger.e('Unexpected error during camera init: $e');
    }
  }

  Future<void> pauseCamera() async {
    _logger.i("TextReaderState: Pausing camera.");
    try {
      if (_cameraController != null && _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
    } on CameraException catch (e) {
      _logger.e('Error pausing camera: $e');
      _setErrorMessage('Error pausing camera: ${e.description}');
    }
    _setIsProcessingImage(false); // Ensure processing is off when paused
  }

  Future<void> resumeCamera() async {
    _logger.i("TextReaderState: Resuming camera.");
    _setErrorMessage('');
    try {
      if (_cameraController != null && !_cameraController!.value.isStreamingImages) {
        await _cameraController!.startImageStream(_processCameraImage);
      } else if (_cameraController == null) {
        // If camera was disposed, re-initialize it
        await initCamera();
      }
    } on CameraException catch (e) {
      _logger.e('Error resuming camera: $e');
      _setErrorMessage('Error resuming camera: ${e.description}');
    }
  }

  Future<void> disposeCamera() async {
    _logger.i("TextReaderState: Disposing camera.");
    if (_cameraController != null) {
      try {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
        }
        await _cameraController!.dispose();
        _cameraController = null;
      } on CameraException catch (e) {
        _logger.e('Error disposing camera: $e');
        _setErrorMessage('Error disposing camera: ${e.description}');
      }
    }
    _setIsCameraReady(false);
    _setIsProcessingImage(false);
    _setRecognizedText('');
    _setCorrectedText('');
    _setTranslatedText('');
    _setDetectedLanguage('');
    _setErrorMessage('');
  }

  void toggleFlash() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _setErrorMessage("Camera not ready for flash control.");
      return;
    }
    try {
      if (_isFlashOn) {
        await _cameraController!.setFlashMode(FlashMode.off);
        _isFlashOn = false;
      } else {
        await _cameraController!.setFlashMode(FlashMode.torch);
        _isFlashOn = true;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) { // Defer notification
        notifyListeners();
      });
    } on CameraException catch (e) {
      _setErrorMessage("Failed to toggle flash: ${e.description}");
      _logger.e("Failed to toggle flash: $e");
    }
  }

  // --- Text Recognition Logic ---
  Future<void> _processCameraImage(CameraImage cameraImage) async {
    if (_isProcessingImage || !_isCameraReady) return;

    _setIsProcessingImage(true);
    _setErrorMessage('');

    final inputImage = _inputImageFromCameraImage(cameraImage);

    if (inputImage == null) {
      _setIsProcessingImage(false);
      return;
    }

    // Debounce to prevent processing too many frames
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () async {
      try {
        final RecognizedText recognizedTextMl = await _textRecognizer.processImage(inputImage);
        _setRecognizedText(recognizedTextMl.text);
        _logger.d("Recognized Text: ${recognizedTextMl.text}");

        if (recognizedTextMl.text.isNotEmpty) {
          await _processRecognizedText(recognizedTextMl.text);
        }
      } catch (e) {
        _logger.e("Error processing image for text recognition: $e");
        _setErrorMessage("Error recognizing text.");
      } finally {
        _setIsProcessingImage(false);
      }
    });
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameraController!.description;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    // Assuming the orientation is relative to the device's natural orientation.
    // Need to adjust based on platform and camera sensor orientation.
    // This is a common point of error for ML Kit with camera.
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      int rotationCompensation = _cameraController!.description.sensorOrientation;
      // For front camera, compensate for the mirrored image
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (360 - rotationCompensation) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) {
      _logger.e("Failed to get image rotation.");
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

  // --- AI Processing ---
  Future<void> _processRecognizedText(String text) async {
    if (text.isEmpty) {
      _setCorrectedText('');
      _setTranslatedText('');
      _setDetectedLanguage('');
      return;
    }

    _setIsProcessingAI(true);
    _setErrorMessage('');

    if (!_networkService.isOnline) {
      _setErrorMessage('No internet connection. Cannot perform AI operations.');
      _setIsProcessingAI(false);
      return;
    }

    try {
      // 1. Correct OCR Errors (using Gemini for robustness)
      final corrected = await _geminiService.correctOcrErrors(text); // Correct method call
      _setCorrectedText(corrected);
      _logger.i("Corrected Text: $corrected");

      // 2. Detect Language
      final detectedLang = await _geminiService.detectLanguage(corrected); // Correct method call
      _setDetectedLanguage(detectedLang);
      _logger.i("Detected Language: $detectedLang");

      // 3. Translate to English (or user's preferred language)
      final translated = await _geminiService.translateText(corrected, 'English'); // Correct method call
      _setTranslatedText(translated);
      _logger.i("Translated Text (English): $translated");

      // Speak the translated text
      await _speechService.speak(translated);
    } catch (e) {
      _logger.e("Error during AI text processing: $e");
      _setErrorMessage("Failed to process text with AI. Please try again.");
    } finally {
      _setIsProcessingAI(false);
    }
  }

  // --- Speech and Text Actions ---
  Future<void> speakRecognizedText() async {
    if (_recognizedText.isNotEmpty) {
      await _speechService.speak(_recognizedText);
    } else {
      _setErrorMessage("No text to speak.");
    }
  }

  Future<void> speakCorrectedText() async {
    if (_correctedText.isNotEmpty) {
      await _speechService.speak(_correctedText);
    } else {
      _setErrorMessage("No corrected text to speak.");
    }
  }

  Future<void> speakTranslatedText() async {
    if (_translatedText.isNotEmpty) {
      await _speechService.speak(_translatedText);
    } else {
      _setErrorMessage("No translated text to speak.");
    }
  }

  void stopSpeaking() {
    _speechService.stopSpeaking();
  }

  void clearResults() {
    _setRecognizedText('');
    _setCorrectedText('');
    _setTranslatedText('');
    _setDetectedLanguage('');
    _setErrorMessage('');
    _speechService.stopSpeaking(); // Stop any ongoing speech
  }

  @override
  void dispose() {
    _logger.i("TextReaderState disposed.");
    _debounceTimer?.cancel();
    disposeCamera(); // Ensure camera is disposed properly
    _textRecognizer.close();
    _speechService.stopSpeaking(); // Ensure speech is stopped on dispose
    super.dispose();
  }
}
