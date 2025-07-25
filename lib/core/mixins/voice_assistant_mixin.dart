// lib/core/mixins/voice_assistant_mixin.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../services/speech_service.dart';
import '../../main.dart'; // For global logger
import '../services/speech_coordinator.dart';
import 'package:logger/logger.dart';

mixin VoiceAssistantMixin<T extends StatefulWidget> on State<T> {
  final SpeechCoordinator _speechCoordinator = SpeechCoordinator(
    SpeechService(),
  );
  final SpeechService _speechService = SpeechService();
  final Logger _logger = logger; // Use the global logger

  // Internal state variables
  String _voiceAssistantRecognizedText = '';
  String _voiceAssistantSpeakingText = '';
  bool _isVoiceAssistantListening = false;
  bool _isVoiceAssistantSpeaking = false;

  // Stream Subscriptions
  StreamSubscription<bool>? _listeningStatusSubscription;
  StreamSubscription<bool>? _speakingStatusSubscription;
  StreamSubscription<String>? _recognizedTextSubscription;
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
    final speechService = _speechService;
    _listeningStatusSubscription = speechService.listeningStatusStream.listen((
      status,
    ) {
      if (mounted) {
        setState(() {
          _isVoiceAssistantListening = status;
        });
      }
    });

    _speakingStatusSubscription = speechService.speakingStatusStream.listen((
      status,
    ) {
      if (mounted) {
        setState(() {
          _isVoiceAssistantSpeaking = status;
        });
      }
    });

    _recognizedTextSubscription = speechService.recognizedTextStream.listen((
      text,
    ) {
      if (mounted) {
        setState(() {
          _voiceAssistantRecognizedText = text;
        });
      }
    });

    _speakingTextSubscription = speechService.speakingTextStream.listen((text) {
      if (mounted) {
        setState(() {
          _voiceAssistantSpeakingText = text;
        });
      }
    });
  }

  void _subscribeToConnectivityChanges() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
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
      _logger.w(
        'Speech service already listening. Stopping first for a clean restart.',
      );
      _speechService.stopListening();
      await Future.delayed(const Duration(milliseconds: 300));
    }
    await _speechService.startListening(
      continuous: continuous,
    );
    if (await Vibration.hasVibrator() ?? false) {
      // Corrected null-aware operator for bool?
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
    await _speechCoordinator.speak(text);
  }

  void stopSpeaking() {
    _logger.i('Stopping speaking.');
    _speechCoordinator.stopSpeaking();
  }

  @override
  void dispose() {
    _listeningStatusSubscription?.cancel();
    _speakingStatusSubscription?.cancel();
    _recognizedTextSubscription?.cancel();
    _speakingTextSubscription?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
