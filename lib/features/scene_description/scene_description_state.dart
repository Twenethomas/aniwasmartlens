// lib/features/scene_description/scene_description_state.dart
import 'dart:async';
import 'dart:io';
// Added for base64Encode
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:camera/camera.dart'; // For CameraImage (used in _processImageForAutoDescription for its bytes)
import 'package:path_provider/path_provider.dart'; // For getTemporaryDirectory

import '../../main.dart'; // For global logger
import '../../core/services/network_service.dart';
import '../../core/services/speech_service.dart';
import '../../core/services/gemini_service.dart';
import '../../core/services/camera_service.dart'; // Import CameraService
import '../../core/services/history_services.dart'; // Import HistoryService
import '../../core/utils/throttler.dart'; // Import Throttler

/// Manages the state and logic for scene description using camera and Gemini.
class SceneDescriptionState extends ChangeNotifier {
  final NetworkService _networkService;
  final SpeechService _speechService;
  final GeminiService _geminiService;
  final CameraService _cameraService; // Injected CameraService
  final HistoryService _historyService; // Injected HistoryService
  final Logger _logger = logger;

  // State variables
  String? _sceneDescription;
  bool _isProcessing = false;
  String? _errorMessage;
  String? _capturedImagePath; // Path to the temporarily captured image
  CameraController?
  _cameraController; // This will hold the controller from CameraService
  bool _isAutoDescribing = false;

  // Throttler for live description to prevent excessive API calls
  final _liveDescriptionThrottler = Throttler(
    milliseconds: 3000,
  ); // 3 seconds throttle

  // New state variables for translation and language
  String _translatedText = '';
  String _detectedLanguage = ''; // Language of the original description
  bool _isTranslating = false;

  // Language mapping for TTS (similar to TextReaderState)
  final Map<String, String> _languageNameToCode = {
    'English': 'en-US',
    'Spanish': 'es-ES',
    'French': 'fr-FR',
    'German': 'de-DE',
    'Chinese': 'zh-CN',
    'Japanese': 'ja-JP',
    'Korean': 'ko-KR',
    'Arabic': 'ar-SA',
    'Russian': 'ru-RU',
    'Italian': 'it-IT',
    'Portuguese': 'pt-PT',
    'Hindi': 'hi-IN',
    // Add more as needed
  };

  // Derived state to simplify UI logic
  bool get isAnyProcessingActive =>
      _isProcessing || _isTranslating || _isAutoDescribing;

  SceneDescriptionState(
    this._networkService,
    this._speechService,
    this._geminiService,
    this._cameraService,
    this._historyService, // Add HistoryService to constructor
  ) {
    // Add listener to CameraService to react to its internal state changes
    _cameraService.addListener(_onCameraServiceStatusChanged);
  }

  // Getters for external access
  String? get sceneDescription => _sceneDescription;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;
  String? get capturedImagePath => _capturedImagePath;
  CameraController? get cameraController => _cameraController;
  bool get isInitialized => _cameraService.isCameraInitialized;
  bool get isAutoDescribing => _isAutoDescribing;

  // Getters for new translation states
  String get translatedText => _translatedText;
  String get detectedLanguage => _detectedLanguage;
  bool get isTranslating => _isTranslating;
  bool get hasDescription =>
      _sceneDescription != null && _sceneDescription!.isNotEmpty;

  /// Sets the CameraController received from the CameraService.
  /// This is crucial for the UI to display the preview and for this state
  /// to perform image capture.
  void setCameraController(CameraController? controller) {
    if (_cameraController != controller) {
      _logger.i("SceneDescriptionState: CameraController updated.");
      _cameraController = controller;
      notifyListeners();
    }
  }

  /// Callback to react to changes in CameraService status.
  /// This ensures SceneDescriptionState always has the correct controller.
  void _onCameraServiceStatusChanged() {
    // Update the internal cameraController reference
    setCameraController(_cameraService.cameraController);
    // If the camera service reports an error, update our error message
    if (_cameraService.cameraErrorMessage != null) {
      setErrorMessage(_cameraService.cameraErrorMessage);
    } else if (_cameraService.isCameraInitialized && _errorMessage != null) {
      // Clear error if camera initialized successfully
      setErrorMessage(null);
    }
    // No need to notifyListeners here as setCameraController already does
  }

  /// Captures an image and then describes the scene using Gemini.
  Future<void> takePictureAndDescribeScene() async {
    if (_isProcessing) {
      _logger.w(
        "SceneDescriptionState: Already processing. Ignoring new request.",
      );
      return;
    }
    if (_cameraService.cameraController == null ||
        !_cameraService.cameraController!.value.isInitialized) {
      setErrorMessage('Camera is not initialized. Please wait or retry.');
      _logger.e("SceneDescriptionState: Camera not initialized for capture.");
      return;
    }

    _logger.i("SceneDescriptionState: Taking picture and describing scene.");
    _isProcessing = true;
    _sceneDescription = null;
    _errorMessage = null;
    _translatedText = ''; // Clear previous translation
    _detectedLanguage = ''; // Clear previous language
    _capturedImagePath = null;
    _speechService.stopSpeaking(); // Stop any ongoing speech
    notifyListeners();

    try {
      // Use CameraService to take the picture
      final XFile? imageFile = await _cameraService.takePicture();

      if (imageFile == null) {
        setErrorMessage('Failed to capture image.');
        _logger.e("SceneDescriptionState: Image file is null after capture.");
        return;
      }

      _capturedImagePath = imageFile.path;
      _logger.i(
        "SceneDescriptionState: Image captured to: $_capturedImagePath",
      );

      // Describe the image using Gemini
      final description = await _geminiService.describeImage(
        _capturedImagePath!,
      );
      // Assume description is in English by default from Gemini
      // Or, if Gemini could return language, use that. For now, default to English.
      _detectedLanguage = "English";

      _sceneDescription = description;
      _logger.i("SceneDescriptionState: Scene described successfully.");
      await _speechService.speak(description); // Speak the description aloud
      setErrorMessage(null); // Clear errors on success
    } catch (e, stack) {
      _logger.e(
        "SceneDescriptionState: Error describing scene: $e",
        error: e,
        stackTrace: stack,
      );
      setErrorMessage('Failed to describe scene: ${e.toString()}');
      _speechService.speak('Failed to describe scene.');
    } finally {
      _isProcessing = false;
      notifyListeners();
      // Optionally restart stream if needed after taking picture (e.g., if coming from live mode)
      // This logic should probably be handled by the page if it's in a live processing mode.
    }
  }

  /// Starts continuous, throttled scene description from the live camera feed.
  Future<void> startAutoDescription() async {
    if (_isAutoDescribing) {
      _logger.i("SceneDescriptionState: Auto-description already active.");
      return;
    }
    if (_cameraService.cameraController == null ||
        !_cameraService.cameraController!.value.isInitialized) {
      setErrorMessage('Camera is not initialized for auto-description.');
      _logger.e(
        "SceneDescriptionState: Camera not initialized for auto-description.",
      );
      return;
    }
    _logger.i("SceneDescriptionState: Starting auto-description.");
    _isAutoDescribing = true;
    _sceneDescription = null;
    _errorMessage = null;
    _translatedText = '';
    _detectedLanguage = '';
    _speechService.stopSpeaking();
    notifyListeners();

    // Start image stream through CameraService
    // The CameraService's startImageStream already takes a callback.
    await _cameraService.startImageStream(_processImageForAutoDescription);
  }

  /// Processes a camera image for auto-description, applying a throttler.
  Future<void> _processImageForAutoDescription(CameraImage image) async {
    if (!_isAutoDescribing || _isProcessing) {
      return; // Don't process if stopped or already busy
    }

    _liveDescriptionThrottler.run(() async {
      if (!_isAutoDescribing || _isProcessing) {
        return; // Double check inside throttler
      }

      _isProcessing =
          true; // Set processing flag for this individual description
      notifyListeners(); // Notify UI that processing started

      try {
        final path = await _saveImageTemporarily(image);
        if (path == null) {
          _logger.w(
            "SceneDescriptionState: Could not save image for auto-description.",
          );
          return;
        }

        final description = await _geminiService.describeImage(path);
        _detectedLanguage = "English"; // Assuming English from Gemini
        _sceneDescription = description;
        _logger.i("SceneDescriptionState: Auto-description: $description");
        await _speechService.speak(description);
        setErrorMessage(null);
      } catch (e, stack) {
        _logger.e(
          "SceneDescriptionState: Error during auto-description: $e",
          error: e,
          stackTrace: stack,
        );
        setErrorMessage('Auto-description failed: ${e.toString()}');
        _speechService.speak('Auto-description failed.');
      } finally {
        _isProcessing = false; // Reset processing flag
        notifyListeners(); // Notify UI that processing finished
      }
    });
  }

  // Future<void> sendToChat() async {
  //   if (_isProcessing) {
  //     _logger.w(
  //       "SceneDescriptionState: Already processing. Ignoring new request.",
  //     );
  //     return;
  //   }

  //   if (_sceneDescription!.isEmpty) {
  //     logger.w(
  //       "SceneDescriptionState: No Scene text available to send to chat.",
  //     );
  //     _speechService.speak("No description available to send to chat.");
  //     return;
  //   }

  //   try {
  //     logger.i(
  //       "SceneDescriptionState: Sending text to chat: \"$sceneDescription\"",
  //     );
  //     _
  //     _speechService.speak("Text sent to chat successfully.");
  //   } catch (e, stack) {
  //     logger.e(
  //       "TextReaderState: Error sending text to chat: $e",
  //       error: e,
  //       stackTrace: stack,
  //     );
  //     _setErrorMessage('Failed to send text to chat: ${e.toString()}');
  //     _speechService.speak("Failed to send text to chat.");
  //   }
  // }

  /// Stops continuous scene description from the live camera feed.
  Future<void> stopAutoDescription() async {
    if (!_isAutoDescribing) {
      _logger.i(
        "SceneDescriptionState: Auto-description not active. Nothing to stop.",
      );
      return;
    }
    _logger.i("SceneDescriptionState: Stopping auto-description.");
    _isAutoDescribing = false;
    _liveDescriptionThrottler
        .dispose(); // Dispose throttler to cancel pending calls
    await _cameraService.stopImageStream(); // Stop the image stream
    notifyListeners();
  }

  /// Saves a CameraImage to a temporary file.
  Future<String?> _saveImageTemporarily(CameraImage image) async {
    try {
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(path);

      // Convert CameraImage to a format suitable for saving (e.g., JPEG).
      // This is a placeholder; real-world implementation might need 'image' package
      // or platform-specific code to properly convert YUV/BGRA to JPEG.
      // For now, it's just saving the bytes of the first plane which might not be a valid JPEG.
      // IMPORTANT: For production, you'll need a proper image conversion here
      // (e.g., using 'image' package to encode to JPEG, or native platform code).
      await file.writeAsBytes(image.planes[0].bytes);
      _logger.d(
        "SceneDescriptionState: Temp image saved to: $path (Warning: may not be valid JPEG)",
      );
      return path;
    } catch (e) {
      _logger.e("SceneDescriptionState: Failed to save temporary image: $e");
      return null;
    }
  }

  /// Speaks the current text (translated if available, otherwise original description).
  Future<void> speakCurrentText() async {
    final textToSpeak =
        _translatedText.isNotEmpty ? _translatedText : _sceneDescription;

    if (textToSpeak != null && textToSpeak.isNotEmpty) {
      _logger.i("SceneDescriptionState: Speaking current text.");
      await _speechService.speak(textToSpeak);
    } else {
      _logger.w("SceneDescriptionState: No text available to speak.");
      await _speechService.speak("No scene description available yet.");
    }
  }

  /// Translates the current scene description to the target language.
  Future<void> translateDescription(String targetLanguage) async {
    if (_sceneDescription == null || _sceneDescription!.isEmpty) {
      setErrorMessage("No description to translate.");
      _speechService.speak("No description to translate.");
      return;
    }
    if (isAnyProcessingActive) {
      setErrorMessage("Already busy. Please wait.");
      return;
    }
    if (!_networkService.isOnline) {
      setErrorMessage("Cannot translate while offline.");
      _speechService.speak("Cannot translate text while offline.");
      return;
    }

    _isTranslating = true;
    _errorMessage = null;
    _speechService.stopSpeaking();
    notifyListeners();

    _logger.i(
      "SceneDescriptionState: Translating description to $targetLanguage.",
    );
    _speechService.speak("Translating to $targetLanguage.");

    try {
      final String translated = await _geminiService.translateText(
        _sceneDescription!,
        targetLanguage,
      );
      _translatedText = translated;

      final String? targetLanguageCode = _languageNameToCode[targetLanguage];
      if (targetLanguageCode != null) {
        _logger.i(
          "SceneDescriptionState: Attempting to set TTS language to $targetLanguageCode.",
        );
        final bool languageSet = await _speechService.setLanguage(
          targetLanguageCode,
        );
        if (!languageSet) {
          _logger.w(
            "SceneDescriptionState: Failed to set TTS language to $targetLanguageCode.",
          );
          setErrorMessage(
            "Failed to set speech language for $targetLanguage. Speaking in default.",
          );
        }
      } else {
        _logger.w(
          "SceneDescriptionState: Unknown target language '$targetLanguage'. Cannot set TTS language.",
        );
        setErrorMessage("Unknown language for speech. Speaking in default.");
      }
      await _speechService.speak(_translatedText);
    } catch (e) {
      _logger.e("SceneDescriptionState: Error translating description: $e");
      setErrorMessage("Failed to translate description: ${e.toString()}");
      _speechService.speak("Failed to translate description.");
    } finally {
      _isTranslating = false;
      notifyListeners();
    }
  }

  /// Sends the current scene description to the chat history.
  Future<void> sendDescriptionToChat() async {
    if (_sceneDescription == null || _sceneDescription!.isEmpty) {
      _logger.w("SceneDescriptionState: No description to send to chat.");
      _speechService.speak("There is no description to send.");
      return;
    }

    _logger.i("SceneDescriptionState: Sending scene description to chat.");
    final textToSend =
        _translatedText.isNotEmpty ? _translatedText : _sceneDescription!;

    try {
      // Assuming ChatService is accessible or a callback is used.
      // Add the scene description to the history as an assistant message.
      // ChatState listens to HistoryService and will update its UI.
      await _historyService.addAssistantMessage(
        "Scene Description: \"$textToSend\"",
      );
      _speechService.speak("Scene description sent to chat successfully.");
    } catch (e, stack) {
      _logger.e(
        "SceneDescriptionState: Error sending description to chat: $e",
        error: e,
        stackTrace: stack,
      );
      setErrorMessage('Failed to send description to chat: ${e.toString()}');
      _speechService.speak("Failed to send description to chat.");
    }
  }

  /// Clears all results and returns to initial state.
  void clearResults() {
    _logger.i("SceneDescriptionState: Clearing results.");
    _sceneDescription = null;
    _errorMessage = null;
    _translatedText = '';
    _detectedLanguage = '';
    _capturedImagePath = null;
    _isProcessing = false;
    _isAutoDescribing = false;
    _speechService.stopSpeaking();
    _isTranslating = false;
    _liveDescriptionThrottler
        .dispose(); // Ensure throttler is disposed on clear
    notifyListeners();
    // No need to resume camera here, as it's typically handled by initCamera on re-entry or auto-describe.
  }

  /// Sets an error message and notifies listeners.
  void setErrorMessage(String? message) {
    if (_errorMessage != message) {
      _errorMessage = message;
      _logger.w("SceneDescriptionState: Error message set: $message");
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _logger.i("SceneDescriptionState disposed.");
    _liveDescriptionThrottler.dispose(); // Ensure throttler is disposed
    // Remove listener from CameraService to prevent memory leaks.
    _cameraService.removeListener(_onCameraServiceStatusChanged);
    super.dispose();
  }
}
