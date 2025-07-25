// lib/features/aniwa_chat/state/chat_state.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:vibration/vibration.dart';

import '../../../core/services/speech_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/history_services.dart';
import '../../../core/services/network_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../main.dart';

enum InputMode { voice, text }

enum ChatStatus { idle, listening, processing, speaking, error }

class ChatState extends ChangeNotifier {
  final SpeechService _speechService;
  final GeminiService _geminiService;
  final HistoryService _historyService;
  final NetworkService _networkService;
  final Logger _logger = logger;

  // Chat Service for command processing
  late ChatService chatService;

  // Current screen route for context awareness
  String _currentScreenRoute = 'unknown';

  // Method to update current screen route from main.dart
  void updateCurrentRoute(String routeName) {
    if (_currentScreenRoute != routeName) {
      _logger.i('ChatState: Current screen route updated to $routeName');
      _currentScreenRoute = routeName;
      // Update ChatService with current screen route
      chatService.updateCurrentRoute(routeName);
    }
  }

  // Internal conversation history
  List<Map<String, String>> _conversationHistory = [];

  // UI State
  String _recognizedText = '';
  String _aiSpeakingFullText = '';
  String? _errorMessage;

  // Processing States
  bool _isProcessingAI = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isWakeWordListening = false;
  String _detectedWakeWord = '';

  // Blind mode state
  bool _isBlindModeEnabled = false;

  // Input Mode
  InputMode _currentInputMode = InputMode.voice;
  ChatStatus _chatStatus = ChatStatus.idle;

  // Timers and Debouncing
  Timer? _commandDebounceTimer;
  Timer? _errorClearTimer;
  Timer? _followUpTimer; // Added: Timer for follow-up listening
  bool _isInFollowUpListening =
      false; // New flag to track follow-up listening state
  String? _lastCommand;
  DateTime? _lastCommandTime;

  // Stream subscriptions for cleanup
  late List<StreamSubscription> _subscriptions;

  // Enhanced state tracking
  bool _isInitialized = false;
  int _consecutiveErrors = 0;
  static const int _maxConsecutiveErrors = 5;
  static const Duration _followUpListeningDuration = Duration(
    seconds: 15,
  ); // Added: Duration for follow-up listening

  // Callback for UI to trigger scroll
  Function()? _scrollToBottomCallback;

  // New field to track if the ChatPage is currently active/visible
  bool _isChatPageActive = false;

  // New field to hold the current partial assistant message during streaming
  String _currentStreamingAssistantResponse = '';

  // Getters
  List<Map<String, String>> get conversationHistory =>
      List.unmodifiable(_conversationHistory);
  String get recognizedText => _recognizedText;
  bool get isProcessingAI => _isProcessingAI;
  String? get errorMessage => _errorMessage;
  bool get isListening => _isListening;
  String get aiSpeakingFullText => _aiSpeakingFullText;
  bool get isSpeaking => _isSpeaking;
  InputMode get currentInputMode => _currentInputMode;
  bool get isWakeWordListening => _isWakeWordListening;
  String get detectedWakeWord => _detectedWakeWord;
  ChatStatus get chatStatus => _chatStatus;
  bool get isActive => _chatStatus != ChatStatus.idle;
  bool get isInitialized => _isInitialized;
  bool get hasErrors => _consecutiveErrors > 0;

  bool get isBlindModeEnabled => _isBlindModeEnabled;

  // Expose the current streaming response
  String get currentStreamingAssistantResponse =>
      _currentStreamingAssistantResponse;
  bool get isStreamingAssistantResponse =>
      _currentStreamingAssistantResponse.isNotEmpty;

  // Navigation callback - now explicitly set from main.dart
  Function(String routeName, {Object? arguments})? onNavigateRequested;

  ChatState(
    this._speechService,
    this._geminiService,
    this._historyService,
    this._networkService,
  ) {
    _subscriptions = [];
  }

  // Method to update the active status of the chat page
  void setChatPageActive(bool isActive) {
    if (_isChatPageActive != isActive) {
      _logger.i('ChatState: Chat page active status changed to: $isActive');
      _isChatPageActive = isActive;
    }
  }

  void enableBlindMode() {
    _logger.i("ChatState: Enabling blind mode");
    _isBlindModeEnabled = true;
    // In blind mode, force voice input mode and start voice input
    setInputMode(InputMode.voice);
    startVoiceInput();
    notifyListeners();
  }

  void disableBlindMode() {
    _logger.i("ChatState: Disabling blind mode");
    _isBlindModeEnabled = false;
    // Optionally stop voice input or revert to default input mode
    stopVoiceInput();
    notifyListeners();
  }

  /// Sets a callback function to trigger scrolling to the bottom of the chat UI.
  /// This allows the ChatState to directly request a scroll after data updates.
  void setScrollToBottomCallback(Function() callback) {
    _scrollToBottomCallback = callback;
    _logger.d("ChatState: Scroll to bottom callback set.");
  }

  // Handle incoming partial assistant message chunks
  Future<void> handlePartialAssistantMessage(String partialMessage) async {
    _logger.d(
      "ChatState: Received partial assistant message: '$partialMessage'",
    );

    if (_currentStreamingAssistantResponse.isEmpty &&
        partialMessage.isNotEmpty) {
      // This is the first chunk, so add a new (initially empty) assistant message to history
      _conversationHistory.add({'role': 'assistant', 'content': ''});
      _logger.d("ChatState: Added new empty assistant message for streaming.");
    }

    // Instead of appending, replace the current streaming response to simulate typing
    _currentStreamingAssistantResponse = partialMessage;

    // Update the last assistant message content with the current streaming response
    if (_conversationHistory.isNotEmpty &&
        _conversationHistory.last['role'] == 'assistant') {
      _conversationHistory[_conversationHistory.length - 1]['content'] =
          _currentStreamingAssistantResponse;
    }

    // Only notify and scroll if the chat page is active
    if (_isChatPageActive) {
      notifyListeners();
      _scrollToBottomCallback?.call();
    }
  }

  // Call this to finalize the assistant message after streaming completes
  Future<void> finalizeAssistantMessage(String fullMessage) async {
    _logger.i("ChatState: Finalizing assistant message: '$fullMessage'");

    if (_conversationHistory.isNotEmpty &&
        _conversationHistory.last['role'] == 'assistant') {
      _conversationHistory[_conversationHistory.length - 1]['content'] =
          fullMessage;
      _logger.d("ChatState: Updated last assistant message with full content.");
    } else {
      // Fallback in case of unexpected state (e.g., streaming started without initial empty message)
      _conversationHistory.add({'role': 'assistant', 'content': fullMessage});
      _logger.w(
        "ChatState: Unexpected state: Added full assistant message directly. History may be out of sync.",
      );
    }

    await _historyService.addEntry(fullMessage, role: 'assistant');
    _currentStreamingAssistantResponse = ''; // Clear streaming buffer
    _logger.d("ChatState: Streaming buffer cleared.");

    // Only notify and scroll if the chat page is active
    if (_isChatPageActive) {
      notifyListeners();
      _scrollToBottomCallback?.call();
    }
  }

  // Enhanced initialization
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _logger.i("ChatState: Initializing ChatState...");

      await _subscribeToSpeechServiceStreams();
      await _loadInitialHistory();

      // Ensure wake word listening is attempted or fallback is handled after init
      await _ensureWakeWordListening();

      _isInitialized = true;
      _consecutiveErrors = 0;
      _logger.i("ChatState: Initialized successfully");
    } catch (e) {
      _logger.e("ChatState: Failed to initialize ChatState: $e");
      _handleError("Failed to initialize chat system: $e");
      rethrow;
    }
  }

  Future<void> _subscribeToSpeechServiceStreams() async {
    // Clear existing subscriptions
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    try {
      // Live recognized text stream
      _subscriptions.add(
        _speechService.recognizedTextStream.listen(
          _handleRecognizedText,
          onError: (error) => _handleStreamError("recognized text", error),
        ),
      );

      // Final recognized text stream
      _subscriptions.add(
        _speechService.finalRecognizedTextStream.listen(
          _handleFinalRecognizedText,
          onError:
              (error) => _handleStreamError("final recognized text", error),
        ),
      );

      // Listening status stream
      _subscriptions.add(
        _speechService.listeningStatusStream.listen(
          _handleListeningStatusChanged,
          onError: (error) => _handleStreamError("listening status", error),
        ),
      );

      // Speaking status stream
      _subscriptions.add(
        _speechService.speakingStatusStream.listen(
          _handleSpeakingStatusChanged,
          onError: (error) => _handleStreamError("speaking status", error),
        ),
      );

      // Speaking text stream
      _subscriptions.add(
        _speechService.speakingTextStream.listen(
          _handleSpeakingText,
          onError: (error) => _handleStreamError("speaking text", error),
        ),
      );

      // Wake word listening stream
      _subscriptions.add(
        _speechService.wakeWordListeningStream.listen(
          _handleWakeWordListeningChanged,
          onError: (error) => _handleStreamError("wake word listening", error),
        ),
      );

      // Wake word detected stream
      _subscriptions.add(
        _speechService.wakeWordDetectedStream.listen(
          _handleWakeWordDetected,
          onError: (error) => _handleStreamError("wake word detected", error),
        ),
      );

      _logger.i(
        "ChatState: Successfully subscribed to ${_subscriptions.length} speech service streams",
      );
    } catch (e) {
      _logger.e("ChatState: Failed to subscribe to speech service streams: $e");
      rethrow;
    }
  }

  // Enhanced error handling
  void _handleStreamError(String streamName, dynamic error) {
    _consecutiveErrors++;
    _logger.e(
      "ChatState: Error in $streamName stream: $error (consecutive errors: $_consecutiveErrors)",
    );

    if (_consecutiveErrors >= _maxConsecutiveErrors) {
      _handleError("Multiple stream errors detected. Please restart the app.");
    } else {
      _setErrorMessage(
        "Temporary issue with $streamName. Retrying...",
        autoClearing: true,
      );
    }
  }

  void _handleError(String message) {
    _setErrorMessage(message);
    _updateChatStatus(ChatStatus.error);
  }

  @override
  void notifyListeners() {
    _logger.d(
      "ChatState: notifyListeners called. Status: $_chatStatus, History Length: ${_conversationHistory.length}",
    );
    super.notifyListeners();
  }

  // Stream Handlers (Enhanced)
  void _handleRecognizedText(String text) {
    if (_isListening && text.isNotEmpty) {
      _logger.d("ChatState: Live recognized text: $text");
      _recognizedText = text;
      _updateChatStatus(ChatStatus.listening);
      _resetErrorCount(); // Reset error count on successful operation
      // Only notify if chat page is active
      if (_isChatPageActive) {
        notifyListeners();
      }
    }
  }

  Future<void> _handleFinalRecognizedText(String finalText) async {
    _logger.i("ChatState: Raw final recognized text: \"$finalText\"");

    // Always clear recognized text immediately.
    _recognizedText = '';
    // Also, make sure the UI recognized text is cleared.
    if (_isChatPageActive) {
      notifyListeners();
    }

    // Only process if the final text is not empty and passes debouncing.
    if (finalText.isNotEmpty && _shouldProcessCommand(finalText)) {
      _updateChatStatus(ChatStatus.processing);

      // Update last command only if it will be processed
      _lastCommand = finalText.toLowerCase().trim();
      _lastCommandTime = DateTime.now();

      // Add user message to UI immediately
      await addUserMessage(finalText);

      // Introduce a small microtask delay to allow UI to update and event loop to clear
      await Future.microtask(() {});

      _logger.i("ChatState: Processing user command: \"$finalText\"");
      // Pass the current context to chatService.processUserCommand
      // This context is necessary for TimeOfDay.now().format in ChatService
      await chatService.processUserCommand(
        finalText,
        navigatorKey.currentContext,
      );
      _resetErrorCount();
    } else if (finalText.isEmpty && _isListening) {
      // If STT stopped with no recognized text, and we were still listening,
      // explicitly stop listening and return to wake word if applicable.
      _logger.i(
        "ChatState: STT stopped with no recognized text. Returning to idle/wake word.",
      );
      await _speechService.stopListening(); // Ensure STT is fully stopped
      _isListening = false; // Update internal state
      _updateChatStatus(ChatStatus.idle); // Set status to idle
      await _ensureWakeWordListening(); // Re-enable wake word
    } else if (finalText.isEmpty) {
      _logger.i(
        "ChatState: Received empty final text, but not actively listening or already processed.",
      );
    }
  }

  // New method to handle interruption: stop speaking and restart listening
  Future<void> handleInterruption() async {
    if (_isSpeaking) {
      await stopSpeaking();
      _logger.i("ChatState: Interrupted AI speech due to user input.");
    }
    if (!_isListening) {
      await startVoiceInput();
      _logger.i("ChatState: Restarted listening after interruption.");
    }
  }

  Future<void> _handleListeningStatusChanged(bool status) async {
    _logger.d("ChatState: Listening status changed: $status");
    _isListening = status;

    if (status) {
      _updateChatStatus(ChatStatus.listening);
      // Stop AI speech if user starts speaking (interruption)
      if (_isSpeaking) {
        await stopSpeaking(); // Await stopping speech
        _logger.i("ChatState: User interruption detected - stopping AI speech");
      }
      // Only cancel follow-up timer if not in follow-up listening mode
      if (!_isInFollowUpListening) {
        _followUpTimer
            ?.cancel(); // Cancel follow-up timer if listening starts manually
      }
    } else if (_chatStatus == ChatStatus.listening) {
      // Only set to idle if not currently speaking or processing, and not during follow-up
      if (!_isSpeaking && !_isProcessingAI && !_isInFollowUpListening) {
        _updateChatStatus(ChatStatus.idle);
      }
    }

    _resetErrorCount();
    // Only notify if chat page is active
    if (_isChatPageActive) {
      notifyListeners();
    }
  }

  Future<void> _handleSpeakingStatusChanged(bool status) async {
    _logger.d("ChatState: Speaking status changed: $status");
    _isSpeaking = status;

    if (status) {
      _updateChatStatus(ChatStatus.speaking);
      _aiSpeakingFullText = ''; // Clear previous text when speaking starts
    } else if (_chatStatus == ChatStatus.speaking) {
      _aiSpeakingFullText = ''; // Clear text when speaking finishes

      _logger.i(
        "ChatState: TTS Finished speaking. Initiating follow-up listening process.",
      );

      // Ensure current listening session (if any from final text processing) is stopped cleanly
      await _speechService.stopListening();
      _isListening = false;
      _recognizedText = ''; // Clear any residual recognized text

      _updateChatStatus(ChatStatus.listening); // Set status to listening

      _isWakeWordListening = false; // Ensure wake word is off

      // Cancel any existing follow-up timer to avoid premature timeout
      _followUpTimer?.cancel();

      _isInFollowUpListening =
          true; // Set flag to indicate follow-up listening active

      // Add a short delay before starting STT for follow-up, to allow audio buffer to clear
      await Future.delayed(const Duration(milliseconds: 300));

      // Start STT for follow-up questions for a limited duration
      try {
        await _speechService.startExtendedListening(
          maxDuration: _followUpListeningDuration,
        );
      } catch (e) {
        _logger.w("ChatState: Failed to start follow-up listening: $e");
        _isInFollowUpListening = false;
        await _handleFollowUpTimeout();
        return;
      }

      // Start a timer to go back to wake word listening after follow-up duration
      _followUpTimer = Timer(_followUpListeningDuration, () async {
        _logger.i(
          "ChatState: Follow-up listening timeout. Returning to wake word.",
        );
        _isInFollowUpListening = false;
        await _handleFollowUpTimeout();
      });
    }

    _resetErrorCount();
    // Only notify if chat page is active
    if (_isChatPageActive) {
      notifyListeners();
    }
  }

  // Added: New method to handle follow-up listening timeout
  Future<void> _handleFollowUpTimeout() async {
    _followUpTimer?.cancel(); // Ensure timer is canceled
    _speechService.stopListening(); // Stop current STT listening
    _isListening = false; // Update internal state
    _recognizedText = ''; // Clear any interim recognized text
    _logger.i("ChatState: Follow-up listening session ended.");
    await _ensureWakeWordListening(); // Re-enable wake word listening
    _updateChatStatus(ChatStatus.idle); // Set chat status to idle
    // Only notify if chat page is active
    if (_isChatPageActive) {
      notifyListeners();
    }
  }

  void _handleSpeakingText(String text) {
    _aiSpeakingFullText = text;
    // Only notify if chat page is active
    if (_isChatPageActive) {
      notifyListeners();
    }
  }

  void _handleWakeWordListeningChanged(bool status) {
    _isWakeWordListening = status;
    _logger.d("ChatState: Wake word listening status: $status");
    if (status) _resetErrorCount();
    // Only notify if chat page is active
    if (_isChatPageActive) {
      notifyListeners();
    }
  }

  void _handleWakeWordDetected(String wakeWord) {
    if (wakeWord.isNotEmpty) {
      _logger.i("ChatState: Wake word detected: $wakeWord");
      _detectedWakeWord = wakeWord;
      // CRITICAL FIX: Ensure _handleWakeWordActivation is awaited
      _handleWakeWordActivation(wakeWord);
      _resetErrorCount();
      // Only notify if chat page is active
      if (_isChatPageActive) {
        notifyListeners();
      }
    }
  }

  void _resetErrorCount() {
    if (_consecutiveErrors > 0) {
      _consecutiveErrors = 0;
      _logger.d("ChatState: Error count reset after successful operation");
    }
  }

  // Chat Service Callbacks
  void _handleProcessingStatusChanged(bool isProcessing) {
    setIsProcessingAI(isProcessing);
    if (isProcessing) {
      _updateChatStatus(ChatStatus.processing);
      _currentStreamingAssistantResponse =
          ''; // Clear streaming buffer when processing starts
      _logger.d("ChatState: Processing started, streaming buffer cleared.");
    } else if (_chatStatus == ChatStatus.processing) {
      _updateChatStatus(ChatStatus.idle);
    }
  }

  Future<void> _handleSpeak(String text) async {
    await speak(text);
  }

  void _handleVibrate() {
    vibrate();
  }

  // This method now calls the actual navigation logic via onNavigateRequested
  void navigateTo(String routeName, {Object? arguments}) {
    if (onNavigateRequested != null) {
      _logger.i(
        "ChatState: Navigating to $routeName with arguments: $arguments",
      );
      // Cast arguments to Map<String, dynamic> if it's not null, as expected by the callback
      onNavigateRequested!(
        routeName,
        arguments: arguments as Map<String, dynamic>?,
      );
    } else {
      _logger.w(
        "ChatState: Navigation callback not set - cannot navigate to $routeName",
      );
    }
  }

  // Core Methods
  Future<void> _loadInitialHistory() async {
    try {
      _conversationHistory = List.from(_historyService.getHistory());
      _logger.i(
        "ChatState: Loaded ${_conversationHistory.length} history entries",
      );
      // Always notify, let the UI decide to rebuild
      notifyListeners();
      // Only trigger scroll if the chat page is currently active
      if (_isChatPageActive) {
        _scrollToBottomCallback?.call();
      }
    } catch (e) {
      _logger.e("ChatState: Failed to load history: $e");
      _handleError("Failed to load conversation history");
    }
  }

  Future<void> initialGreeting(BuildContext? context) async {
    if (!_isInitialized) {
      _logger.w(
        "ChatState: Not initialized during greeting, initializing now.",
      );
      await initialize();
    }
    _logger.i("ChatState: Providing initial greeting");

    String greeting;
    if (_speechService.porcupineInitializationFailed) {
      greeting = """
      <speak>
          Hello there!
          I'm Aniwa, your AI companion. <break time="500ms"/>
          I couldn't enable voice activation at the moment, but you can always type your commands.
          How can I assist you today?
      </speak>
      """;

      "Hello there! I'm Aniwa, your AI companion. I couldn't enable voice activation at the moment, but you can always type your commands. How can I assist you today?";
      _currentInputMode = InputMode.text; // Explicitly set to text mode
      _logger.i(
        "ChatState: Wake word failed, defaulting to text input for greeting.",
      );
    } else {
      greeting =
          "Hello there! I'm Aniwa, your AI companion. Say 'Hey Teddy' to activate voice commands. How can I assist you today?";
      _currentInputMode =
          InputMode.voice; // Default to voice mode if wake word is expected
      _logger.i(
        "ChatState: Wake word available, defaulting to voice input for greeting.",
      );
    }

    // Directly add assistant greeting message to ChatState
    await addAssistantMessage(greeting);
    await speak(greeting);
    // After greeting, ensure wake word listening is active (or handle fallback).
    // The _handleSpeakingStatusChanged will now initiate follow-up listening,
    // and after that times out, it will ensure wake word listening.
  }

  bool _shouldProcessCommand(String command) {
    final trimmedCommand = command.toLowerCase().trim();
    final now = DateTime.now();
    // Skip empty commands
    if (trimmedCommand.isEmpty) {
      _logger.d("ChatState: Skipping empty command.");
      return false;
    }
    // Skip duplicate commands within 2 seconds
    if (_lastCommand == trimmedCommand &&
        _lastCommandTime != null &&
        now.difference(_lastCommandTime!) < const Duration(seconds: 2)) {
      _logger.w("ChatState: Skipping duplicate command: $trimmedCommand");
      return false;
    }
    // _lastCommand and _lastCommandTime will be updated AFTER this check if it passes.
    return true;
  }

  Future<void> _processUserCommand(String command) async {
    try {
      _setErrorMessage(null);
      // Cancel any existing debounce timer
      _commandDebounceTimer?.cancel();
      // Debounce rapid commands
      _commandDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
        _logger.i(
          "ChatState: Processing user command after debounce: $command",
        );
        // The ChatService will now call onAddAssistantMessage when it has a response
        // Pass the current context to chatService.processUserCommand
        // This context is necessary for TimeOfDay.now().format in ChatService
        await chatService.processUserCommand(
          command,
          navigatorKey.currentContext,
        );
      });
    } catch (e) {
      _logger.e("ChatState: Error processing user command: $e");
      _handleError("Failed to process command: $e");
    }
  }

  Future<void> sendMessage(String message, BuildContext? context) async {
    if (message.trim().isEmpty) {
      _setErrorMessage('Message cannot be empty');
      _logger.w("ChatState: Attempted to send empty message.");
      return;
    }

    _logger.i("ChatState: Sending message: $message");
    // Add user message to ChatState when sent from UI
    await addUserMessage(message);
    await _processUserCommand(message);
  }

  // This method is for adding complete messages to history (user messages, or AI after streaming)
  Future<void> addEntry(String content, {String role = 'assistant'}) async {
    try {
      _logger.i(
        "ChatState: addEntry: BEFORE adding. History length: ${_conversationHistory.length}, Content: '$content', Role: '$role'",
      );
      _conversationHistory.add({
        "role": role,
        "content": content,
      }); // <--- This is the line that adds to the internal list
      _logger.i(
        "ChatState: addEntry: AFTER adding to local list. New history length: ${_conversationHistory.length}",
      );

      await _historyService.addEntry(content, role: role);
      _logger.i(
        "ChatState: addEntry: AFTER saving to history service. Current history length: ${_conversationHistory.length}",
      );

      notifyListeners(); // Always notify, let the UI decide to rebuild

      // Only trigger scroll to bottom after new message is added and notified if chat page is active
      if (_isChatPageActive && _scrollToBottomCallback != null) {
        _logger.i(
          "ChatState: addEntry: Triggering scroll to bottom callback (chat page active).",
        );
        _scrollToBottomCallback!();
      } else if (!_isChatPageActive) {
        _logger.i(
          "ChatState: addEntry: Skipping scroll, chat page not active.",
        );
      } else {
        _logger.w(
          "ChatState: addEntry: _scrollToBottomCallback is null. Cannot scroll.",
        );
      }
    } catch (e) {
      _logger.e("ChatState: Failed to add entry: $e");
      _handleError("Failed to save message");
    }
  }

  Future<void> addUserMessage(String content) async {
    _logger.i("ChatState: Calling addUserMessage for: '$content'");
    await addEntry(content, role: 'user');
  }

  String _extractTextFromSSML(String ssmlText) {
    return ssmlText
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> addAssistantMessage(String content) async {
    _logger.i("ChatState: Calling addAssistantMessage for: '$content'");
    final plainText = _extractTextFromSSML(content);
    await addEntry(plainText, role: 'assistant');
  }

  Future<void> clearChatHistory() async {
    try {
      _logger.i("ChatState: Clearing chat history");
      _conversationHistory.clear();
      await _historyService.clearHistory();
      _setErrorMessage(null);
      _updateChatStatus(ChatStatus.idle);
      // Always notify, let the UI decide to rebuild
      notifyListeners();
      // Only trigger scroll if the chat page is currently active
      if (_isChatPageActive) {
        _scrollToBottomCallback?.call(); // Scroll to top (empty state)
      }
    } catch (e) {
      _logger.e("ChatState: Failed to clear history: $e");
      _handleError("Failed to clear history");
    }
  }

  // Enhanced Speech Control
  Future<void> startVoiceInput() async {
    if (!_isInitialized) {
      _logger.w(
        "ChatState: Not initialized for voice input, initializing now...",
      );
      await initialize();
    }

    try {
      _setErrorMessage(null);
      _logger.i("ChatState: Starting voice input");
      // Stop wake word listening if it's active
      if (_isWakeWordListening) {
        await stopWakeWordListening();
      }
      // Use the enhanced listening from the improved speech service
      // _speechService.startListening() now handles microphone acquisition delays
      await _speechService.startExtendedListening(
        maxDuration: const Duration(minutes: 3),
      );
    } catch (e) {
      _logger.e("ChatState: Failed to start voice input: $e");
      _handleError('Failed to start listening: $e');
    }
  }

  Future<void> stopVoiceInput() async {
    _logger.i("ChatState: Stopping voice input");
    await _speechService.stopListening();
    _recognizedText = '';
    _followUpTimer?.cancel(); // Added: Cancel follow-up timer on manual stop
    _updateChatStatus(ChatStatus.idle);
    await _ensureWakeWordListening(); // Re-enable wake word listening after manual stop
  }

  Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      _logger.i("ChatState: Speaking: $text");
      await _speechService.speak(text);
    }
  }

  Future<void> stopSpeaking() async {
    _logger.i("ChatState: Stopping speech");
    await _speechService.stopSpeaking();
  }

  // Enhanced Wake Word Control
  Future<void> startWakeWordListening() async {
    if (!_isInitialized) {
      _logger.w(
        "ChatState: Not initialized for wake word, initializing now...",
      );
      await initialize();
    }

    try {
      _logger.i("ChatState: Starting wake word listening");
      _setErrorMessage(null);
      await _speechService.startWakeWordListening();
    } catch (e) {
      _logger.e("ChatState: Failed to start wake word listening: $e");
      _handleError('Failed to start wake word listening: $e');
    }
  }

  Future<void> stopWakeWordListening() async {
    _logger.i("ChatState: Stopping wake word listening");
    await _speechService.stopWakeWordListening();
  }

  Future<void> _ensureWakeWordListening() async {
    // If wake word initialization has failed permanently, force text input mode
    if (_speechService.porcupineInitializationFailed) {
      _currentInputMode = InputMode.text;
      _isWakeWordListening = false;
      _logger.w(
        "ChatState: Wake word permanently failed. Forcing InputMode.text.",
      );
      _setErrorMessage(
        "Voice activation (wake word) is unavailable. Please use text input.",
        autoClearing: false,
      );
      // Only notify if chat page is active
      if (_isChatPageActive) {
        notifyListeners();
      }
      return;
    }

    // If currently in voice mode and not already listening for wake word, try to start it
    if (_currentInputMode == InputMode.voice &&
        !_speechService.isWakeWordListening &&
        !_speechService.isPorcupineInitializing) {
      _logger.i("ChatState: Ensuring wake word listening is active.");
      await startWakeWordListening(); // Re-call startWakeWordListening
      _isWakeWordListening =
          _speechService.isWakeWordListening; // Update internal state
      if (!_isWakeWordListening) {
        // If it failed to start even after attempt, set to text mode
        _currentInputMode = InputMode.text;
        _logger.e(
          "ChatState: Failed to start wake word listening after attempt. Falling back to text input.",
        );
        _setErrorMessage(
          "Voice activation could not be started. Please use text input.",
          autoClearing: false,
        );
      }
    } else if (_currentInputMode == InputMode.text) {
      // If in text mode, ensure wake word is off
      if (_speechService.isWakeWordListening) {
        await _speechService.stopWakeWordListening();
        _isWakeWordListening = false;
        _logger.i(
          "ChatState: InputMode is text, stopping wake word listening.",
        );
      }
    }
    // Only notify if chat page is active
    if (_isChatPageActive) {
      notifyListeners();
    }
  }

  void _handleWakeWordActivation(String wakeWord) async {
    // Make it async
    _logger.i("ChatState: Processing wake word activation: $wakeWord");

    // Provide haptic feedback
    vibrate();

    // Stop AI speech if active
    if (_isSpeaking) {
      await stopSpeaking();
      _logger.i("ChatState: Stopped AI speech due to wake word");
    }

    // Ensure voice mode
    if (_currentInputMode != InputMode.voice) {
      setInputMode(InputMode.voice);
    }

    // Clear errors
    _setErrorMessage(null);

    _logger.i("ChatState: Ready for voice input after wake word detection");

    // Introduce a short delay before starting STT to allow for clean transition
    await Future.delayed(const Duration(milliseconds: 300));

    // CRITICAL FIX: Explicitly start STT listening here after wake word is detected
    // This will now use the startListening method from SpeechService,
    // which includes the microphone release delay and clean STT restart logic.
    // Use startExtendedListening to allow for more natural pauses after wake word.
    await _speechService.startExtendedListening(
      maxDuration:
          _followUpListeningDuration, // Use the existing follow-up duration
      manualStart: false,
    );

    _isListening = true; // Set listening status
    _updateChatStatus(ChatStatus.listening);
    // Only notify if chat page is active
    if (_isChatPageActive) {
      notifyListeners();
    }

    // Start a timer to go back to wake word listening after follow-up duration
    _followUpTimer?.cancel(); // Ensure any previous timer is canceled
    _followUpTimer = Timer(_followUpListeningDuration, () async {
      _logger.i(
        "ChatState: Follow-up listening timeout after wake word. Returning to wake word.",
      );
      await _handleFollowUpTimeout();
    });
  }

  void clearDetectedWakeWord() {
    _detectedWakeWord = '';
    _speechService.clearRecognizedText();
    // Only notify if chat page is active
    if (_isChatPageActive) {
      notifyListeners();
    }
  }

  // Input Mode Control
  void setInputMode(InputMode mode) {
    if (_currentInputMode != mode) {
      _logger.i("ChatState: Switching input mode to: $mode");
      _currentInputMode = mode;

      if (mode == InputMode.text) {
        // Stop voice-related services
        if (_isListening) stopVoiceInput();
        if (_isWakeWordListening) stopWakeWordListening();
      } else {
        // Start voice services
        _ensureWakeWordListening();
      }

      _followUpTimer
          ?.cancel(); // Added: Cancel follow-up timer if input mode changes
      // Only notify if chat page is active
      if (_isChatPageActive) {
        notifyListeners();
      }
    }
  }

  // Enhanced Utility Methods
  void _updateChatStatus(ChatStatus status) {
    if (_chatStatus != status) {
      _chatStatus = status;
      _logger.d("ChatState: Chat status changed to: $status");
      // Only notify if chat page is active
      if (_isChatPageActive) {
        notifyListeners();
      }
    }
  }

  void _setErrorMessage(String? message, {bool autoClearing = false}) {
    if (_errorMessage != message) {
      _errorMessage = message;
      if (message != null) {
        _updateChatStatus(ChatStatus.error);
        _logger.w("ChatState: Error set: $message");

        // Auto-clear certain errors
        if (autoClearing) {
          _errorClearTimer?.cancel();
          _errorClearTimer = Timer(const Duration(seconds: 3), () {
            _setErrorMessage(null);
            if (_chatStatus == ChatStatus.error) {
              _updateChatStatus(ChatStatus.idle);
            }
          });
        }
      }
      // Only notify if chat page is active
      if (_isChatPageActive) {
        notifyListeners();
      }
    }
  }

  void setIsProcessingAI(bool status) {
    if (_isProcessingAI != status) {
      _isProcessingAI = status;
      _logger.d("ChatState: isProcessingAI changed to: $status");
      // Only notify if chat page is active
      if (_isChatPageActive) {
        notifyListeners();
      }
    }
  }

  void updateHistory(List<Map<String, String>> newHistory) {
    _conversationHistory = List.from(newHistory);
    _logger.i(
      "ChatState: History updated externally. New length: ${_conversationHistory.length}",
    );
    // Always notify, let the UI decide to rebuild
    notifyListeners();
    // Only trigger scroll if the chat page is currently active
    if (_isChatPageActive) {
      _scrollToBottomCallback
          ?.call(); // Ensure scroll to bottom after history update
    }
  }

  void vibrate() {
    try {
      Vibration.vibrate(duration: 50);
    } catch (e) {
      _logger.w("ChatState: Vibration failed: $e");
    }
  }

  // Enhanced Lifecycle Management
  Future<void> pause() async {
    _logger.i("ChatState: Pausing chat state");
    await stopVoiceInput();
    await stopWakeWordListening();
    await stopSpeaking();

    // Cancel timers
    _commandDebounceTimer?.cancel();
    _errorClearTimer?.cancel();
    _followUpTimer?.cancel(); // Added: Cancel follow-up timer on pause
  }

  Future<void> resume() async {
    _logger.i("ChatState: Resuming chat state");

    if (!_isInitialized) {
      await initialize();
    }

    if (_currentInputMode == InputMode.voice) {
      await _ensureWakeWordListening();
    }
  }

  // Health check
  Future<bool> healthCheck() async {
    try {
      final speechAvailable =
          await _speechService.isSpeechRecognitionAvailable();
      final networkAvailable = _networkService.isOnline;

      _logger.i(
        "ChatState: Health check - Speech: $speechAvailable, Network: $networkAvailable",
      );

      if (!speechAvailable || !networkAvailable) {
        _handleError(
          "System services unavailable. Please check permissions and network.",
        );
        return false;
      }

      _resetErrorCount();
      return true;
    } catch (e) {
      _logger.e("ChatState: Health check failed: $e");
      _handleError("System health check failed");
      return false;
    }
  }

  @override
  void dispose() {
    _logger.i("ChatState: Disposing ChatState");

    // Cancel timers
    _commandDebounceTimer?.cancel();
    _errorClearTimer?.cancel();
    _followUpTimer?.cancel(); // Added: Cancel follow-up timer on dispose

    // Cancel all subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // Stop services (SpeechService itself is disposed in main.dart)
    _speechService.stopListening();
    _speechService.stopSpeaking();
    _speechService.stopWakeWordListening();

    super.dispose();
  }
}
