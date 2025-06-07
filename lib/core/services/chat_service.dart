// lib/core/services/chat_service.dart
import 'dart:async';
import 'package:flutter/material.dart'; // Only for TimeOfDay, not for UI
import 'package:logger/logger.dart';
// Removed unused import: import 'package:connectivity_plus/connectivity_plus.dart';

import 'speech_service.dart';
import 'gemini_service.dart';
import '../routing/app_router.dart';
import 'history_services.dart';
import 'network_service.dart';

// Global logger instance from main.dart
import '../../main.dart';


class ChatService {
  final SpeechService _speechService;
  final GeminiService _geminiService;
  final HistoryService _historyService;
  final NetworkService _networkService;
  final Logger _logger;

  // Callbacks to update ChatState - these are provided by ChatState itself
  final Function(List<Map<String, String>>) onHistoryUpdated;
  final Function(bool) onProcessingStatusChanged;
  final Future<void> Function(String) onSpeak;
  final Function() onVibrate;
  final Function(String routeName, {Object? arguments}) onNavigate;

  // Internal state for command processing guard
  bool _isProcessingCommand = false;
  String? _lastProcessedCommand;
  DateTime? _lastProcessedTime;

  late final Map<
    String,
    Future<void> Function(BuildContext? context, String fullCommand)
  > _commandHandlers;

  ChatService(
    this._speechService,
    this._geminiService,
    this._historyService,
    this._networkService,
    {
    required this.onHistoryUpdated,
    required this.onProcessingStatusChanged,
    required this.onSpeak,
    required this.onVibrate,
    required this.onNavigate,
  }) : _logger = logger { // Use the global logger instance
    _commandHandlers = {
      'open chat': (context, fullCommand) => _handleOpenChat(context),
      'go to chat': (context, fullCommand) => _handleOpenChat(context),
      'open text reader': (context, fullCommand) => _handleOpenTextReader(context),
      'read text': (context, fullCommand) => _handleOpenTextReader(context),
      'open scene description': (context, fullCommand) => _handleOpenSceneDescription(context),
      'describe scene': (context, fullCommand) => _handleOpenSceneDescription(context),
      'open navigation': (context, fullCommand) => _handleOpenNavigation(context),
      'start navigation': (context, fullCommand) => _handleOpenNavigation(context),
      'open emergency': (context, fullCommand) => _handleOpenEmergency(context),
      'emergency': (context, fullCommand) => _handleOpenEmergency(context),
      'open history': (context, fullCommand) => _handleOpenHistory(context),
      'view history': (context, fullCommand) => _handleOpenHistory(context),
      'open object detection': (context, fullCommand) => _handleOpenObjectDetection(context),
      'detect object': (context, fullCommand) => _handleOpenObjectDetection(context),
      'open facial recognition': (context, fullCommand) => _handleOpenFacialRecognition(context),
      'recognize face': (context, fullCommand) => _handleOpenFacialRecognition(context),
      'explore features': (context, fullCommand) => _handleExploreFeatures(context),
      'clear chat': (context, fullCommand) => _handleClearChat(),
      'hello': (context, fullCommand) => _handleGreeting(),
      'hi': (context, fullCommand) => _handleGreeting(),
      'tell me about yourself': (context, fullCommand) => _handleSelfIntro(),
      'what is your name': (context, fullCommand) => _handleSelfIntro(),
      'who are you': (context, fullCommand) => _handleSelfIntro(),
      'what can you do': (context, fullCommand) => _handleCapabilities(),
      'how are you': (context, fullCommand) => _handleHowAreYou(),
      'what is the time': (context, fullCommand) => _handleTime(context),
      'what is today\'s date': (context, fullCommand) => _handleDate(),
      'are you online': (context, fullCommand) => _handleOnlineStatus(),
      'are you offline': (context, fullCommand) => _handleOnlineStatus(),
    };
  }

  /// Processes a user command, checking for duplicates and network status.
  Future<void> processUserCommand(String command, BuildContext? context) async {
    // Basic duplicate command prevention
    if (_isProcessingCommand &&
        _lastProcessedCommand == command.toLowerCase().trim() &&
        _lastProcessedTime != null &&
        DateTime.now().difference(_lastProcessedTime!) < const Duration(seconds: 2)) {
      _logger.w("Skipping duplicate command: $command");
      return;
    }

    _isProcessingCommand = true;
    _lastProcessedCommand = command.toLowerCase().trim();
    _lastProcessedTime = DateTime.now();

    onProcessingStatusChanged(true); // Notify ChatState that processing has started
    String response;

    // Check for explicit command match first
    final normalizedCommand = command.toLowerCase().trim();
    if (_commandHandlers.containsKey(normalizedCommand)) {
      _logger.i("Executing direct command: $normalizedCommand");
      await _commandHandlers[normalizedCommand]!(context, normalizedCommand);
      _isProcessingCommand = false;
      onProcessingStatusChanged(false); // Notify ChatState that processing has ended
      return; // Command handled, no need for AI
    }

    // If no direct command, try AI or offline fallback
    if (await _networkService.checkConnectionAndReturnStatus()) {
      _logger.i("Online: Sending command to Gemini API.");
      // Correct method name: getChatResponse
      response = await _geminiService.getChatResponse(_historyService.getHistory()
        ..add({"role": "user", "parts": command})); // Ensure user message is part of history sent to Gemini
    } else {
      _logger.i("Offline: Using local fallback for command.");
      response = _getOfflineResponse(command, context);
    }

    onHistoryUpdated([
      ..._historyService.getHistory(),
      {"role": "user", "content": command}, // Add user command to history *before* AI response
      {"role": "assistant", "content": response},
    ]);
    _historyService.addEntry(command); // Add user command to history service
    _historyService.addEntry(response); // Add AI response to history service
    await onSpeak(response);

    _isProcessingCommand = false;
    onProcessingStatusChanged(false); // Notify ChatState that processing has ended
  }

  // --- Command Handlers ---

  Future<void> _handleOpenChat(BuildContext? context) async {
    _logger.i("Command: Open Chat");
    await onSpeak("Opening chat.");
    if (context != null && context.mounted) { // Add mounted check
      onNavigate(AppRouter.aniwaChat, arguments: {'isForTabInitialization': true});
    }
  }

  Future<void> _handleOpenTextReader(BuildContext? context) async {
    _logger.i("Command: Open Text Reader");
    await onSpeak("Opening text reader. Please point your camera at the text.");
    if (context != null && context.mounted) { // Add mounted check
      onNavigate(AppRouter.textReader, arguments: {'autoCapture': false});
    }
  }

  Future<void> _handleOpenSceneDescription(BuildContext? context) async {
    _logger.i("Command: Open Scene Description");
    await onSpeak("Opening scene description. Please point your camera to the scene.");
    if (context != null && context.mounted) { // Add mounted check
      onNavigate(AppRouter.sceneDescription, arguments: {'autoDescribe': false});
    }
  }

  Future<void> _handleOpenNavigation(BuildContext? context) async {
    _logger.i("Command: Open Navigation");
    await onSpeak("Opening navigation. Please set your destination on the map.");
    if (context != null && context.mounted) { // Add mounted check
      onNavigate(AppRouter.navigation);
    }
  }

  Future<void> _handleOpenEmergency(BuildContext? context) async {
    _logger.i("Command: Open Emergency");
    await onSpeak("Opening emergency contacts.");
    if (context != null && context.mounted) { // Add mounted check
      onNavigate(AppRouter.emergency);
    }
  }

  Future<void> _handleOpenHistory(BuildContext? context) async {
    _logger.i("Command: Open History");
    await onSpeak("Opening history.");
    if (context != null && context.mounted) { // Add mounted check
      onNavigate(AppRouter.history);
    }
  }

  Future<void> _handleOpenObjectDetection(BuildContext? context) async {
    _logger.i("Command: Open Object Detection");
    await onSpeak("Opening object detection. Point your camera to detect objects.");
    if (context != null && context.mounted) { // Add mounted check
      onNavigate(AppRouter.objectDetector, arguments: {'autoStartLive': true});
    }
  }

  Future<void> _handleOpenFacialRecognition(BuildContext? context) async {
    _logger.i("Command: Open Facial Recognition");
    await onSpeak("Opening facial recognition. Looking for faces now.");
    if (context != null && context.mounted) { // Add mounted check
      onNavigate(AppRouter.facialRecognition, arguments: {'autoStartLive': true});
    }
  }

  Future<void> _handleExploreFeatures(BuildContext? context) async {
    _logger.i("Command: Explore Features");
    await onSpeak("Opening explore features page.");
    if (context != null && context.mounted) { // Add mounted check
      onNavigate(AppRouter.exploreFeatures);
    }
  }

  Future<void> _handleClearChat() async {
    _logger.i("Command: Clear Chat History");
    clearHistory();
    await onSpeak("Chat history cleared.");
  }

  Future<void> _handleGreeting() async {
    _logger.i("Command: Greeting");
    await onSpeak("Hello! How can I help you today?");
  }

  Future<void> _handleSelfIntro() async {
    _logger.i("Command: Self Introduction");
    await onSpeak("I am Assist Lens, your AI companion designed to help you with various tasks.");
  }

  Future<void> _handleCapabilities() async {
    _logger.i("Command: Capabilities");
    await onSpeak("I can help you read text, describe scenes, navigate, detect objects, recognize faces, and chat. What would you like to do?");
  }

  Future<void> _handleHowAreYou() async {
    _logger.i("Command: How are you");
    await onSpeak("I'm doing great, thank you for asking! How can I assist you?");
  }

  Future<void> _handleTime(BuildContext? context) async {
    _logger.i("Command: Time");
    if (context != null && context.mounted) { // Add mounted check
      final time = TimeOfDay.now().format(context);
      await onSpeak("The current time is $time.");
    } else {
      await onSpeak("I cannot tell the time without a valid context.");
    }
  }

  Future<void> _handleDate() async {
    _logger.i("Command: Date");
    final date = DateTime.now().toLocal().toString().split(' ')[0];
    await onSpeak("Today's date is $date.");
  }

  Future<void> _handleOnlineStatus() async {
    _logger.i("Command: Online Status Check");
    if (_networkService.isOnline) {
      await onSpeak("I am currently online and connected to the internet.");
    } else {
      await onSpeak("I am currently offline. Some features may be limited.");
    }
  }

  /// Provides a basic rule-based offline response for chat.
  String _getOfflineResponse(String command, BuildContext? context) {
    command = command.toLowerCase();
    if (command.contains('hello') || command.contains('hi')) {
      return 'Hello there! I am currently offline, but I can still help with some basic functions.';
    } else if (command.contains('time')) {
      if (context != null && context.mounted) { // Add mounted check
        return 'I am offline, but the current time is ${TimeOfDay.now().format(context).replaceAll(' ', '')}.';
      } else {
        return 'I am offline, but the current time is unavailable.';
      }
    } else if (command.contains('date')) {
      return 'I am offline, but today\'s date is ${DateTime.now().toLocal().toString().split(' ')[0]}.';
    } else if (command.contains('name')) {
      return 'I am Assist Lens, your helpful companion.';
    } else if (command.contains('online') || command.contains('offline')) {
      return _networkService.isOnline ? "I am online." : "I am offline.";
    } else {
      return 'I am currently offline and cannot connect to the internet to answer that. Is there anything else I can assist you with offline?';
    }
  }

  /// Clears the conversation history in HistoryService.
  void clearHistory() {
    _historyService.clearHistory();
    onHistoryUpdated([]); // Notify ChatState to clear its local history
  }

  void stopCurrentSpeech() {
    _speechService.stopSpeaking();
  }

  void dispose() {
    // No need to dispose anything specific here as dependencies are managed by Provider
  }
}
