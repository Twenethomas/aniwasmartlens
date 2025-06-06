// lib/features/aniwa_chat/state/chat_state.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:vibration/vibration.dart'; // For vibration feedback

import '../../../core/services/speech_service.dart';
import '../../../core/services/gemini_service.dart'; // Changed from azure_gpt_service.dart
import '../../../core/services/history_services.dart';
import '../../../core/services/network_service.dart';
import '../../../main.dart'; // For global logger and routeObserver
import '../../../core/routing/app_router.dart'; // For navigation

enum InputMode { voice, text }

class ChatState extends ChangeNotifier {
  final SpeechService _speechService;
  final GeminiService _geminiService; // Changed from AzureGptService
  final HistoryService _historyService;
  final NetworkService _networkService;
  final Logger _logger = logger; // Use global logger

  // Internal list for conversation history, now mutable
  List<Map<String, String>> _conversationHistory = [];

  // Getters for UI to consume
  List<Map<String, String>> get conversationHistory => List.unmodifiable(_conversationHistory); // Return unmodifiable view for external access
  String _recognizedText = '';
  String get recognizedText => _recognizedText;

  bool _isProcessingAI = false;
  bool get isProcessingAI => _isProcessingAI;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _isListening = false;
  bool get isListening => _isListening;

  String _aiSpeakingFullText = '';
  String get aiSpeakingFullText => _aiSpeakingFullText;

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  InputMode _currentInputMode = InputMode.voice;
  InputMode get currentInputMode => _currentInputMode;

  // Callback for navigation requests. Changed arguments type to Object?
  Function(String routeName, {Object? arguments})? onNavigateRequested;

  // This will be set by main.dart after ChatState is created
  // ignore: prefer_final_fields
  dynamic _chatService; // Keep as dynamic or define a ChatService interface
  set chatService(dynamic service) {
    _chatService = service;
  }

  ChatState(
    this._speechService,
    this._geminiService,
    this._historyService,
    this._networkService,
  ) {
    _subscribeToSpeechServiceStreams();
    _loadInitialHistory(); // Load history on init
  }

  // Ensure speechService and geminiService are correctly passed for their methods.
  // SpeechService.speakingStatusStream.listen is now handled by _subscribeToSpeechServiceStreams
  void _subscribeToSpeechServiceStreams() {
    _speechService.recognizedTextStream.listen((text) {
      if (_isListening) {
        _logger.d("STT: Live Recognized: $text");
        _recognizedText = text;
        notifyListeners();
      }
    });

    _speechService.finalRecognizedTextStream.listen((finalText) {
      _logger.i("ChatState: Final recognized text from STT: \"$finalText\"");
      if (finalText.isNotEmpty) {
        processUserMessage(finalText, null); // Pass null for context here, will be handled by chat page.
      }
      _isListening = false; // Stop listening after final text is received
      _recognizedText = ''; // Clear recognized text
      notifyListeners();
    });

    _speechService.listeningStatusStream.listen((status) {
      _logger.d("STT: Listening Status: $status");
      _isListening = status;
      notifyListeners();
    });

    _speechService.speakingStatusStream.listen((status) {
      _logger.d("TTS: Speaking Status: $status");
      _isSpeaking = status;
      notifyListeners();
    });

    _speechService.speakingTextStream.listen((text) {
      _logger.d("TTS: Speaking Text: $text");
      _aiSpeakingFullText = text;
      notifyListeners();
    });
  }

  /// Loads the initial conversation history from HistoryService.
  Future<void> _loadInitialHistory() async {
    // IMPORTANT: Create a mutable copy of the history
    _conversationHistory = List.from(_historyService.getHistory());
    _logger.i("ChatState: Loaded ${_conversationHistory.length} history entries.");
    notifyListeners();
  }

  /// Initial greeting logic.
  void initialGreeting(BuildContext context) async {
    _logger.i("ChatState: Providing initial greeting.");
    await addAssistantMessage("Hello there! I'm Aniwa, your AI companion. How can I assist you today?");
    await speak("Hello there! I'm Aniwa, your AI companion. How can I assist you today?");
  }

  /// Processes user's message, adds to history, and gets AI response.
  Future<void> processUserMessage(String message, BuildContext? context) async {
    if (message.trim().isEmpty) {
      _setErrorMessage('Message cannot be empty.');
      return;
    }

    _setErrorMessage(null);
    setIsProcessingAI(true); // Corrected: use public setter
    vibrate();

    await addUserMessage(message);

    if (!_networkService.isOnline) {
      await addAssistantMessage("I'm sorry, I cannot connect to the internet right now. Please check your connection.");
      await speak("I'm sorry, I cannot connect to the internet right now. Please check your connection.");
      setIsProcessingAI(false); // Corrected: use public setter
      return;
    }

    try {
      final chatHistory = _conversationHistory.map((e) {
        return {'role': e['role']!, 'parts': [{'text': e['content']!}]};
      }).toList();

      final aiResponse = await _geminiService.getChatResponse(chatHistory);

      if (aiResponse.toLowerCase().contains("navig")) {
        _logger.i("ChatState: Detected navigation request. Navigating...");
        await addAssistantMessage("Navigating to navigation screen.");
        await speak("Navigating to navigation screen.");
        navigateTo(AppRouter.navigation);
      } else {
        await addAssistantMessage(aiResponse);
        await speak(aiResponse);
      }
    } catch (e) {
      _logger.e("Error getting AI response: $e");
      _setErrorMessage('Failed to get AI response. Please try again.');
      await addAssistantMessage("I'm sorry, I encountered an error. Please try asking again.");
      await speak("I'm sorry, I encountered an error. Please try asking again.");
    } finally {
      setIsProcessingAI(false); // Corrected: use public setter
    }
  }

  /// Sends a message, adding it to history and triggering AI processing.
  Future<void> sendMessage(String message, BuildContext? context) async {
    _logger.i("ChatState: Sending message: $message");
    // Directly call processUserMessage, which handles adding to history
    await processUserMessage(message, context);
  }

  /// Adds a message to the conversation history and persists it.
  Future<void> addEntry(String content, {String role = 'assistant'}) async {
    // IMPORTANT: Add to the mutable internal list
    _conversationHistory.add({"role": role, "content": content});
    await _historyService.addEntry(content, role: role); // Persist via HistoryService
    notifyListeners();
  }

  /// Adds a user message to the conversation history and persists it.
  Future<void> addUserMessage(String content) async {
    await addEntry(content, role: 'user');
  }

  /// Adds an assistant message to the conversation history and persists it.
  Future<void> addAssistantMessage(String content) async {
    await addEntry(content, role: 'assistant');
  }

  /// Clears the entire chat history from memory and persistence.
  void clearChatHistory() async {
    _logger.i("ChatState: Clearing chat history.");
    _conversationHistory = []; // Reset internal list to empty
    await _historyService.clearHistory();
    _setErrorMessage(null); // Clear any existing errors
    notifyListeners();
    // Provide initial greeting after clearing
    // This will be called via didChangeDependencies on the page, or explicitly if needed
  }

  // --- Speech Control ---
  void startVoiceInput() async {
    _setErrorMessage(null);
    _isListening = true;
    notifyListeners();
    try {
      await _speechService.startListening(continuous: true);
      _logger.i("Started voice input (continuous: true)");
    } catch (e) {
      _setErrorMessage('Failed to start listening: $e');
      _logger.e("Error starting voice input: $e");
      _isListening = false;
      notifyListeners();
    }
  }

  void stopVoiceInput() {
    _logger.i("Stopping voice input.");
    _speechService.stopListening();
    _isListening = false;
    _recognizedText = '';
    notifyListeners();
  }

  Future<void> speak(String text) async {
    _logger.i("ChatState: Speaking: $text");
    await _speechService.speak(text);
  }

  void stopSpeaking() {
    _logger.i("ChatState: Stopping speech.");
    _speechService.stopSpeaking();
  }

  // --- Utility Methods ---
  void _setErrorMessage(String? message) {
    if (_errorMessage != message) {
      _errorMessage = message;
      notifyListeners();
    }
  }

  // Public setter for isProcessingAI
  void setIsProcessingAI(bool status) { // No underscore here
    if (_isProcessingAI != status) {
      _isProcessingAI = status;
      notifyListeners();
    }
  }

  void updateHistory(List<Map<String, String>> newHistory) {
    // IMPORTANT: Create a mutable copy when updating from external sources
    _conversationHistory = List.from(newHistory);
    notifyListeners();
  }

  void vibrate() {
    Vibration.vibrate(duration: 50);
  }

  void setInputMode(InputMode mode) {
    if (_currentInputMode != mode) {
      _currentInputMode = mode;
      // If switching to text mode, stop listening if active
      if (mode == InputMode.text && _isListening) {
        stopVoiceInput();
      }
      notifyListeners();
    }
  }

  // Changed arguments type to Object? to match the expected signature in ChatService
  void navigateTo(String routeName, {Object? arguments}) {
    if (onNavigateRequested != null) {
      _logger.i("ChatState: Navigating to $routeName with arguments: $arguments");
      // Safely cast arguments back to Map<String, dynamic>? for the callback, if needed
      onNavigateRequested!(routeName, arguments: arguments as Map<String, dynamic>?);
    } else {
      _logger.w("ChatState: onNavigateRequested callback not set. Cannot navigate.");
    }
  }

  @override
  void dispose() {
    _logger.i("ChatState disposed.");
    _speechService.stopListening();
    _speechService.stopSpeaking();
    super.dispose();
  }
}
