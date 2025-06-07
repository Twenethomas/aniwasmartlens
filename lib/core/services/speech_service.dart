// lib/core/services/speech_service.dart
import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart'; // Import permission_handler
import 'package:flutter/foundation.dart'; // For @required and ChangeNotifier

import '../../main.dart'; // For global logger

class SpeechService extends ChangeNotifier {
  late FlutterTts _flutterTts;
  late stt.SpeechToText _speechToText;
  final Logger _logger = logger; // Use the global logger

  // TTS State
  bool _isSpeaking = false;
  String _speakingText = '';

  // STT State
  bool _isListeningStt = false;
  String _recognizedText = '';
  String _finalRecognizedText = ''; // Stores the complete sentence/command after speech ends

  // Streams for external listeners
  final StreamController<bool> _listeningStatusController = StreamController<bool>.broadcast();
  final StreamController<bool> _speakingStatusController = StreamController<bool>.broadcast();
  final StreamController<String> _recognizedTextController = StreamController<String>.broadcast();
  final StreamController<String> _finalRecognizedTextController = StreamController<String>.broadcast();
  final StreamController<String> _speakingTextController = StreamController<String>.broadcast();

  // Getters for stream access
  Stream<bool> get listeningStatusStream => _listeningStatusController.stream;
  Stream<bool> get speakingStatusStream => _speakingStatusController.stream;
  Stream<String> get recognizedTextStream => _recognizedTextController.stream;
  Stream<String> get finalRecognizedTextStream => _finalRecognizedTextController.stream;
  Stream<String> get speakingTextStream => _speakingTextController.stream;

  // Getters for direct state access (useful for immediate checks)
  bool get isSpeaking => _isSpeaking;
  bool get isListeningStt => _isListeningStt;

  SpeechService() {
    _flutterTts = FlutterTts();
    _speechToText = stt.SpeechToText();
  }

  Future<void> init() async {
    _logger.i("SpeechService: Initializing TTS and STT.");
    await _initTts();
    await _initStt();
  }

  // --- Text-to-Speech (TTS) ---
  Future<void> _initTts() async {
    _flutterTts.setLanguage("en-US"); // Default language
    _flutterTts.setSpeechRate(0.5); // Normal speed
    _flutterTts.setVolume(1.0); // Full volume
    _flutterTts.setPitch(1.0); // Normal pitch

    _flutterTts.setStartHandler(() {
      _isSpeaking = true;
      _speakingStatusController.add(true);
      _logger.d("TTS: Started speaking.");
      notifyListeners();
    });

    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      _speakingText = ''; // Clear text on completion
      _speakingStatusController.add(false);
      _logger.d("TTS: Finished speaking.");
      notifyListeners();
    });

    _flutterTts.setErrorHandler((msg) {
      _isSpeaking = false;
      _speakingText = ''; // Clear text on error
      _speakingStatusController.add(false);
      _logger.e("TTS: Error occurred: $msg");
      notifyListeners();
    });

    _flutterTts.setProgressHandler((text, start, end, word) {
      // Update the currently speaking word or phrase
      _speakingText = text;
      _speakingTextController.add(text);
      notifyListeners();
    });
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) {
      _logger.w("TTS: Attempted to speak empty text.");
      return;
    }
    if (_isSpeaking) {
      await _flutterTts.stop(); // Stop current speech if any
      _logger.d("TTS: Stopped previous speech to speak new text.");
    }
    _speakingText = text; // Set the full text being spoken
    _speakingTextController.add(text);
    _logger.i("TTS: Attempting to speak: '$text'");
    await _flutterTts.speak(text);
  }

  Future<void> stopSpeaking() async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      _isSpeaking = false;
      _speakingText = '';
      _speakingStatusController.add(false);
      _logger.i("TTS: Speech stopped by command.");
      notifyListeners();
    }
  }

  // --- Speech-to-Text (STT) ---
  Future<void> _initStt() async {
    bool available = await _speechToText.initialize(
      onStatus: (status) {
        _logger.d("STT: Status: $status");
        if (status == stt.SpeechToText.listeningStatus) {
          _isListeningStt = true;
        } else {
          _isListeningStt = false;
        }
        _listeningStatusController.add(_isListeningStt);
        notifyListeners();
      },
      onError: (errorNotification) {
        _logger.e("STT: Error: ${errorNotification.errorMsg}");
        _isListeningStt = false;
        _listeningStatusController.add(false);
        _recognizedText = ''; // Clear recognized text on error
        _finalRecognizedText = ''; // Clear final text on error
        _recognizedTextController.add('');
        _finalRecognizedTextController.add('');
        notifyListeners();
      },
    );

    if (available) {
      _logger.i("STT: Initialized successfully.");
    } else {
      _logger.e("STT: Initialization failed. Speech recognition not available.");
    }
  }

  Future<bool> checkMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (status.isDenied || status.isRestricted || status.isPermanentlyDenied) {
      _logger.w("Microphone permission not granted. Requesting...");
      final result = await Permission.microphone.request();
      return result.isGranted;
    }
    return status.isGranted;
  }

  /// Starts continuous or non-continuous speech recognition.
  Future<void> startListening({bool continuous = false}) async {
    final hasPermission = await checkMicrophonePermission();
    if (!hasPermission) {
      _logger.w("STT: Cannot start listening, microphone permission not granted.");
      return;
    }

    if (_isListeningStt) {
      _logger.w("STT: Already listening. Stopping current session before starting a new one.");
      await _speechToText.stop();
      await Future.delayed(const Duration(milliseconds: 200)); // Small delay for state update
    }
    
    _recognizedText = ''; // Clear previous recognized text
    _finalRecognizedText = ''; // Clear previous final text
    _recognizedTextController.add('');
    _finalRecognizedTextController.add('');
    notifyListeners();

    try {
      await _speechToText.listen(
        onResult: (result) {
          _recognizedText = result.recognizedWords;
          _recognizedTextController.add(_recognizedText);
          _logger.d("STT: Recognized: $_recognizedText (final: ${result.finalResult})");

          if (result.finalResult) {
            _finalRecognizedText = result.recognizedWords;
            _finalRecognizedTextController.add(_finalRecognizedText);
            _logger.i("STT: Final Recognized: $_finalRecognizedText");
            if (!continuous) {
              stopListening(); // Stop if not continuous and final result
            }
          }
          notifyListeners();
        },
        listenFor: continuous ? const Duration(hours: 1) : const Duration(seconds: 5), // Listen for longer if continuous
        pauseFor: const Duration(seconds: 3), // Pause before ending if no speech
        partialResults: true,
        localeId: "en_US", // Specify locale
      );
      _isListeningStt = true;
      _listeningStatusController.add(true);
      _logger.i("STT: Started listening (continuous: $continuous).");
      notifyListeners();
    } catch (e) {
      _logger.e("STT: Error starting listening: $e");
      _isListeningStt = false;
      _listeningStatusController.add(false);
      notifyListeners();
    }
  }

  Future<void> stopListening() async {
    if (_isListeningStt) {
      await _speechToText.stop();
      _isListeningStt = false;
      _listeningStatusController.add(false);
      _logger.i("STT: Listening stopped by command.");
      // The final result will be pushed by onResult handler before this.
      notifyListeners();
    }
  }

  void clearRecognizedText() {
    _recognizedText = '';
    _finalRecognizedText = '';
    _recognizedTextController.add('');
    _finalRecognizedTextController.add('');
    notifyListeners();
  }

  @override
  void dispose() {
    _logger.i("SpeechService: Disposing.");
    _flutterTts.stop();
    _speechToText.cancel(); // Use cancel to ensure resources are freed
    _listeningStatusController.close();
    _speakingStatusController.close();
    _recognizedTextController.close();
    _finalRecognizedTextController.close();
    _speakingTextController.close();
    super.dispose();
  }
}
