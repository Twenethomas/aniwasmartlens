// lib/core/mixins/voice_assistant_mixin.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:vibration/vibration.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:provider/provider.dart'; // Import Provider

// Import the correct Speech Service file
import '../services/speech_service.dart';
// Removed Azure GPT Service as it's no longer directly used here.
// import '../services/azure_gpt_service.dart';
import '../services/chat_service.dart'; // Import ChatService-+
import '../../features/aniwa_chat/state/chat_state.dart'; // NEW: Import ChatState
import '../../main.dart'; // For global logger

mixin VoiceAssistantMixin<T extends StatefulWidget> on State<T> {
  final SpeechService _speechService = SpeechService();
  final Logger _logger = logger; // Use the global logger

  // Internal state variables
  String _voiceAssistantRecognizedText = '';
  String _voiceAssistantSpeakingText = '';
  bool _isVoiceAssistantListening = false;
  bool _isVoiceAssistantSpeaking = false;

  // Fields for duplicate command prevention
  String? _lastProcessedCommand;
  DateTime? _lastProcessedTime;

  // Stream Subscriptions
  StreamSubscription<bool>? _listeningStatusSubscription;
  StreamSubscription<bool>? _speakingStatusSubscription;
  StreamSubscription<String>? _recognizedTextSubscription;
  StreamSubscription<String>? _finalRecognizedTextSubscription;
  StreamSubscription<String>? _speakingTextSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Expose state for UI
  String get voiceAssistantRecognizedText => _voiceAssistantRecognizedText;
  String get voiceAssistantSpeakingText => _voiceAssistantSpeakingText;
  bool get isVoiceAssistantListening => _isVoiceAssistantListening;
  bool get isVoiceAssistantSpeaking => _isVoiceAssistantSpeaking;

  @override
  void initState() {
    super.initState();
    _subscribeToSpeechServiceStreams();
    _subscribeToConnectivityChanges();
  }

  void _subscribeToSpeechServiceStreams() {
    _listeningStatusSubscription =
        _speechService.listeningStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _isVoiceAssistantListening = status;
        });
      }
    });

    _speakingStatusSubscription =
        _speechService.speakingStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _isVoiceAssistantSpeaking = status;
        });
      }
    });

    _recognizedTextSubscription =
        _speechService.recognizedTextStream.listen((text) {
      if (mounted) {
        setState(() {
          _voiceAssistantRecognizedText = text;
        });
      }
    });

    _finalRecognizedTextSubscription =
        _speechService.finalRecognizedTextStream.listen((text) {
      if (mounted) {
        _logger.i('Final recognized text from Flutter STT: $text');
        _onFinalRecognizedText(text);
      }
    });

    _speakingTextSubscription = _speechService.speakingTextStream.listen((text) {
      if (mounted) {
        setState(() {
          _voiceAssistantSpeakingText = text;
        });
      }
    });
  }

  void _subscribeToConnectivityChanges() {
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final isOnline = !results.contains(ConnectivityResult.none);
      _logger.i('Connectivity changed. Online: $isOnline');
    });
  }

  /// Starts voice input.
  /// If `continuous` is true, it attempts to start continuous listening via SpeechService.
  /// Otherwise, it uses the SpeechService for a single, short listening session.
  Future<void> startVoiceInput({bool continuous = false}) async {
    _logger.i('Attempting to start voice input (continuous: $continuous)');
    _speechService.clearRecognizedText(); // Clear any stale text

    // Use the SpeechService for both continuous and non-continuous listening.
    if (_speechService.isListeningStt) {
      _logger.w('Speech service already listening. Stopping first for a clean restart.');
      _speechService.stopListening();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await _speechService.startListening(continuous: continuous);
    if (await Vibration.hasVibrator() ?? false) { // Corrected null-aware operator for bool?
      Vibration.vibrate(duration: 50); // Short haptic feedback
    }
    if (mounted) {
      setState(() {
        _isVoiceAssistantListening = _speechService.isListeningStt;
      });
    }
  }

  /// Stops voice input.
  /// Stops the Flutter SpeechService.
  void stopVoiceInput() {
    _logger.i('Stopping voice input.');
    _speechService.stopListening(); // Stop Flutter's STT
    if (mounted) {
      setState(() {
        _isVoiceAssistantListening = false;
      });
    }
  }

  Future<void> speak(String text) async {
    _logger.i('Speaking: $text');
    await _speechService.speak(text);
  }

  void stopSpeaking() {
    _logger.i('Stopping speaking.');
    _speechService.stopSpeaking();
  }

  Future<void> _onFinalRecognizedText(String command) async {
    if (command.isEmpty) {
      _logger.d('Empty command received, ignoring.');
      return;
    }

    // Prevent duplicate processing if the same command is recognized rapidly
    final now = DateTime.now();
    if (_lastProcessedCommand == command.toLowerCase().trim() &&
        _lastProcessedTime != null &&
        now.difference(_lastProcessedTime!) < const Duration(seconds: 2)) {
      _logger.w('Duplicate command "$command" ignored within 2 seconds.');
      return;
    }

    _lastProcessedCommand = command.toLowerCase().trim();
    _lastProcessedTime = now;

    _logger.i('Processing final recognized text: "$command"');

    // Delegate command processing to ChatState, which will then call ChatService
    if (mounted) {
      final chatState = Provider.of<ChatState>(context, listen: false);
      // Assuming ChatState has a method to process commands and takes BuildContext
      await chatState.processUserMessage(command, context);
    } else {
      _logger.e("VoiceAssistantMixin: Context not mounted, cannot process command via ChatState.");
    }
  }

  @override
  void dispose() {
    _listeningStatusSubscription?.cancel();
    _speakingStatusSubscription?.cancel();
    _recognizedTextSubscription?.cancel();
    _finalRecognizedTextSubscription?.cancel();
    _speakingTextSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
