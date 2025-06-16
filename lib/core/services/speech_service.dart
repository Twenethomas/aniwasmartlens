// lib/core/services/speech_service.dart
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart'; // Add this import
// Ensure this is also imported for PorcupineException

import '../../main.dart'; // For global logger

/// Custom exception for Porcupine initialization failures.
class PorcupineInitializationException implements Exception {
  final String message;
  PorcupineInitializationException(this.message);
  @override
  String toString() => "PorcupineInitializationException: $message";
}

class SpeechService extends ChangeNotifier {
  late FlutterTts _flutterTts;
  late stt.SpeechToText _speechToText;
  PorcupineManager? _porcupineManager;
  final Logger _logger = logger; // Use the global logger

  // TTS State
  bool _isSpeaking = false;
  String _speakingText = '';
  double _currentVolume = 1.0;
  double _currentSpeechRate = 0.5;
  double _currentPitch = 1.0;

  // STT State
  bool _isListeningStt = false;
  String _recognizedText = '';
  String _finalRecognizedText = '';
  Timer? _sttTimeoutTimer;
  Timer? _silenceTimer;
  DateTime?
  _lastSpeechTime; // Kept for potential future use in silence detection
  // New: Flag to indicate if STT was started manually (e.g., via mic button)
  bool _manualSttStart = false;
  // Public getter for manualSttStart
  bool get manualSttStart => _manualSttStart;

  // Wake Word State
  bool _isWakeWordListening = false;
  String _detectedWakeWord = '';
  bool _isPorcupineInitializing = false;
  bool _porcupineInitializationFailed = false;
  int _porcupineRetryCount = 0;
  static const int _maxPorcupineRetries = 3;
  Timer? _porcupineRetryTimer;

  // Expose wake word initialization status for ChatState
  bool get porcupineInitializationFailed => _porcupineInitializationFailed;
  bool get isPorcupineInitializing => _isPorcupineInitializing;

  // Microphone management
  bool _microphoneInUse = false;
  Completer<void>?
  _microphoneReleaseCompleter; // Use a Completer for explicit release signal
  static const Duration _microphoneReleaseDelay = Duration(
    milliseconds: 2000,
  ); // Increased delay

  // Configuration for improved listening
  static const Duration _maxSilenceDuration = Duration(
    seconds: 6,
  ); // Adjusted silence tolerance for conversational flow
  static const Duration _extendedListenDuration = Duration(
    minutes: 2,
  ); // Longer total listening time
  static const Duration _minPauseBetweenWords = Duration(
    seconds: 6,
  ); // Adjusted pause tolerance

  // Streams for external listeners
  final StreamController<bool> _listeningStatusController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _speakingStatusController =
      StreamController<bool>.broadcast();
  final StreamController<String> _recognizedTextController =
      StreamController<String>.broadcast();
  final StreamController<String> _finalRecognizedTextController =
      StreamController<String>.broadcast();
  final StreamController<String> _speakingTextController =
      StreamController<String>.broadcast();
  final StreamController<bool> _wakeWordListeningController =
      StreamController<bool>.broadcast();
  final StreamController<String> _wakeWordDetectedController =
      StreamController<String>.broadcast();

  // Getters for stream access
  Stream<bool> get listeningStatusStream => _listeningStatusController.stream;
  Stream<bool> get speakingStatusStream => _speakingStatusController.stream;
  Stream<String> get recognizedTextStream => _recognizedTextController.stream;
  Stream<String> get finalRecognizedTextStream =>
      _finalRecognizedTextController.stream;
  Stream<String> get speakingTextStream => _speakingTextController.stream;
  Stream<bool> get wakeWordListeningStream =>
      _wakeWordListeningController.stream;
  Stream<String> get wakeWordDetectedStream =>
      _wakeWordDetectedController.stream;

  // Getters for direct state access
  bool get isSpeaking => _isSpeaking;
  bool get isListeningStt => _isListeningStt;
  bool get isWakeWordListening => _isWakeWordListening;
  String get detectedWakeWord => _detectedWakeWord;
  String get recognizedText => _recognizedText;
  String get finalRecognizedText => _finalRecognizedText;
  double get currentVolume => _currentVolume;
  double get currentSpeechRate => 0.5;
  double get currentPitch => _currentPitch;

  // Private constructor for singleton
  SpeechService._internal() {
    _flutterTts = FlutterTts();
    _speechToText = stt.SpeechToText();
    // Initialize TTS and STT immediately with the singleton
    _initTts();
    _initStt();
  }

  // Singleton instance
  static final SpeechService _instance = SpeechService._internal();

  // Factory constructor to return the singleton instance
  factory SpeechService() {
    return _instance;
  }

  // Public init method to be called after the singleton is obtained
  Future<void> init() async {
    _logger.i(
      "SpeechService: Performing initial setup for TTS, STT, and Wake Word.",
    );
    // Initialize wake word with proper error handling
    await _initWakeWord();
  }

  // --- Microphone Management ---
  void _setMicrophoneInUse(bool inUse, String component) {
    _microphoneInUse = inUse;
    _logger.d("Microphone: ${inUse ? 'Acquired' : 'Released'} by $component");

    if (!inUse) {
      // Microphone is being released. Start a timer and create a completer.
      _microphoneReleaseCompleter = Completer<void>();
      Timer(_microphoneReleaseDelay, () {
        if (!(_microphoneReleaseCompleter?.isCompleted ?? true)) {
          _microphoneReleaseCompleter?.complete();
          _logger.d(
            "Microphone: Release delay completed, microphone fully available",
          );
        }
      });
    } else {
      // Microphone is being acquired. If a release completer exists and is not completed, complete it.
      if (!(_microphoneReleaseCompleter?.isCompleted ?? true)) {
        _microphoneReleaseCompleter
            ?.complete(); // Force complete if mic is re-acquired
        _logger.d(
          "Microphone: Acquisition interrupted pending release, forced completer.",
        );
      }
      _microphoneReleaseCompleter = null; // Clear completer
    }
  }

  Future<void> _waitForMicrophoneRelease() async {
    if (_microphoneInUse ||
        (_microphoneReleaseCompleter?.isCompleted == false)) {
      _logger.d("Microphone: Waiting for microphone to be fully released...");
      // If there's an active release process, wait for it to complete.
      if (_microphoneReleaseCompleter?.isCompleted == false) {
        await _microphoneReleaseCompleter!.future;
      }
      // Add a small extra delay to be absolutely safe after the completer,
      // or if it was already released but we want a small buffer.
      await Future.delayed(const Duration(milliseconds: 200));
      _microphoneInUse = false; // Explicitly set to false after waiting
      _logger.d("Microphone: Confirmed fully released after wait.");
    }
  }

  // --- Text-to-Speech (TTS) ---
  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(_currentSpeechRate);
    await _flutterTts.setVolume(_currentVolume);
    await _flutterTts.setPitch(_currentPitch);

    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
      _speakingStatusController.add(true);
      _logger.d("TTS: Started speaking: '$_speakingText'");
      notifyListeners();
    });

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      _speakingText = '';
      _speakingStatusController.add(false);
      _logger.d("TTS: Finished speaking.");
      _setMicrophoneInUse(false, "TTS completion"); // Release microphone
      notifyListeners();
      // After speaking finishes, we might want to automatically listen for follow-up
      // This logic will be handled by ChatState based on this status change.
    });

    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
      _speakingText = '';
      _speakingStatusController.add(false);
      _logger.e("TTS: Error occurred: $msg");
      _setMicrophoneInUse(false, "TTS error"); // Release microphone on error
      notifyListeners();
    });

    _flutterTts.setProgressHandler((text, start, end, word) {
      // Optional: Track speaking progress
      _logger.d(
        "TTS: Speaking progress - Text: '$text', Start: $start, End: $end, Word: '$word'",
      );
      notifyListeners();
    });

    _logger.i("TTS: Initialized successfully.");
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) {
      _logger.w("TTS: Attempted to speak empty text.");
      return;
    }

    // Stop STT before speaking to avoid microphone conflict
    if (_isListeningStt) {
      _logger.i("TTS: Stopping STT before speaking to acquire microphone.");
      await stopListening();
    }
    // Stop wake word listening before speaking if it's active
    if (_isWakeWordListening) {
      _logger.i(
        "TTS: Stopping wake word before speaking to acquire microphone.",
      );
      await stopWakeWordListening();
    }
    await _waitForMicrophoneRelease(); // Ensure microphone is free before trying to speak

    if (_isSpeaking) {
      await _flutterTts.stop();
      _logger.d("TTS: Stopped previous speech to speak new text.");
      _setMicrophoneInUse(
        false,
        "TTS stop before new speech",
      ); // Ensure mic is released from prior TTS
    }

    _speakingText = text;
    _speakingTextController.add(text);
    _logger.i("TTS: Speaking: '$text'");

    try {
      _setMicrophoneInUse(true, "TTS"); // Acquire microphone for TTS
      await _flutterTts.speak(text);
    } catch (e) {
      _logger.e("TTS: Error during speech: $e");
      _isSpeaking = false;
      _speakingText = '';
      _speakingStatusController.add(false);
      _setMicrophoneInUse(
        false,
        "TTS speech error",
      ); // Release microphone on error
      notifyListeners();
    }
  }

  Future<void> stopSpeaking() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      _isSpeaking = false;
      _speakingText = '';
      _speakingStatusController.add(false);
      _logger.i("TTS: Speech stopped by command.");
      _setMicrophoneInUse(false, "TTS stop command"); // Release microphone
      notifyListeners();
    }
  }

  Future<void> adjustVolume(double adjustment) async {
    _currentVolume = (_currentVolume + adjustment).clamp(0.0, 1.0);
    await _flutterTts.setVolume(_currentVolume);
    _logger.i("TTS: Volume adjusted to $_currentVolume");
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    _currentVolume = volume.clamp(0.0, 1.0);
    await _flutterTts.setVolume(_currentVolume);
    _logger.i("TTS: Volume set to $_currentVolume");
    notifyListeners();
  }

  Future<void> setSpeechRate(double rate) async {
    _currentSpeechRate = rate.clamp(0.1, 1.0);
    await _flutterTts.setSpeechRate(_currentSpeechRate);
    _logger.i("TTS: Speech rate set to $_currentSpeechRate");
    notifyListeners();
  }

  Future<void> setPitch(double pitch) async {
    _currentPitch = pitch.clamp(0.5, 2.0);
    await _flutterTts.setPitch(_currentPitch);
    _logger.i("TTS: Pitch set to $_currentPitch");
    notifyListeners();
  }

  /// Sets the TTS language to the given BCP-47 language code (e.g., 'en-US', 'es-ES').
  /// Returns true if the language was successfully set, false otherwise.
  Future<bool> setLanguage(String languageCode) async {
    try {
      final List<dynamic> languages = await _flutterTts.getLanguages;
      if (languages.contains(languageCode)) {
        await _flutterTts.setLanguage(languageCode);
        _logger.i("TTS: Language set to: $languageCode");
        return true;
      } else {
        _logger.w("TTS: Language $languageCode not supported by TTS engine.");
        return false;
      }
    } catch (e) {
      _logger.e("TTS: Error setting language: $e");
      return false;
    }
  }

  // --- Speech-to-Text (STT) ---
  Future<void> _initStt() async {
    bool available = await _speechToText.initialize(
      onStatus: (status) {
        _logger.d("STT: Status changed to: $status");

        if (status == stt.SpeechToText.listeningStatus) {
          _isListeningStt = true;
          _lastSpeechTime = DateTime.now();
          _setMicrophoneInUse(true, "STT"); // Acquire microphone for STT
        } else if (status == stt.SpeechToText.notListeningStatus ||
            status == stt.SpeechToText.doneStatus) {
          _isListeningStt = false;
          _setMicrophoneInUse(false, "STT"); // Release microphone
          _sttTimeoutTimer?.cancel();
          _silenceTimer?.cancel();

          // Only send empty final text if no actual text was recognized and STT session ended
          if (_finalRecognizedText.isEmpty && _recognizedText.isNotEmpty) {
            // Promote interim to final if session ended without explicit final and interim exists
            _finalRecognizedText = _recognizedText;
            _finalRecognizedTextController.add(_finalRecognizedText);
            _logger.i(
              "STT: Listening stopped. Sent interim text as final: '$_finalRecognizedText'",
            );
          } else if (_finalRecognizedText.isEmpty) {
            _logger.i(
              "STT: Listening stopped with no recognized text. Sending empty final text.",
            );
            _finalRecognizedTextController.add(
              '',
            ); // Explicitly send empty final text
          }
          // The ChatState will now handle restarting wake word or continuous listening.
        }

        _listeningStatusController.add(_isListeningStt);
        notifyListeners();
      },
      onError: (errorNotification) {
        _logger.e(
          "STT: Error: ${errorNotification.errorMsg} (Type: ${errorNotification.runtimeType})",
        );
        _isListeningStt = false;
        _setMicrophoneInUse(false, "STT error"); // Release microphone on error
        _listeningStatusController.add(false);
        _sttTimeoutTimer?.cancel();
        _silenceTimer?.cancel();

        // Always explicitly send empty final text on error if nothing was recognized
        if (_finalRecognizedText.isEmpty) {
          _finalRecognizedTextController.add('');
        }
        // The ChatState will now handle restarting wake word or continuous listening.
        notifyListeners();
      },
    );

    if (available) {
      _logger.i("STT: Initialized successfully.");
    } else {
      _logger.e(
        "STT: Initialization failed. Speech recognition not available.",
      );
    }
  }

  Future<bool> checkMicrophonePermission() async {
    final status = await Permission.microphone.status;

    if (status.isDenied || status.isRestricted) {
      _logger.w("Microphone permission not granted. Requesting...");
      final result = await Permission.microphone.request();
      return result.isGranted;
    } else if (status.isPermanentlyDenied) {
      _logger.e(
        "Microphone permission permanently denied. Please enable in settings.",
      );
      return false;
    }

    return status.isGranted;
  }

  Future<void> startListening({
    bool continuous = false,
    Duration? listenFor,
    Duration? pauseFor,
    bool manualStart = false, // New parameter to track manual initiation
  }) async {
    final hasPermission = await checkMicrophonePermission();
    if (!hasPermission) {
      _logger.w(
        "STT: Cannot start listening, microphone permission not granted.",
      );
      return;
    }

    // --- CRITICAL CHANGE HERE ---
    // Ensure microphone is fully released before attempting to start STT.
    await _waitForMicrophoneRelease();

    // If wake word detection was active, stop it here.
    if (_isWakeWordListening) {
      _logger.i("STT: Stopping wake word detection before STT");
      await stopWakeWordListening();
    }

    if (_isListeningStt) {
      _logger.w("STT: Already listening. Stopping current session first.");
      await stopListening();
      await Future.delayed(const Duration(milliseconds: 300)); // Small buffer
    }

    // Clear previous results before starting a new session
    _recognizedText = '';
    _finalRecognizedText = '';
    _recognizedTextController.add('');
    _finalRecognizedTextController.add(''); // Ensure stream is cleared
    _manualSttStart = manualStart; // Set the manual start flag
    notifyListeners();

    try {
      // Use extended durations for better user experience
      final Duration actualListenFor =
          listenFor ??
          (continuous ? const Duration(hours: 1) : _extendedListenDuration);
      final Duration actualPauseFor = pauseFor ?? _minPauseBetweenWords;

      await _speechToText.listen(
        onResult: (result) {
          _lastSpeechTime = DateTime.now();
          _recognizedText = result.recognizedWords;
          _recognizedTextController.add(_recognizedText);

          _logger.d(
            "STT: Recognized: '$_recognizedText' (final: ${result.finalResult}, confidence: ${result.confidence})",
          );

          // Reset silence timer when we get speech or partial results
          _resetSilenceTimer(continuous);

          if (result.finalResult) {
            _finalRecognizedText = result.recognizedWords;
            _finalRecognizedTextController.add(_finalRecognizedText);
            _logger.i("STT: Final result: '$_finalRecognizedText'");
            // In non-continuous mode, stop immediately on final result
            if (!continuous) {
              stopListening();
            }
          }
          notifyListeners();
        },
        listenFor: actualListenFor,
        pauseFor: actualPauseFor,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
        ), // Use options
        localeId: "en_US",
        onSoundLevelChange: (level) {
          // Reset silence timer on significant sound detection
          if (level > -30) {
            // Adjust threshold as needed
            _lastSpeechTime = DateTime.now();
          }
        },
      );

      _isListeningStt = true;
      _listeningStatusController.add(true);
      _logger.i(
        "STT: Started listening (continuous: $continuous, duration: ${actualListenFor.inSeconds}s, pause: ${actualPauseFor.inSeconds}s, manual: $manualStart)",
      );

      // Set main timeout timer (for overall session duration)
      _sttTimeoutTimer?.cancel();
      _sttTimeoutTimer = Timer(actualListenFor, () {
        if (_isListeningStt) {
          _logger.i("STT: Maximum listen duration reached");
          stopListening();
        }
      });

      // Start silence monitoring for non-continuous mode
      if (!continuous) {
        _startSilenceTimer();
      }

      notifyListeners();
    } catch (e) {
      _logger.e("STT: Error starting listening: $e");
      _isListeningStt = false;
      _setMicrophoneInUse(
        false,
        "STT start error",
      ); // Release microphone on error
      _listeningStatusController.add(false);
      // Explicitly send empty final text on start error if nothing was recognized
      if (_finalRecognizedText.isEmpty) {
        _finalRecognizedTextController.add('');
      }
      notifyListeners();
    }
  }

  /// Force preempt microphone from wake word detection immediately.
  /// Stops wake word listening and releases microphone without delay.
  Future<void> forcePreemptMicrophoneFromWakeWord() async {
    if (_isWakeWordListening) {
      _logger.i("Mic Preempt: Forcing stop of wake word listening.");
      await stopWakeWordListening();
      // Immediately release microphone without delay
      _microphoneInUse = false;
      if (!(_microphoneReleaseCompleter?.isCompleted ?? true)) {
        _microphoneReleaseCompleter?.complete();
      }
      _logger.i(
        "Mic Preempt: Microphone released immediately after preemption.",
      );
      notifyListeners();
    }
  }

  void _startSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(_maxSilenceDuration, () {
      if (_isListeningStt) {
        _logger.i("STT: Stopping due to extended silence.");
        // If there was any recognized text (even partial) before silence, send it as final
        if (_recognizedText.isNotEmpty) {
          _finalRecognizedText = _recognizedText;
          _finalRecognizedTextController.add(_finalRecognizedText);
          _logger.i("STT: Final result from silence: '$_finalRecognizedText'");
        } else {
          // If no text was recognized at all during the listening period and silence timeout hit
          _logger.i("STT: No text recognized during silence period.");
          _finalRecognizedText = '';
          _finalRecognizedTextController.add('');
        }
        stopListening(); // This will trigger the onStatus 'done' or 'notListening'
      }
    });
  }

  void _resetSilenceTimer(bool continuous) {
    // We only actively manage the _silenceTimer for non-continuous listening
    // or when we want to enforce an explicit timeout after an utterance
    // in continuous mode. For a purely conversational continuous mode,
    // the STT engine's internal `pauseFor` might be sufficient.
    // However, to ensure a smooth transition back to wake word if the user
    // simply stops talking, our silence timer is useful.
    // If it's a manual continuous session, keep extending the silence timer
    // with each new recognized word to allow for natural conversation pauses.
    // If it's a one-shot (not continuous), then _startSilenceTimer handles it.
    if (continuous) {
      _silenceTimer?.cancel(); // Cancel previous timer
      _silenceTimer = Timer(_maxSilenceDuration, () {
        if (_isListeningStt) {
          _logger.i(
            "STT: Continuous listening stopping due to extended silence in conversation.",
          );
          stopListening(); // Stop the continuous session
        }
      });
    }
  }

  Future<void> startExtendedListening({
    Duration? maxDuration,
    bool manualStart = false,
  }) async {
    final duration = maxDuration ?? const Duration(minutes: 5);
    await startListening(
      continuous: true, // Use continuous mode to allow for longer sessions
      listenFor: duration,
      pauseFor: const Duration(
        seconds: 4,
      ), // Allow reasonable pauses within continuous session
      manualStart: manualStart, // Propagate manualStart
    );
  }

  Future<void> stopListening() async {
    if (_isListeningStt) {
      try {
        await _speechToText.stop();
        _logger.i("STT: Explicitly calling stopListening.");
        // The _initStt's onStatus handler will now take care of setting
        // _isListeningStt to false, releasing microphone, canceling timers,
        // and adding final text to stream.
        notifyListeners();
      } catch (e) {
        _logger.e("STT: Error stopping listening: $e");
        _setMicrophoneInUse(
          false,
          "STT stop error",
        ); // Ensure mic is released on error
      }
    }
  }

  void clearRecognizedText() {
    _recognizedText = '';
    _finalRecognizedText = '';
    _recognizedTextController.add('');
    _finalRecognizedTextController.add('');
    notifyListeners();
  }

  // --- Wake Word Detection (Porcupine) - IMPROVED ---
  Future<void> _initWakeWord() async {
    if (_isPorcupineInitializing) {
      _logger.w(
        "Wake Word: Already initializing, skipping duplicate initialization.",
      );
      return;
    }
    if (_porcupineInitializationFailed &&
        _porcupineRetryCount >= _maxPorcupineRetries) {
      _logger.e(
        "Wake Word: Max retries exceeded. Wake word detection disabled.",
      );
      return;
    }
    _isPorcupineInitializing = true;
    _logger.i(
      "Wake Word: Initializing... (Attempt ${_porcupineRetryCount + 1})",
    );
    try {
      // Ensure clean state before initialization
      await _cleanupPorcupine();
      // Check microphone permission before initializing Porcupine
      final hasPermission = await checkMicrophonePermission();
      if (!hasPermission) {
        _logger.e(
          "Wake Word: Microphone permission not granted. Cannot initialize wake word detection.",
        );
        _porcupineInitializationFailed = true;
        _isPorcupineInitializing = false;
        _isWakeWordListening = false;
        _wakeWordListeningController.add(false);
        _setMicrophoneInUse(false, "Porcupine init no perm");
        notifyListeners();
        return;
      }
      // Wait for microphone to be fully released
      await _waitForMicrophoneRelease();

      // Initialize Porcupine with custom wake word
      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        "FJ3CNOTKkH9oBhjMCp20gq/dK4JR6sKuwLDVv1UXxs7Fy+TqcaUuRQ==", // Your Picovoice access key
        [
          "assets/ml/Assistive-lens_en_android_v3_0_0.ppn",
        ], // Custom wake word model path (keywordIndex)
        (keywordIndex) {
          _handleWakeWordDetection(keywordIndex);
        },
        errorCallback: (error) {
          _logger.e("Wake Word: Runtime Porcupine Error: $error");
          _handlePorcupineRuntimeError(error);
        },
        sensitivities: [0.5], // Adjust sensitivity (0.0 to 1.0)
      );
      _logger.i("Wake Word: PorcupineManager created successfully.");
      // Start Porcupine listening immediately after successful initialization
      await _porcupineManager!.start();
      _isWakeWordListening = true;
      _setMicrophoneInUse(true, "Porcupine");
      _wakeWordListeningController.add(true);
      _porcupineInitializationFailed = false;
      _porcupineRetryCount = 0; // Reset retry count on success
      _logger.i("Wake Word: Started listening for 'assist lens'.");
      notifyListeners();
    } on PorcupineException catch (e) {
      _logger.e(
        "Wake Word: PorcupineException during initialization: ${e.message}",
      );
      await _handlePorcupineInitializationError(e);
    } catch (e) {
      _logger.e("Wake Word: General error during initialization: $e");
      await _handlePorcupineInitializationError(e);
    } finally {
      _isPorcupineInitializing = false;
    }
  }

  Future<void> _cleanupPorcupine() async {
    if (_porcupineManager != null) {
      _logger.d("Wake Word: Cleaning up existing PorcupineManager.");
      try {
        if (_isWakeWordListening) {
          await _porcupineManager!.stop();
        }
        await _porcupineManager!.delete();
        _porcupineManager = null;
        _isWakeWordListening = false;
        _wakeWordListeningController.add(false);
        _setMicrophoneInUse(false, "Porcupine cleanup");
      } catch (e) {
        _logger.e("Wake Word: Error during Porcupine cleanup: $e");
      }
    }
  }

  Future<void> _handlePorcupineInitializationError(dynamic error) async {
    _porcupineInitializationFailed = true;
    _isPorcupineInitializing = false;
    _isWakeWordListening = false;
    _wakeWordListeningController.add(false);
    _setMicrophoneInUse(false, "Porcupine init error");
    _porcupineRetryCount++;
    _logger.e(
      "Wake Word: Initialization failed (attempt $_porcupineRetryCount). Error: $error",
    );
    notifyListeners();

    if (_porcupineRetryCount < _maxPorcupineRetries) {
      _logger.i("Wake Word: Retrying initialization in 5 seconds...");
      _porcupineRetryTimer?.cancel();
      _porcupineRetryTimer = Timer(const Duration(seconds: 5), () {
        _initWakeWord(); // Attempt re-initialization
      });
    } else {
      _logger.e(
        "Wake Word: Max initialization retries reached. Wake word detection permanently disabled.",
      );
      throw PorcupineInitializationException(
          "Max retries reached for Porcupine initialization. Error: $error");
    }
  }

  void _handlePorcupineRuntimeError(PorcupineException error) {
    _logger.e("Wake Word: Runtime error: ${error.message}");
    _isWakeWordListening = false;
    _wakeWordListeningController.add(false);
    _setMicrophoneInUse(false, "Porcupine runtime error");
    _porcupineInitializationFailed =
        true; // Consider runtime errors as a failure for fallback
    notifyListeners();
    // Attempt to recover by reinitializing or inform ChatState to switch modes
    _logger.i("Wake Word: Attempting to reinitialize after runtime error...");
    _initWakeWord(); // Try to restart Porcupine
  }

  void _handleWakeWordDetection(int keywordIndex) {
    String wakeWord = '';
    switch (keywordIndex) {
      case 0:
        wakeWord = 'assistive lens';
        break;
      default:
        wakeWord = 'unknown';
    }

    _detectedWakeWord = wakeWord;
    _wakeWordDetectedController.add(wakeWord);
    _logger.i("Wake Word: Detected '$wakeWord' at index $keywordIndex");
    notifyListeners();

    // Stop Porcupine listening immediately when wake word is detected
    // This releases the microphone from Porcupine.
    stopWakeWordListening()
        .then((_) {
          _logger.i(
            "Wake Word: Porcupine stopped after detection. ChatState will now handle STT.",
          );
          // Don't start STT here, ChatState will handle starting STT
          // after processing the wake word detection. This prevents
          // race conditions and ensures ChatState has full control.
        })
        .catchError((e) {
          _logger.e("Wake Word: Error stopping Porcupine after detection: $e");
          _wakeWordDetectedController.add('error');
          notifyListeners();
        });
  }

  Future<void> startWakeWordListening() async {
    // Only start if not already listening, not initializing, and not failed permanently
    if (!_isWakeWordListening &&
        !_isPorcupineInitializing &&
        !_porcupineInitializationFailed) {
      if (_porcupineManager != null) {
        _logger.i("Wake Word: Starting listening...");
        try {
          await _waitForMicrophoneRelease(); // Ensure microphone is free
          await _porcupineManager!.start();
          _isWakeWordListening = true;
          _setMicrophoneInUse(true, "Porcupine");
          _wakeWordListeningController.add(true);
          _logger.i("Wake Word: Started listening for 'assist lens'.");
        } catch (e) {
          _logger.e("Wake Word: Error starting Porcupine listening: $e");
          _handlePorcupineRuntimeError(
            PorcupineException(
              "Failed to start listening: $e",
            ), // Use PorcupineException
          );
        }
      } else {
        _logger.w(
          "Wake Word: PorcupineManager not initialized. Attempting initialization.",
        );
        await _initWakeWord(); // Try to initialize if null
      }
    } else if (_porcupineInitializationFailed) {
      _logger.w(
        "Wake Word: Cannot start listening, Porcupine initialization failed permanently.",
      );
    } else if (_isPorcupineInitializing) {
      _logger.w(
        "Wake Word: Cannot start listening, Porcupine is initializing.",
      );
    } else {
      _logger.d("Wake Word: Already listening for wake word.");
    }
    notifyListeners();
  }

  Future<void> stopWakeWordListening() async {
    if (_isWakeWordListening && _porcupineManager != null) {
      _logger.i("Wake Word: Stopping listening.");
      try {
        await _porcupineManager!.stop();
        _isWakeWordListening = false;
        _wakeWordListeningController.add(false);
        _setMicrophoneInUse(false, "Porcupine");
      } catch (e) {
        _logger.e("Wake Word: Error stopping Porcupine listening: $e");
      }
    }
    notifyListeners();
  }

  /// Checks if speech recognition (STT) is available.
  Future<bool> isSpeechRecognitionAvailable() async {
    // This checks if the STT engine itself is available
    return await _speechToText.initialize();
  }

  /// Performs a full restart of all speech services.
  Future<void> restartAll() async {
    _logger.i("SpeechService: Restarting all speech services...");
    await forceCleanup();
    await init();
    _logger.i("SpeechService: All speech services restarted.");
  }

  /// Forces a cleanup of all active speech recognition components.
  Future<void> forceCleanup() async {
    _logger.i("SpeechService: Performing force cleanup...");

    _sttTimeoutTimer?.cancel();
    _silenceTimer?.cancel();
    _porcupineRetryTimer?.cancel();
    // Removed _followUpTimer from here as it belongs to ChatState.

    await stopListening(); // Stop STT
    await stopSpeaking(); // Stop TTS
    await _cleanupPorcupine(); // Stop and delete Porcupine

    // Clear state variables
    _isSpeaking = false;
    _isListeningStt = false;
    _isWakeWordListening = false;
    _recognizedText = '';
    _finalRecognizedText = '';
    _speakingText = '';
    _detectedWakeWord = '';

    // Reset all state
    _microphoneInUse = false;
    _microphoneReleaseCompleter = null; // Ensure completer is reset
    _porcupineInitializationFailed = false;
    _porcupineRetryCount = 0;
    _manualSttStart = false; // Reset manual start flag

    // Notify listeners of clean state
    notifyListeners();

    _logger.i("SpeechService: Force cleanup completed.");
  }

  // --- Error Recovery Methods ---

  /// Attempts to recover from errors by reinitializing all services
  Future<bool> recoverFromError() async {
    _logger.i("SpeechService: Attempting error recovery...");

    try {
      await forceCleanup();
      await Future.delayed(const Duration(seconds: 2));
      await restartAll();
      _logger.i("SpeechService: Error recovery successful.");
      return true;
    } catch (e) {
      _logger.e("SpeechService: Error recovery failed: $e");
      return false;
    }
  }

  /// Gets health status of all services
  Map<String, bool> getHealthStatus() {
    return {
      'tts_healthy': !_isSpeaking || _speakingText.isNotEmpty,
      'stt_healthy': _speechToText.isAvailable,
      'wake_word_healthy':
          (_porcupineManager != null && !_porcupineInitializationFailed) ||
          _isWakeWordListening,
      'microphone_available':
          _speechToText.isAvailable, // Basic check for mic availability
    };
  }

  @override
  void dispose() {
    _logger.i("SpeechService: Disposing SpeechService...");
    _sttTimeoutTimer?.cancel();
    _silenceTimer?.cancel();
    _porcupineRetryTimer?.cancel();
    _listeningStatusController.close();
    _speakingStatusController.close();
    _recognizedTextController.close();
    _finalRecognizedTextController.close();
    _speakingTextController.close();
    _wakeWordListeningController.close();
    _wakeWordDetectedController.close();
    _flutterTts.stop();
    _speechToText.stop();
    _cleanupPorcupine(); // Clean up Porcupine manager
    super.dispose();
  }
}
