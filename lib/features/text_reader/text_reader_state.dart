// lib/features/text_reader/text_reader_state.dart
import 'dart:async';
import 'dart:io';
// Added for WriteBuffer
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' as ui;
import 'package:flutter/material.dart'; // Import for WidgetsBinding.instance.addPostFrameCallback
import 'package:flutter/services.dart'; // Added for Platform
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'; // Ensure this import is present and correct
// Import logger
// Import permission_handler
import 'package:vibration/vibration.dart'; // Added for haptic feedback
// For saving images
import 'package:gal/gal.dart'; // Updated to use gal instead of image_gallery_saver

import '../../core/services/network_service.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/gemini_service.dart';
import '../../core/services/history_services.dart'; // Re-added HistoryService
import '../../core/services/text_reader_service.dart'; // Re-added TextReaderService
import '../../core/services/camera_service.dart'; // NEW: Import CameraService
// NEW: Import Throttler
import '../../main.dart'; // For global logger

enum TextReaderMode {
  liveScan, // Continuously scan for text in live camera feed
  capturedText, // Display a captured image and allow processing
}

class TextReaderState extends ChangeNotifier {
  // Removed CameraController from here, now managed by CameraService
  // Removed: List<CameraDescription> _availableCameras = []; // No longer used
  // Removed: int _currentCameraIndex = 0; // No longer used
  bool _isCameraReady = false; // Now derived from CameraService
  String _recognizedText = '';
  String _correctedText = '';
  String _translatedText = '';
  String _detectedLanguage = '';
  String? _errorMessage;
  bool _isProcessingImage = false; // For ML Kit OCR
  bool _isProcessingAI = false; // For Gemini (correction, translation)
  bool _isSpeaking = false;
  bool _isTranslating = false; // New flag for translation state
  bool _textInView =
      false; // Indicates if text is currently detected in the live feed
  String? _capturedImagePath; // Path to the temporarily captured image file
  // Removed: bool _hasAutoCapturedThisSession = false; // No longer used

  Timer? _liveDetectionDebounceTimer; // Timer to debounce live text detection
  static const int _liveDetectionDebounceDurationMs = 500; // Debounce for 500ms

  Timer? _textInViewFeedbackTimer; // Timer for text in view feedback
  bool _spokenTextInViewFeedbackGiven = false;

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  ); // FIXED: Changed TextScript to TextRecognitionScript
  final NetworkService _networkService;
  final SpeechService _speechService;
  final GeminiService _geminiService;
  final HistoryService _historyService;
  final TextReaderServices _textReaderService;
  final CameraService _cameraService; // NEW: Injected CameraService

  bool _isServiceDisposed =
      false; // Flag to prevent operations on disposed service

  // NEW: Current mode of the text reader UI
  TextReaderMode _currentMode = TextReaderMode.liveScan;

  // NEW: Flash state (derived from CameraService)
  bool get isFlashOn => _cameraService.isFlashOn;

  // NEW: Auto-capture state
  bool _isAutoCaptureEnabled = false;
  bool get isAutoCaptureEnabled => _isAutoCaptureEnabled;

  // Language mapping for TTS
  // This map should be comprehensive for all supported languages.
  final Map<String, String> _languageNameToCode = {
    'English': 'en-US', // Default or specific regional English
    'Spanish': 'es-ES', // Example: Castilian Spanish
    'French': 'fr-FR',
    'German': 'de-DE',
    'Chinese': 'zh-CN', // Mandarin Chinese (Simplified, China)
    'Japanese': 'ja-JP',
    'Korean': 'ko-KR',
    'Arabic': 'ar-SA', // Arabic (Saudi Arabia)
    'Russian': 'ru-RU',
    'Italian': 'it-IT',
    'Portuguese': 'pt-PT', // Portuguese (Portugal)
    'Hindi': 'hi-IN',
    'Bengali': 'bn-IN',
    'Urdu': 'ur-PK',
    'Turkish': 'tr-TR',
    'Vietnamese': 'vi-VN',
    'Thai': 'th-TH',
    'Indonesian': 'id-ID',
    'Malay': 'ms-MY',
    'Swahili': 'sw-TZ', // Swahili (Tanzania)
    'Zulu': 'zu-ZA',
    'Hausa': 'ha-NG',
  };

  // Getters for UI consumption
  // isCameraReady now reflects CameraService's state
  bool get isCameraReady => _cameraService.isCameraInitialized;
  String get recognizedText => _recognizedText;
  String get correctedText => _correctedText;
  String get translatedText => _translatedText;
  String get detectedLanguage => _detectedLanguage;
  String? get errorMessage => _errorMessage;
  bool get isProcessingImage => _isProcessingImage;
  bool get isProcessingAI => _isProcessingAI;
  bool get isSpeaking => _isSpeaking;
  bool get isTranslating => _isTranslating; // Expose translation state
  bool get textInView => _textInView;
  String? get capturedImagePath => _capturedImagePath;
  TextReaderMode get currentMode => _currentMode; // Expose current mode

  // Derived state to simplify UI logic
  bool get isAnyProcessingActive =>
      isProcessingImage || isProcessingAI || _isTranslating;

  /// Checks if there's any text available to work with
  bool get hasText =>
      recognizedText.isNotEmpty ||
      correctedText.isNotEmpty ||
      translatedText.isNotEmpty;

  /// Checks if the camera is in live mode (no captured image being displayed)
  // isInLiveMode now also checks if CameraService is streaming
  bool get isInLiveMode =>
      _capturedImagePath == null && _cameraService.isStreamingImages;

  TextReaderState({
    required NetworkService networkService,
    required SpeechService speechService,
    required GeminiService geminiService,
    required HistoryService historyService,
    required TextReaderServices textReaderService,
    required CameraService cameraService, // NEW: CameraService injected
  }) : _networkService = networkService,
       _speechService = speechService,
       _geminiService = geminiService,
       _historyService = historyService,
       _textReaderService = textReaderService,
       _cameraService = cameraService {
    // Assign injected CameraService
    _speechService.addListener(_onSpeechStatusChanged);
    _cameraService.addListener(
      _onCameraServiceStatusChanged,
    ); // Listen to CameraService changes
    logger.i("TextReaderState initialized.");
  }

  void _onSpeechStatusChanged() {
    // This callback is triggered when speech service changes its speaking status
    final newSpeakingStatus = _speechService.isSpeaking;
    if (_isSpeaking != newSpeakingStatus) {
      _isSpeaking = newSpeakingStatus;
      notifyListeners();
    }
  }

  // NEW: Listener for CameraService status changes
  void _onCameraServiceStatusChanged() {
    // Update internal _isCameraReady based on CameraService's state
    if (_isCameraReady != _cameraService.isCameraInitialized) {
      _isCameraReady = _cameraService.isCameraInitialized;
      notifyListeners();
    }
    // Also update errorMessage if CameraService has one
    if (_errorMessage != _cameraService.cameraErrorMessage) {
      _errorMessage = _cameraService.cameraErrorMessage;
      notifyListeners();
    }
    // Update streaming status
    // Removed: if (isInLiveMode != _cameraService.isStreamingImages) { notifyListeners(); }
    // The `isInLiveMode` getter already depends on `_cameraService.isStreamingImages`
    // and `_capturedImagePath`, so direct notification here isn't always strictly needed
    // if _capturedImagePath isn't changing. However, for a complete UI update, keeping
    // notifyListeners() might be beneficial if any widget directly observes `isInLiveMode`.
    // For now, removing it to clear the specific `undefined_identifier` error related to `_isStreamingImages` local variable.
  }

  /// Initializes the camera for live text detection.
  // Now delegates to CameraService
  Future<void> initCamera() async {
    if (_isServiceDisposed) {
      logger.w(
        "TextReaderState: initCamera called on disposed service. Aborting.",
      );
      return;
    }

    logger.i(
      "TextReaderState: Requesting camera initialization from CameraService...",
    );
    await _cameraService.initializeCamera(); // Delegate initialization
    _isCameraReady = _cameraService.isCameraInitialized;
    _setErrorMessage(
      _cameraService.cameraErrorMessage,
    ); // Get error from CameraService

    if (_isCameraReady) {
      _setMode(TextReaderMode.liveScan); // Always start in live scan mode
      await resumeCamera(); // Start the image stream immediately
      logger.i(
        "TextReaderState: Camera initialized and live stream started (via CameraService).",
      );
    } else {
      logger.e(
        "TextReaderState: Camera not ready after CameraService initialization.",
      );
    }
    notifyListeners();
  }

  /// Starts or resumes the camera image stream for live text detection.
  // Now delegates to CameraService
  Future<void> resumeCamera() async {
    if (_isServiceDisposed) {
      logger.w(
        "TextReaderState: resumeCamera called on disposed service. Aborting.",
      );
      return;
    }
    if (!_cameraService.isCameraInitialized) {
      logger.w(
        "TextReaderState: Camera not initialized. Cannot resume stream.",
      );
      _setErrorMessage(
        "Camera not initialized. Please ensure permissions are granted.",
      );
      notifyListeners();
      return;
    }
    if (_cameraService.isStreamingImages &&
        _currentMode == TextReaderMode.liveScan) {
      // FIXED: Use _cameraService.isStreamingImages
      logger.i(
        "TextReaderState: Camera stream already active in live mode. No need to resume.",
      );
      return;
    }

    logger.i(
      "TextReaderState: Requesting camera stream resume from CameraService for live detection.",
    );
    _setErrorMessage(null); // Clear any previous errors

    await _cameraService.startImageStream((CameraImage image) {
      _liveDetectionDebounceTimer?.cancel(); // Cancel any existing timer
      _liveDetectionDebounceTimer = Timer(
        const Duration(milliseconds: _liveDetectionDebounceDurationMs),
        () {
          if (_currentMode == TextReaderMode.liveScan &&
              !isAnyProcessingActive) {
            _processCameraImage(image);
          } else {
            logger.d(
              "TextReaderState: Skipping live frame processing due to non-live mode or active processing.",
            );
          }
        },
      );
    });
    // Update internal streaming status based on CameraService (though isInLiveMode getter handles this)
    // Removed: _isStreamingImages = _cameraService.isStreamingImages; // No longer needed
    _setErrorMessage(_cameraService.cameraErrorMessage);
    notifyListeners();
  }

  /// Pauses the camera image stream.
  // Now delegates to CameraService
  Future<void> pauseCamera() async {
    if (_isServiceDisposed) {
      logger.w(
        "TextReaderState: pauseCamera called on disposed service. Aborting.",
      );
      return;
    }
    logger.i(
      "TextReaderState: Requesting camera stream pause from CameraService.",
    );
    _liveDetectionDebounceTimer?.cancel(); // Cancel any pending live detection
    await _cameraService.stopImageStream(); // Delegate pausing
    // Removed: _isStreamingImages = _cameraService.isStreamingImages; // No longer needed
    _setErrorMessage(_cameraService.cameraErrorMessage);
    notifyListeners();
  }

  /// Disposes the camera controller and stops any active streams.
  // Now delegates to CameraService
  Future<void> disposeCamera() async {
    logger.i(
      "TextReaderState: Requesting camera disposal from CameraService.",
    );
    _liveDetectionDebounceTimer?.cancel();
    _textInViewFeedbackTimer?.cancel();
    await _cameraService.disposeCamera(); // Delegate disposal
    _isCameraReady = _cameraService.isCameraInitialized;
    // Removed: _isStreamingImages = _cameraService.isStreamingImages; // No longer needed
    _setErrorMessage(_cameraService.cameraErrorMessage);
    notifyListeners();
  }

  /// Processes a single camera image for live text detection.
  /// This method is optimized to only detect text and update the `_textInView` status.
  Future<void> _processCameraImage(CameraImage image) async {
    if (_isServiceDisposed ||
        _currentMode != TextReaderMode.liveScan ||
        isAnyProcessingActive) {
      logger.d(
        "TextReaderState: Skipping _processCameraImage due to service disposed, non-live mode, or active processing.",
      );
      return;
    }

    if (!_networkService.isOnline) {
      _updateTextInViewStatus(false); // No text in view if offline
      _setErrorMessage("Offline. Live text detection paused.");
      return;
    }

    InputImage? inputImage;
    try {
      // Use CameraService's current camera controller to get details for InputImage
      final cameraController = _cameraService.cameraController;
      if (cameraController == null || !cameraController.value.isInitialized) {
        logger.e(
          "TextReaderState: CameraController from CameraService is not ready.",
        );
        _updateTextInViewStatus(false);
        return;
      }
      inputImage = _inputImageFromCameraImage(
        image,
        cameraController.description.lensDirection,
        cameraController.description.sensorOrientation,
      );
      if (inputImage == null) {
        logger.e(
          "TextReaderState: Failed to create InputImage from CameraImage.",
        );
        _updateTextInViewStatus(false);
        return;
      }

      final RecognizedText recognizedTextMlKit = await _textRecognizer
          .processImage(inputImage);
      final bool textFound = recognizedTextMlKit.text.isNotEmpty;
      _updateTextInViewStatus(textFound);

      // Provide haptic/audio feedback when text is in view for the first time
      if (textFound && !_spokenTextInViewFeedbackGiven) {
        Vibration.vibrate(duration: 50); // Short vibrate
        _speechService.speak("Text in view.");
        _spokenTextInViewFeedbackGiven = true;
        _textInViewFeedbackTimer?.cancel(); // Cancel previous timer
        _textInViewFeedbackTimer = Timer(const Duration(seconds: 5), () {
          _spokenTextInViewFeedbackGiven = false; // Reset after some time
        });
      }
    } catch (e) {
      logger.e("TextReaderState: Error during live text detection: $e");
      _setErrorMessage("Live scan error: ${e.toString()}");
      _updateTextInViewStatus(false);
    } finally {
      // Ensure inputImage is closed if it was created from a file
      if (inputImage?.filePath != null) {
        try {
          if (await File(inputImage!.filePath!).exists()) {
            await File(inputImage.filePath!).delete();
          }
        } catch (e) {
          logger.e(
            "TextReaderState: Error deleting temporary input image file: $e",
          );
        }
      }
    }
  }

  // Helper method to create InputImage from CameraImage (updated to use CameraService's controller info)
  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraLensDirection lensDirection,
    int sensorOrientation,
  ) {
    if (!_cameraService.isCameraInitialized) {
      return null;
    }

    final InputImageRotation mlKitRotation;

    if (Platform.isIOS) {
      mlKitRotation = InputImageRotationValue.fromRawValue(sensorOrientation)!;
    } else if (Platform.isAndroid) {
      int rotationCompensation = sensorOrientation;
      if (lensDirection == CameraLensDirection.front) {
        rotationCompensation = (360 - rotationCompensation) % 360;
      }
      mlKitRotation =
          InputImageRotationValue.fromRawValue(rotationCompensation)!;
    } else {
      mlKitRotation =
          InputImageRotation.rotation0deg; // Default for other platforms
    }

    final bytes = _concatenatePlplanes(image.planes);
    final format =
        InputImageFormat
            .nv21; // Use YUV420 for Android (NV21) and BGRA8888 for iOS (BGRA)

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

  // Helper to concatenate image planes into a single Uint8List for ML Kit
  Uint8List _concatenatePlplanes(List<Plane> planes) {
    final allBytes = ui.WriteBuffer();
    for (Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  /// Captures an image, performs OCR, and then switches to CapturedTextMode.
  // Now delegates to CameraService for taking picture
  Future<void> takePictureAndProcessText() async {
    if (_isServiceDisposed) {
      logger.w(
        "TextReaderState: takePictureAndProcessText called on disposed service. Aborting.",
      );
      return;
    }
    if (!_cameraService.isCameraInitialized) {
      _setErrorMessage("Camera not ready.");
      _speechService.speak("Camera is not ready. Please wait.");
      return;
    }
    if (isAnyProcessingActive) {
      _setErrorMessage("Please wait for current operation to finish.");
      return;
    }

    _setIsProcessingImage(true);
    _setErrorMessage(null);
    _setRecognizedText('');
    _setCorrectedText('');
    _setTranslatedText('');
    _setDetectedLanguage('');
    _setCapturedImagePath(null); // Clear any old captured image
    _speechService.stopSpeaking(); // Stop any ongoing speech

    logger.i("TextReaderState: Capturing picture for text processing.");
    _speechService.speak("Capturing text.");

    try {
      await pauseCamera(); // Pause live stream before taking picture
      final XFile? file =
          await _cameraService.takePicture(); // Delegate taking picture
      if (file == null) {
        throw Exception("Failed to capture image.");
      }

      _setCapturedImagePath(file.path);
      _setMode(TextReaderMode.capturedText); // Switch to captured text mode

      if (!_networkService.isOnline) {
        _setErrorMessage("Offline. Cannot process image.");
        _speechService.speak("Unable to process image while offline.");
        return;
      }

      logger.i("TextReaderState: Processing captured image: ${file.path}");
      final InputImage inputImage = InputImage.fromFilePath(file.path);
      final RecognizedText recognizedTextMlKit = await _textRecognizer
          .processImage(inputImage);

      if (recognizedTextMlKit.text.isEmpty) {
        _setErrorMessage("No text detected in the captured image.");
        _speechService.speak("No text detected in the image.");
      } else {
        _setRecognizedText(recognizedTextMlKit.text);
        _setDetectedLanguage(
          recognizedTextMlKit.blocks.isNotEmpty
              ? recognizedTextMlKit.blocks.first.recognizedLanguages
                  .first
              : 'Unknown',
        );
        _speechService.speak(
          "Text captured. Press speak, correct, or translate.",
        );
      }
    } catch (e) {
      logger.e("TextReaderState: Error taking picture or processing text: $e");
      _setErrorMessage("Failed to capture or process text: ${e.toString()}");
      _speechService.speak("Failed to capture or process text.");
    } finally {
      _setIsProcessingImage(false);
      // Do NOT resume camera here. Resuming happens when clearing results.
    }
  }

  /// Corrects the currently recognized text using Gemini.
  Future<void> correctText() async {
    if (_isServiceDisposed) {
      logger.w(
        "TextReaderState: correctText called on disposed service. Aborting.",
      );
      return;
    }
    if (recognizedText.isEmpty) {
      _setErrorMessage("No text to correct.");
      _speechService.speak("No text to correct.");
      return;
    }
    if (isAnyProcessingActive) {
      _setErrorMessage("Already busy. Please wait.");
      return;
    }
    if (!_networkService.isOnline) {
      _setErrorMessage("Cannot correct text while offline.");
      _speechService.speak("Cannot correct text while offline.");
      return;
    }

    _setIsProcessingAI(true);
    _setErrorMessage(null);
    _speechService.stopSpeaking();
    logger.i("TextReaderState: Correcting text using Gemini.");
    _speechService.speak("Correcting text.");

    try {
      final String corrected = await _geminiService.correctOcrErrors(
        recognizedText,
      );
      _setCorrectedText(corrected);
      _setTranslatedText(''); // Clear translation if correction is applied
      _speechService.speak("Text corrected.");
    } catch (e) {
      logger.e("TextReaderState: Error correcting text: $e");
      _setErrorMessage("Failed to correct text: ${e.toString()}");
      _speechService.speak("Failed to correct text.");
    } finally {
      _setIsProcessingAI(false);
    }
  }

  /// Translates the currently recognized (or corrected) text using Gemini.
  Future<void> translateText(String targetLanguage) async {
    if (_isServiceDisposed) {
      logger.w(
        "TextReaderState: translateText called on disposed service. Aborting.",
      );
      return;
    }
    final textToTranslate =
        correctedText.isNotEmpty ? correctedText : recognizedText;
    if (textToTranslate.isEmpty) {
      _setErrorMessage("No text to translate.");
      _speechService.speak("No text to translate.");
      return;
    }
    if (isAnyProcessingActive) {
      _setErrorMessage("Already busy. Please wait.");
      return;
    }
    if (!_networkService.isOnline) {
      _setErrorMessage("Cannot translate text while offline.");
      _speechService.speak("Cannot translate text while offline.");
      return;
    }

    _setIsProcessingAI(true);
    _isTranslating = true; // Set translation specific flag
    _setErrorMessage(null);
    _speechService.stopSpeaking();
    logger.i(
      "TextReaderState: Translating text to $targetLanguage using Gemini.",
    );
    _speechService.speak("Translating to $targetLanguage.");

    try {
      final String translated = await _geminiService.translateText(
        textToTranslate,
        targetLanguage,
      );
      _setTranslatedText(translated);

      // NEW: Set TTS language to the translated language
      final String? targetLanguageCode = _languageNameToCode[targetLanguage];
      if (targetLanguageCode != null) {
        logger.i(
          "TextReaderState: Attempting to set TTS language to $targetLanguageCode.",
        );
        final bool languageSet = await _speechService.setLanguage(
          targetLanguageCode,
        );
        if (!languageSet) {
          logger.w(
            "TextReaderState: Failed to set TTS language to $targetLanguageCode. Using default.",
          );
          _setErrorMessage(
            "Failed to set speech language for $targetLanguage. Speaking in default language.",
          );
        } else {
          logger.i(
            "TextReaderState: TTS language set to $targetLanguageCode.",
          );
        }
      } else {
        logger.w(
          "TextReaderState: Unknown target language '$targetLanguage'. Cannot set TTS language.",
        );
        _setErrorMessage(
          "Unknown language for speech. Speaking in default language.",
        );
      }

      _speechService.speak("Translation complete.");
    } catch (e) {
      logger.e("TextReaderState: Error translating text: $e");
      _setErrorMessage("Failed to translate text: ${e.toString()}");
      _speechService.speak("Failed to translate text.");
    } finally {
      _setIsProcessingAI(false);
      _isTranslating = false;
    }
  }

  /// Speaks the currently displayed text (translated > corrected > recognized).
  Future<void> speakCurrentText() async {
    if (_isServiceDisposed) {
      logger.w(
        "TextReaderState: speakCurrentText called on disposed service. Aborting.",
      );
      return;
    }
    final textToSpeak =
        translatedText.isNotEmpty
            ? translatedText
            : (correctedText.isNotEmpty ? correctedText : recognizedText);

    if (textToSpeak.isEmpty) {
      _setErrorMessage("No text to speak.");
      _speechService.speak("There is no text to speak.");
      return;
    }

    if (_speechService.isSpeaking) {
      _speechService.stopSpeaking();
      _speechService.speak("Speech stopped.");
      return;
    }

    _setErrorMessage(null);
    logger.i("TextReaderState: Speaking current text.");
    await _speechService.speak(textToSpeak);
  }

  /// Clears all results and returns to live scan mode, resuming camera.
  void clearResults({bool keepProcessingFlags = false}) {
    if (_isServiceDisposed) {
      logger.w(
        "TextReaderState: clearResults called on disposed service. Aborting.",
      );
      return;
    }
    logger.i(
      "TextReaderState: clearResults called. Resetting to live scan mode.",
    );
    _setRecognizedText('');
    _setCorrectedText('');
    _setTranslatedText('');
    _setDetectedLanguage('');
    _setErrorMessage('');
    _setCapturedImagePath(null); // Clear captured image path
    _speechService.stopSpeaking(); // Stop any ongoing speech
    _liveDetectionDebounceTimer?.cancel(); // Cancel any pending live detection
    _updateTextInViewStatus(false); // Reset text in view flag
    _spokenTextInViewFeedbackGiven = false;
    _textInViewFeedbackTimer?.cancel();
    _textInViewFeedbackTimer = null;
    // Removed: _hasAutoCapturedThisSession = false; // No longer used

    if (!keepProcessingFlags) {
      _setIsProcessingImage(false);
      _setIsProcessingAI(false);
      _isTranslating = false; // Reset translation flag
    }
    _setMode(TextReaderMode.liveScan); // Switch back to live scan mode
    logger.i("TextReaderState: Results cleared. Resuming camera.");
    resumeCamera(); // Resume camera after clearing results
  }

  // Private setters for state variables
  void _setIsProcessingImage(bool value) {
    if (_isProcessingImage != value) {
      _isProcessingImage = value;
      notifyListeners();
    }
  }

  void _setIsProcessingAI(bool value) {
    if (_isProcessingAI != value) {
      _isProcessingAI = value;
      notifyListeners();
    }
  }

  void _setRecognizedText(String text) {
    if (_recognizedText != text) {
      _recognizedText = text;
      notifyListeners();
    }
  }

  void _setCorrectedText(String text) {
    if (_correctedText != text) {
      _correctedText = text;
      notifyListeners();
    }
  }

  void _setTranslatedText(String text) {
    if (_translatedText != text) {
      _translatedText = text;
      notifyListeners();
    }
  }

  void _setDetectedLanguage(String language) {
    if (_detectedLanguage != language) {
      _detectedLanguage = language;
      notifyListeners();
    }
  }

  void _setErrorMessage(String? message) {
    if (_errorMessage != message) {
      _errorMessage = message;
      notifyListeners();
    }
  }

  void _updateTextInViewStatus(bool status) {
    if (_textInView != status) {
      _textInView = status;
      notifyListeners();
    }
  }

  void _setCapturedImagePath(String? path) {
    if (_capturedImagePath != path) {
      _capturedImagePath = path;
      notifyListeners();
    }
  }

  void _setMode(TextReaderMode mode) {
    if (_currentMode != mode) {
      _currentMode = mode;
      notifyListeners();
    }
  }

  // NEW: Toggle Flash - now delegates to CameraService
  void toggleFlash() async {
    if (_isServiceDisposed) return;
    await _cameraService.toggleFlash();
    notifyListeners(); // Notify to reflect flash state change from CameraService
  }

  // NEW: Set Auto-Capture
  void setAutoCapture(bool enable) {
    if (_isAutoCaptureEnabled != enable && !_isServiceDisposed) {
      _isAutoCaptureEnabled = enable;
      // Removed: _hasAutoCapturedThisSession = false; // No longer used
      notifyListeners();
      logger.i("TextReaderState: Auto-capture set to: $enable");
      if (!enable) {
        _spokenTextInViewFeedbackGiven =
            false; // Reset feedback when auto-capture is off
      }
    }
  }

  /// Saves the captured image to the device gallery
  Future<void> saveImageToGallery() async {
    if (_isServiceDisposed || _capturedImagePath == null) {
      logger.w(
        "TextReaderState: Cannot save image. No captured image available or service disposed.",
      );
      _speechService.speak("No image available to save.");
      return;
    }

    try {
      logger.i(
        "TextReaderState: Saving image to gallery: $_capturedImagePath",
      );
      await Gal.putImage(_capturedImagePath!);
      _speechService.speak("Image saved to gallery successfully.");
      logger.i("TextReaderState: Image saved to gallery successfully.");
    } catch (e, stack) {
      logger.e(
        "TextReaderState: Error saving image to gallery: $e",
        error: e,
        stackTrace: stack,
      );
      _setErrorMessage('Failed to save image: ${e.toString()}');
      _speechService.speak("Failed to save image to gallery.");
    }
  }

  /// Sends the processed text to chat/conversation
  Future<void> sendToChat() async {
    if (_isServiceDisposed) {
      logger.w("TextReaderState: sendToChat called on disposed service.");
      return;
    }

    String textToSend =
        translatedText.isNotEmpty
            ? translatedText
            : (correctedText.isNotEmpty ? correctedText : recognizedText);

    if (textToSend.isEmpty) {
      logger.w("TextReaderState: No text available to send to chat.");
      _speechService.speak("No text available to send to chat.");
      return;
    }

    try {
      logger.i("TextReaderState: Sending text to chat: \"$textToSend\"");
      await _historyService.addUserMessage("Text from camera: \"$textToSend\"");
      _speechService.speak("Text sent to chat successfully.");
    } catch (e, stack) {
      logger.e(
        "TextReaderState: Error sending text to chat: $e",
        error: e,
        stackTrace: stack,
      );
      _setErrorMessage('Failed to send text to chat: ${e.toString()}');
      _speechService.speak("Failed to send text to chat.");
    }
  }

  /// Stops any ongoing speech
  void stopSpeaking() {
    if (_isServiceDisposed) return;
    logger.i("TextReaderState: Stopping speech.");
    _speechService.stopSpeaking();
  }

  @override
  void dispose() {
    logger.i("TextReaderState disposed.");
    _isServiceDisposed = true; // Set dispose flag immediately

    _liveDetectionDebounceTimer?.cancel();
    _textInViewFeedbackTimer?.cancel();
    _speechService.removeListener(
      _onSpeechStatusChanged,
    ); // Remove speech listener
    _cameraService.removeListener(
      _onCameraServiceStatusChanged,
    ); // NEW: Remove camera service listener

    // This state no longer disposes the camera itself, CameraService does.
    // Ensure any internal camera stream callbacks are cleaned up (already done by _liveDetectionDebounceTimer?.cancel())

    _textRecognizer
        .close()
        .then((_) {
          logger.i("TextReaderState: Text recognizer closed.");
        })
        .catchError((e) {
          logger.e("TextReaderState: Error closing text recognizer: $e");
        });

    _speechService.stopSpeaking(); // Ensure speech is stopped

    super.dispose();
    logger.i("TextReaderState: Disposal process completed.");
  }
}
