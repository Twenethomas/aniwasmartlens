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

  // Input Mode
  InputMode _currentInputMode = InputMode.voice;
  ChatStatus _chatStatus = ChatStatus.idle;

  // Timers and Debouncing
  Timer? _commandDebounceTimer;
  Timer? _errorClearTimer;
  Timer? _followUpTimer; // Added: Timer for follow-up listening
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

  // Navigation callback - now explicitly set from main.dart
  Function(String routeName, {Object? arguments})? onNavigateRequested;

  ChatState(
    this._speechService,
    this._geminiService,
    this._historyService,
    this._networkService,
  ) {
    // _initializeChatService();
    _subscriptions = [];
  }

  /// Sets a callback function to trigger scrolling to the bottom of the chat UI.
  /// This allows the ChatState to directly request a scroll after data updates.
  void setScrollToBottomCallback(Function() callback) {
    _scrollToBottomCallback = callback;
    _logger.d("ChatState: Scroll to bottom callback set.");
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

  // void _initializeChatService() {
  //   chatService = ChatService(
  //     _speechService,
  //     _geminiService,
  //     _historyService,
  //     _networkService,
  //     onProcessingStatusChanged: setIsProcessingAI,
  //     onSpeak: speak,
  //     onVibrate: vibrate,
  //     // onNavigate will be set by the main.dart file through chatState.navigateTo
  //     // No direct setting of onNavigate here, as it's handled by main.dart's setup
  //     onNavigate: navigateTo, // Pass chatState's own navigateTo method
  //     onAddUserMessage: addUserMessage,
  //     onAddAssistantMessage: addAssistantMessage,
  //   );
  // }

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
      notifyListeners();
    }
  }

  Future<void> _handleFinalRecognizedText(String finalText) async {
    _logger.i("ChatState: Final recognized text: \"$finalText\"");
    _recognizedText = ''; // Clear recognized text immediately
    if (finalText.isNotEmpty && _shouldProcessCommand(finalText)) {
      _updateChatStatus(ChatStatus.processing);
      // NOTE: User message added here to ChatState
      await addUserMessage(finalText); // Add user message to UI immediately

      // Pass the current context to chatService.processUserCommand
      // This context is necessary for TimeOfDay.now().format in ChatService
      await chatService.processUserCommand(
        finalText,
        navigatorKey.currentContext,
      );
      _resetErrorCount();
    } else if (finalText.isEmpty && _isListening) {
      // Added condition for empty final text when still listening
      _logger.i(
        "ChatState: STT stopped with no recognized text. Returning to idle.",
      );
      _isListening = false; // Update internal state
      _updateChatStatus(ChatStatus.idle); // Set status to idle
      await _ensureWakeWordListening(); // Re-enable wake word
    }
    // notifyListeners() is called in addUserMessage, not needed here directly.
    // However, if no user message was added (e.g., empty text), we still need to notify.
    if (finalText.isEmpty) {
      notifyListeners();
    }
  }

  void _handleListeningStatusChanged(bool status) {
    _logger.d("ChatState: Listening status changed: $status");
    _isListening = status;

    if (status) {
      _updateChatStatus(ChatStatus.listening);
      // Stop AI speech if user starts speaking (interruption)
      if (_isSpeaking) {
        stopSpeaking();
        _logger.i("ChatState: User interruption detected - stopping AI speech");
      }
      _followUpTimer
          ?.cancel(); // Cancel follow-up timer if listening starts manually
    } else if (_chatStatus == ChatStatus.listening) {
      // Only set to idle if not currently speaking or processing, and not during follow-up
      if (!_isSpeaking && !_isProcessingAI && _followUpTimer == null) {
        _updateChatStatus(ChatStatus.idle);
      }
    }

    _resetErrorCount();
    notifyListeners();
  }

  Future<void> _handleSpeakingStatusChanged(bool status) async {
    _logger.d("ChatState: Speaking status changed: $status");
    _isSpeaking = status;

    if (status) {
      _updateChatStatus(ChatStatus.speaking);
      _aiSpeakingFullText = ''; // Clear previous text when speaking starts
    } else if (_chatStatus == ChatStatus.speaking) {
      _aiSpeakingFullText = ''; // Clear text when speaking finishes
      // TTS has finished. Start follow-up listening.
      _logger.i(
        "ChatState: TTS Finished speaking. Starting follow-up listening.",
      );
      _updateChatStatus(ChatStatus.listening); // Set status to listening
      _isListening = true;
      _isWakeWordListening = false; // Ensure wake word is off

      // Start STT for follow-up questions for a limited duration
      await _speechService.startExtendedListening(
        maxDuration: _followUpListeningDuration,
      );

      // Start a timer to go back to wake word listening after follow-up duration
      _followUpTimer?.cancel(); // Cancel any existing timer
      _followUpTimer = Timer(_followUpListeningDuration, () async {
        _logger.i(
          "ChatState: Follow-up listening timeout. Returning to wake word.",
        );
        await _handleFollowUpTimeout();
      });
    }

    _resetErrorCount();
    notifyListeners();
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
    notifyListeners();
  }

  void _handleSpeakingText(String text) {
    _aiSpeakingFullText = text;
    notifyListeners();
  }

  void _handleWakeWordListeningChanged(bool status) {
    _isWakeWordListening = status;
    _logger.d("ChatState: Wake word listening status: $status");
    if (status) _resetErrorCount();
    notifyListeners();
  }

  void _handleWakeWordDetected(String wakeWord) {
    if (wakeWord.isNotEmpty) {
      _logger.i("ChatState: Wake word detected: $wakeWord");
      _detectedWakeWord = wakeWord;
      // CRITICAL FIX: Ensure _handleWakeWordActivation is awaited
      _handleWakeWordActivation(wakeWord);
      _resetErrorCount();
      notifyListeners();
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
      notifyListeners();
      // Ensure scroll to bottom after initial load
      _scrollToBottomCallback?.call();
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
      greeting =
          "Hello there! I'm Aniwa, your AI companion. I couldn't enable voice activation at the moment, but you can always type your commands. How can I assist you today?";
      _currentInputMode = InputMode.text; // Explicitly set to text mode
      _logger.i(
        "ChatState: Wake word failed, defaulting to text input for greeting.",
      );
    } else {
      greeting =
          "Hello there! I'm Aniwa, your AI companion. Say 'Assist Lens' to activate voice commands. How can I assist you today?";
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
    _lastCommand = trimmedCommand;
    _lastCommandTime = now;
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

      notifyListeners();
      _logger.i(
        "ChatState: addEntry: AFTER notifyListeners. History length at time of callback: ${_conversationHistory.length}",
      );

      // Explicitly trigger scroll to bottom after new message is added and notified
      if (_scrollToBottomCallback != null) {
        _logger.i("ChatState: addEntry: Triggering scroll to bottom callback.");
        _scrollToBottomCallback!();
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

  Future<void> addAssistantMessage(String content) async {
    _logger.i("ChatState: Calling addAssistantMessage for: '$content'");
    await addEntry(content, role: 'assistant');
  }

  Future<void> clearChatHistory() async {
    try {
      _logger.i("ChatState: Clearing chat history");
      _conversationHistory.clear();
      await _historyService.clearHistory();
      _setErrorMessage(null);
      _updateChatStatus(ChatStatus.idle);
      notifyListeners();
      _scrollToBottomCallback?.call(); // Scroll to top (empty state)
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
      notifyListeners();
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
    notifyListeners();
  }

  void _handleWakeWordActivation(String wakeWord) async {
    // Make it async
    _logger.i("ChatState: Processing wake word activation: $wakeWord");

    // Provide haptic feedback
    vibrate();

    // Stop AI speech if active
    if (_isSpeaking) {
      stopSpeaking();
      _logger.i("ChatState: Stopped AI speech due to wake word");
    }

    // Ensure voice mode
    if (_currentInputMode != InputMode.voice) {
      setInputMode(InputMode.voice);
    }

    // Clear errors
    _setErrorMessage(null);

    _logger.i("ChatState: Ready for voice input after wake word detection");

    // CRITICAL FIX: Explicitly start STT listening here after wake word is detected
    // This will now use the startListening method from SpeechService,
    // which includes the microphone release delay and clean STT restart logic.
    await _speechService.startListening(
      manualStart: false,
    ); // Start STT for user input

    _isListening = true; // Set listening status
    _updateChatStatus(ChatStatus.listening);
    notifyListeners();

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
    notifyListeners();
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
      notifyListeners();
    }
  }

  // Enhanced Utility Methods
  void _updateChatStatus(ChatStatus status) {
    if (_chatStatus != status) {
      _chatStatus = status;
      _logger.d("ChatState: Chat status changed to: $status");
      notifyListeners();
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
      notifyListeners();
    }
  }

  void setIsProcessingAI(bool status) {
    if (_isProcessingAI != status) {
      _isProcessingAI = status;
      _logger.d("ChatState: isProcessingAI changed to: $status");
      notifyListeners();
    }
  }

  void updateHistory(List<Map<String, String>> newHistory) {
    _conversationHistory = List.from(newHistory);
    _logger.i(
      "ChatState: History updated externally. New length: ${_conversationHistory.length}",
    );
    notifyListeners();
    _scrollToBottomCallback
        ?.call(); // Ensure scroll to bottom after history update
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
