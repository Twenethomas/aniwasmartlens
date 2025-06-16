// lib/core/services/chat_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart'; // Keep for TimeOfDay.now().format(context)
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import 'speech_service.dart';
import 'gemini_service.dart';
import '../routing/app_router.dart';
import 'history_services.dart';
import 'network_service.dart';
import '../../main.dart'; // For global logger
import '../../features/aniwa_chat/state/chat_state.dart'; // Still used for Provider.of in _handleClearChat

enum CommandType { direct, structured, conversation }

class CommandHandler {
  final Future<void> Function(BuildContext?, String, Map<String, dynamic>) execute;
  final CommandType type;

  CommandHandler(this.execute, this.type);
}

class ChatService {
  final SpeechService _speechService;
  final GeminiService _geminiService;
  final HistoryService _historyService; // Still used for _buildMessageHistory and direct history access
  final NetworkService _networkService;
  final Logger _logger;

  // Callbacks for UI integration (from ChatState)
  final Function(bool) onProcessingStatusChanged;
  final Future<void> Function(String) onSpeak;
  final Function() onVibrate;
  final Function(String routeName, {Object? arguments}) onNavigate; // This is the key navigation callback
  final Function(String content) onAddUserMessage; // NEW: Callback to add user message to ChatState
  final Function(String content) onAddAssistantMessage; // NEW: Callback to add assistant message to ChatState

  // Processing state
  bool _isProcessingCommand = false;
  String? _lastProcessedCommand;
  DateTime? _lastProcessedTime;
  Timer? _processingTimeoutTimer;
  String _lastSpokenResponse = '';

  // App context
  String? _currentScreenRoute;
  final Map<String, dynamic> _contextData = {};

  // Command patterns for direct processing
  late final Map<RegExp, CommandHandler> _directCommandPatterns;
  late final Map<String, CommandHandler> _intentActionMap;

  // Gemini configuration for structured responses
  static const Map<String, dynamic> _appActionSchema = {
    "responseMimeType": "application/json",
    "responseSchema": {
      "type": "OBJECT",
      "properties": {
        "action": {
          "type": "STRING",
          "enum": [
            "NONE",
            "OPEN_TEXT_READER",
            "OPEN_SCENE_DESCRIPTION",
            "OPEN_NAVIGATION",
            "OPEN_EMERGENCY",
            "OPEN_HISTORY",
            "OPEN_OBJECT_DETECTION",
            "OPEN_FACIAL_RECOGNITION",
            "EXPLORE_FEATURES",
            "CLEAR_CHAT",
            "HELLO",
            "DATE",
            "TIME",
            "WHO_ARE_YOU",
            "STATUS",
            "VOLUME_UP",
            "VOLUME_DOWN",
            "REPEAT_LAST",
            "STOP_SPEAKING",
          ],
        },
        "parameters": {
          "type": "OBJECT",
          "properties": {
            "autoCapture": {"type": "BOOLEAN"},
            "autoDescribe": {"type": "BOOLEAN"},
            "autoStartLive": {"type": "BOOLEAN"},
            "sensitivity": {"type": "NUMBER"},
            "repeatCount": {"type": "INTEGER"},
          },
        },
        "spokenResponse": {"type": "STRING"},
        "confidence": {"type": "NUMBER"},
      },
      "required": ["action", "spokenResponse"]
    },
  };

  ChatService(
    this._speechService,
    this._geminiService,
    this._historyService,
    this._networkService, {
    required this.onProcessingStatusChanged,
    required this.onSpeak,
    required this.onVibrate,
    required this.onNavigate, // This is the injected navigation callback
    required this.onAddUserMessage, // NEW
    required this.onAddAssistantMessage, // NEW
  }) : _logger = logger {
    _initializeCommandPatterns();
    _initializeIntentActionMap();
  }

  void updateCurrentRoute(String route) {
    _logger.i("ChatService: Updated current screen: $route");
    _currentScreenRoute = route;
  }

  void _initializeCommandPatterns() {
    _directCommandPatterns = {
      // Chat management
      RegExp(r'^(clear|empty|reset|delete) (chat|history|conversation)$', caseSensitive: false):
          CommandHandler(_handleClearChat, CommandType.direct),

      // Greetings and basic interactions
      RegExp(r'^(hello|hi|hey|greetings|good morning|good afternoon|good evening)', caseSensitive: false):
          CommandHandler(_handleGreeting, CommandType.direct),

      // Self-identification
      RegExp(r'^(who are you|introduce yourself|your name|what\s+is\s+your\s+name)', caseSensitive: false):
          CommandHandler(_handleSelfIntro, CommandType.direct),

      // Capabilities inquiry
      RegExp(r'^(what can you do|your capabilities|features|help|commands)', caseSensitive: false):
          CommandHandler(_handleCapabilities, CommandType.direct),

      // Status checks
      RegExp(r'^(how are you|how\s*\*s\s*it\s*going|your status)', caseSensitive: false):
          CommandHandler(_handleHowAreYou, CommandType.direct),

      // Time and date
      RegExp(r'^(time|current time|what time is it|tell me the time)$', caseSensitive: false):
          CommandHandler(_handleTime, CommandType.direct),
      RegExp(r'^(date|today\s*\*s\s*date|current date|what\s*\*s\s*today)$', caseSensitive: false):
          CommandHandler(_handleDate, CommandType.direct),

      // Connection status
      RegExp(r'^(status|are you online|connection status|network|internet)$', caseSensitive: false):
          CommandHandler(_handleOnlineStatus, CommandType.direct),

      // Speech control
      RegExp(r'^(stop|quiet|silence|shut up|stop talking)$', caseSensitive: false):
          CommandHandler(_handleStopSpeaking, CommandType.direct),
      RegExp(r'^(repeat|say again|what did you say)$', caseSensitive: false):
          CommandHandler(_handleRepeatLast, CommandType.direct),

      // Volume control
      RegExp(r'^(volume up|louder|increase volume|speak louder)$', caseSensitive: false):
          CommandHandler(_handleVolumeUp, CommandType.direct),
      RegExp(r'^(volume down|quieter|decrease volume|speak quieter)$', caseSensitive: false):
          CommandHandler(_handleVolumeDown, CommandType.direct),
    };
  }

  void _initializeIntentActionMap() {
    _intentActionMap = {
      "OPEN_TEXT_READER": CommandHandler(_handleOpenTextReader, CommandType.structured),
      "OPEN_SCENE_DESCRIPTION": CommandHandler(_handleOpenSceneDescription, CommandType.structured),
      "OPEN_NAVIGATION": CommandHandler(_handleOpenNavigation, CommandType.structured),
      "OPEN_EMERGENCY": CommandHandler(_handleOpenEmergency, CommandType.structured),
      "OPEN_HISTORY": CommandHandler(_handleOpenHistory, CommandType.structured),
      "OPEN_OBJECT_DETECTION": CommandHandler(_handleOpenObjectDetection, CommandType.structured),
      "OPEN_FACIAL_RECOGNITION": CommandHandler(_handleOpenFacialRecognition, CommandType.structured),
      "EXPLORE_FEATURES": CommandHandler(_handleExploreFeatures, CommandType.structured),
      "CLEAR_CHAT": CommandHandler(_handleClearChat, CommandType.structured),
      "HELLO": CommandHandler(_handleGreeting, CommandType.structured),
      "DATE": CommandHandler(_handleDate, CommandType.structured),
      "TIME": CommandHandler(_handleTime, CommandType.structured),
      "WHO_ARE_YOU": CommandHandler(_handleSelfIntro, CommandType.structured),
      "STATUS": CommandHandler(_handleOnlineStatus, CommandType.structured),
      "VOLUME_UP": CommandHandler(_handleVolumeUp, CommandType.structured),
      "VOLUME_DOWN": CommandHandler(_handleVolumeDown, CommandType.structured),
      "REPEAT_LAST": CommandHandler(_handleRepeatLast, CommandType.structured),
      "STOP_SPEAKING": CommandHandler(_handleStopSpeaking, CommandType.structured),
    };
  }

  // Main processing method - now accepts BuildContext only for TimeOfDay.now().format
  Future<void> processUserCommand(String command, BuildContext? currentContext) async {
    if (!_shouldProcessCommand(command)) return;
    await _executeCommand(command, currentContext);
  }

  bool _shouldProcessCommand(String command) {
    final normalizedCommand = command.toLowerCase().trim();

    if (normalizedCommand.isEmpty) {
      _logger.w("ChatService: Empty command received");
      return false;
    }

    // Check for duplicate commands
    if (_isProcessingCommand &&
        _lastProcessedCommand == normalizedCommand &&
        _lastProcessedTime != null &&
        DateTime.now().difference(_lastProcessedTime!) < const Duration(seconds: 2)) {
      _logger.w("ChatService: Skipping duplicate command: $normalizedCommand");
      return false;
    }

    return true;
  }

  // Pass BuildContext only if absolutely necessary (e.g., for TimeOfDay.now().format)
  Future<void> _executeCommand(String command, BuildContext? currentContext) async {
    _startProcessing(command);

    try {
      final commandType = _determineCommandType(command);

      switch (commandType) {
        case CommandType.direct:
          await _processDirectCommand(command, currentContext);
          break;
        case CommandType.structured:
          await _processStructuredCommand(command, currentContext);
          break;
        case CommandType.conversation:
          await _processConversationalCommand(command);
          break;
      }
    } catch (e, stackTrace) {
      _logger.e("ChatService: Command processing error: $e", error: e, stackTrace: stackTrace);
      await _handleProcessingError(e);
    } finally {
      _finishProcessing();
    }
  }

  void _startProcessing(String command) {
    _isProcessingCommand = true;
    _lastProcessedCommand = command.toLowerCase().trim();
    _lastProcessedTime = DateTime.now();
    onProcessingStatusChanged(true);

    // Set processing timeout
    _processingTimeoutTimer?.cancel();
    _processingTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_isProcessingCommand) {
        _logger.w("ChatService: Processing timeout reached");
        _finishProcessing();
      }
    });
  }

  void _finishProcessing() {
    _isProcessingCommand = false;
    _processingTimeoutTimer?.cancel();
    onProcessingStatusChanged(false);
  }

  CommandType _determineCommandType(String command) {
    final normalizedCommand = command.toLowerCase().trim();

    // Check for direct command patterns first
    if (_directCommandPatterns.keys.any((pattern) => pattern.hasMatch(normalizedCommand))) {
      return CommandType.direct;
    }

    // Check if it's likely a feature request that needs structured processing
    if (_isFeatureRequest(normalizedCommand)) {
      return CommandType.structured;
    }

    // Default to conversational
    return CommandType.conversation;
  }

  bool _isFeatureRequest(String command) {
    final featureKeywords = [
      'open', 'start', 'launch', 'go to', 'navigate', 'show', 'read', 'describe',
      'detect', 'recognize', 'scan', 'find', 'emergency', 'help', 'call'
    ];

    return featureKeywords.any((keyword) => command.contains(keyword));
  }

  // Pass BuildContext for TimeOfDay.now().format only if needed
  Future<void> _processDirectCommand(String command, BuildContext? currentContext) async {
    final normalizedCommand = command.toLowerCase().trim();

    final handler = _directCommandPatterns.entries
        .firstWhere((entry) => entry.key.hasMatch(normalizedCommand))
        .value;

    _logger.i("ChatService: Executing direct command: $normalizedCommand");
    await handler.execute(currentContext, command, {}); // Pass context only if needed by handler
  }

  Future<void> _processStructuredCommand(String command, BuildContext? currentContext) async {
    if (!await _networkService.checkConnectionAndReturnStatus()) {
      await _handleOfflineCommand(command);
      return;
    }

    _logger.i("ChatService: Processing structured command with Gemini");

    final response = await _getGeminiStructuredResponse(command);
    await _executeStructuredResponse(response, currentContext); // Pass context only if needed by handler
  }

  Future<void> _processConversationalCommand(String command) async {
    if (!await _networkService.checkConnectionAndReturnStatus()) {
      await _handleOfflineCommand(command);
      return;
    }

    _logger.i("ChatService: Processing conversational command");

    final response = await _getGeminiConversationalResponse(command);
    await onSpeak(response);
    onAddAssistantMessage(response); // Use callback to add assistant message
    _lastSpokenResponse = response;
  }

  Future<Map<String, dynamic>> _getGeminiStructuredResponse(String command) async {
    final systemInstructions = _buildSystemInstructions();
    final messages = _buildMessageHistory(command, systemInstructions);

    try {
      final geminiResponse = await _geminiService.getChatResponse(
        messages,
        generationConfig: _appActionSchema,
      );

      return _parseGeminiResponse(geminiResponse);
    } catch (e) {
      _logger.e("ChatService: Gemini structured response failed: $e");
      return _buildFallbackResponse("I'm having trouble processing that request. Please try again.");
    }
  }

  Future<String> _getGeminiConversationalResponse(String command) async {
    final historyForGemini = _historyService.getHistory().map((e) => {
      'role': e['role'],
      'parts': [{'text': e['content']}],
    }).toList();

    try {
      return await _geminiService.getChatResponse(historyForGemini);
    } catch (e) {
      _logger.e("ChatService: Gemini conversational response failed: $e");
      return "I'm having trouble understanding that. Could you please try rephrasing your request?";
    }
  }

  String _buildSystemInstructions() {
    return """
You are Aniwa an Assistive Lens, a compassionate AI assistant designed for visually impaired users.

Current Context:
- Screen: ${_currentScreenRoute ?? 'unknown'}
- Additional context: $_contextData

Guidelines:
1. Be concise yet warm in responses
2. Announce screen changes clearly
3. Confirm actions when completed
4. Only use JSON actions when explicitly requested
5. Default to natural conversation (NONE action)

Response Format (when action needed):
{
  "action": "ACTION_TYPE",
  "parameters": { /* optional */ },
  "spokenResponse": "Clear, friendly response",
  "confidence": 0.8
}

Example for text reader request:
{
  "action": "OPEN_TEXT_READER",
  "parameters": {"autoCapture": true},
  "spokenResponse": "Opening text reader. Point your camera at the text.",
  "confidence": 0.9
}
""";
  }

  List<Map<String, dynamic>> _buildMessageHistory(String command, String systemInstructions) {
    final historyForGemini = _historyService.getHistory().map((e) => {
      'role': e['role'],
      'parts': [{'text': e['content']}],
    }).toList();

    List<Map<String, dynamic>> messages = [];

    if (historyForGemini.isEmpty) {
      messages.add({
        "role": "user",
        "parts": [
          {"text": "$systemInstructions\n\nUser request: \"$command\""},
        ],
      });
    } else {
      for (int i = 0; i < historyForGemini.length; i++) {
        final msg = Map<String, dynamic>.from(historyForGemini[i]);
        if (i == 0 && msg['role'] == 'user') {
          msg['parts'][0]['text'] = "$systemInstructions\n\nUser request: \"${msg['parts'][0]['text']}\"";
        }
        messages.add(msg);
      }
    }

    return messages;
  }

  Map<String, dynamic> _parseGeminiResponse(String geminiResponse) {
    try {
      final response = json.decode(geminiResponse);
      if (response?['action'] == null || response?['spokenResponse'] == null) {
        throw const FormatException('Invalid response structure');
      }
      return response;
    } catch (_) {
      return _buildFallbackResponse("Let me think differently about that request");
    }
  }

  Map<String, dynamic> _buildFallbackResponse(String message) {
    return {
      "action": "NONE",
      "spokenResponse": message,
      "confidence": 0.5
    };
  }

  // Pass BuildContext for TimeOfDay.now().format only if needed
  Future<void> _executeStructuredResponse(Map<String, dynamic> response, BuildContext? currentContext) async {
    final action = response['action'] ?? 'NONE';
    final params = response['parameters'] ?? <String, dynamic>{};
    final spoken = response['spokenResponse'] ?? '';

    if (action == 'NONE') {
      await onSpeak(spoken);
      onAddAssistantMessage(spoken); // Use callback to add assistant message
      _lastSpokenResponse = spoken;
    } else {
      await onVibrate(); // Tactile feedback for actions
      if (spoken.isNotEmpty) {
        await onSpeak(spoken);
        _lastSpokenResponse = spoken;
      }

      final handler = _intentActionMap[action];
      if (handler != null) {
        // Pass currentContext if it's a Time/Date command, otherwise null
        await handler.execute(action == "TIME" || action == "DATE" ? currentContext : null, '', params);

        // Maintain conversation flow after actions
        if (action != "CLEAR_CHAT" && action != "STOP_SPEAKING") {
          await Future.delayed(const Duration(seconds: 1));
          await onSpeak("What else can I help with?");
        }
      } else {
        _logger.w("ChatService: Unknown action: $action");
        await onSpeak("I'm not sure how to handle that action.");
      }
    }
  }

  Future<void> _handleOfflineCommand(String command) async {
    _logger.i("ChatService: Processing offline command");
    final response = _getOfflineResponse(command);
    await onSpeak(response);
    onAddAssistantMessage(response); // Use callback to add assistant message
    _lastSpokenResponse = response;
  }

  Future<void> _handleProcessingError(dynamic error) async {
    final errorMessage = "Let me try that again. Could you repeat?";
    await onSpeak(errorMessage);
    onAddAssistantMessage(errorMessage); // Use callback to add assistant message
    _lastSpokenResponse = errorMessage;
  }

  // =============== COMMAND HANDLERS ===============
  // Removed BuildContext? context from these handlers as onNavigate is now global.
  // Except for _handleTime and _handleDate where context is actually used.

  Future<void> _handleClearChat(BuildContext? context, String command, Map<String, dynamic> params) async {
    _historyService.clearHistory();
    // This Provider.of call uses the context from the initial ChatState creation in main.dart.
    // It's still necessary if clearChatHistory modifies UI state directly via Provider.
    if (context != null && context.mounted) {
      Provider.of<ChatState>(context, listen: false).clearChatHistory();
    }
    await onVibrate();
    final response = "Chat history cleared. Fresh start!";
    await onSpeak(response);
    _lastSpokenResponse = response;
  }

  Future<void> _handleGreeting(BuildContext? context, String command, Map<String, dynamic> params) async {
    final response = "Hello there! I'm Assist Lens. How can I help you today?";
    await onSpeak(response);
    onAddAssistantMessage(response);
    _lastSpokenResponse = response;
  }

  Future<void> _handleSelfIntro(BuildContext? context, String command, Map<String, dynamic> params) async {
    final response = "I'm Assist Lens, your helpful assistant. I can read text, describe scenes, recognize objects and faces, and more.";
    await onSpeak(response);
    onAddAssistantMessage(response);
    _lastSpokenResponse = response;
  }

  Future<void> _handleCapabilities(BuildContext? context, String command, Map<String, dynamic> params) async {
    final response = "I can help with: Reading text aloud, describing your surroundings, recognizing objects and faces, navigation assistance, emergency contacts, and general questions. What would you like to try?";
    await onSpeak(response);
    onAddAssistantMessage(response);
    _lastSpokenResponse = response;
  }

  Future<void> _handleHowAreYou(BuildContext? context, String command, Map<String, dynamic> params) async {
    final response = "I'm functioning well and ready to assist you!";
    await onSpeak(response);
    onAddAssistantMessage(response);
    _lastSpokenResponse = response;
  }

  Future<void> _handleTime(BuildContext? context, String command, Map<String, dynamic> params) async {
    // Only use context for TimeOfDay.now().format
    final time = context != null && context.mounted ? TimeOfDay.now().format(context) : "unknown";
    final response = "The current time is $time.";
    await onSpeak(response);
    onAddAssistantMessage(response);
    _lastSpokenResponse = response;
  }

  Future<void> _handleDate(BuildContext? context, String command, Map<String, dynamic> params) async {
    final date = DateTime.now().toLocal().toString().split(' ')[0];
    final response = "Today's date is ${_formatDateForSpeech(date)}.";
    await onSpeak(response);
    onAddAssistantMessage(response);
    _lastSpokenResponse = response;
  }

  Future<void> _handleOnlineStatus(BuildContext? context, String command, Map<String, dynamic> params) async {
    final isOnline = _networkService.isOnline;
    final response = isOnline
        ? "I'm currently online with full capabilities."
        : "I'm offline but can still handle basic tasks.";
    await onSpeak(response);
    onAddAssistantMessage(response);
    _lastSpokenResponse = response;
  }

  Future<void> _handleStopSpeaking(BuildContext? context, String command, Map<String, dynamic> params) async {
    await _speechService.stopSpeaking();
  }

  Future<void> _handleRepeatLast(BuildContext? context, String command, Map<String, dynamic> params) async {
    if (_lastSpokenResponse.isNotEmpty) {
      await onSpeak(_lastSpokenResponse);
    } else {
      await onSpeak("I haven't said anything yet to repeat.");
    }
  }

  Future<void> _handleVolumeUp(BuildContext? context, String command, Map<String, dynamic> params) async {
    await _speechService.adjustVolume(0.1); // Increase by 10%
    await onSpeak("Volume increased.");
  }

  Future<void> _handleVolumeDown(BuildContext? context, String command, Map<String, dynamic> params) async {
    await _speechService.adjustVolume(-0.1); // Decrease by 10%
    await onSpeak("Volume decreased.");
  }

  // Feature opening handlers - now directly call onNavigate
  Future<void> _handleOpenTextReader(BuildContext? context, String command, Map<String, dynamic> params) async {
    final autoCapture = params['autoCapture'] ?? false;
    final message = autoCapture
        ? "Opening text reader. Camera will activate shortly to capture text automatically."
        : "Opening text reader. Tap the capture button when ready.";
    await onSpeak(message);
    onAddAssistantMessage(message);
    onNavigate(AppRouter.textReader, arguments: {'autoCapture': autoCapture});
    _lastSpokenResponse = message;
  }

  Future<void> _handleOpenSceneDescription(BuildContext? context, String command, Map<String, dynamic> params) async {
    final autoDescribe = params['autoDescribe'] ?? false;
    final message = autoDescribe
        ? "Opening scene description. Analyzing your surroundings now."
        : "Opening scene description. Point your camera and tap describe when ready.";
    await onSpeak(message);
    onAddAssistantMessage(message);
    onNavigate(AppRouter.sceneDescription, arguments: {'autoDescribe': autoDescribe});
    _lastSpokenResponse = message;
  }

  Future<void> _handleOpenNavigation(BuildContext? context, String command, Map<String, dynamic> params) async {
    final message = "Opening navigation. I'll help guide you.";
    await onSpeak(message);
    onAddAssistantMessage(message);
    onNavigate(AppRouter.navigation);
    _lastSpokenResponse = message;
  }

  Future<void> _handleOpenEmergency(BuildContext? context, String command, Map<String, dynamic> params) async {
    final message = "Opening emergency contacts. Important numbers are ready.";
    await onSpeak(message);
    onAddAssistantMessage(message);
    onNavigate(AppRouter.emergency);
    _lastSpokenResponse = message;
  }

  Future<void> _handleOpenHistory(BuildContext? context, String command, Map<String, dynamic> params) async {
    final message = "Opening your history. Previous conversations are here.";
    await onSpeak(message);
    onAddAssistantMessage(message);
    onNavigate(AppRouter.history);
    _lastSpokenResponse = message;
  }

  Future<void> _handleOpenObjectDetection(BuildContext? context, String command, Map<String, dynamic> params) async {
    final autoStartLive = params['autoStartLive'] ?? true;
    final message = autoStartLive
        ? "Object detection starting. I'll describe what the camera sees."
        : "Object detection ready. Activate camera when you're set.";
    await onSpeak(message);
    onAddAssistantMessage(message);
    onNavigate(AppRouter.objectDetector, arguments: {'autoStartLive': autoStartLive});
    _lastSpokenResponse = message;
  }

  Future<void> _handleOpenFacialRecognition(BuildContext? context, String command, Map<String, dynamic> params) async {
    final autoStartLive = params['autoStartLive'] ?? true;
    final message = autoStartLive
        ? "Facial recognition starting. Looking for familiar faces."
        : "Facial recognition ready. Activate when you want to scan.";
    await onSpeak(message);
    onAddAssistantMessage(message);
    onNavigate(AppRouter.facialRecognition, arguments: {'autoStartLive': autoStartLive});
    _lastSpokenResponse = message;
  }

  Future<void> _handleExploreFeatures(BuildContext? context, String command, Map<String, dynamic> params) async {
    final message = "Exploring features. Here's what I can help with.";
    await onSpeak(message);
    onAddAssistantMessage(message);
    onNavigate(AppRouter.exploreFeatures);
    _lastSpokenResponse = message;
  }

  // Utility methods
  String _formatDateForSpeech(String date) {
    final parts = date.split('-');
    return "${parts[1]}-${parts[2]}-${parts[0]}"; // MM-DD-YYYY format for speech
  }

  String _getOfflineResponse(String command) {
    final cmd = command.toLowerCase();

    if (RegExp(r'^(open|go to|navigate)').hasMatch(cmd)) {
      return "I can't open features while offline. Try asking about time, date, or my capabilities.";
    }

    if (RegExp(r'^(hello|hi|hey)').hasMatch(cmd)) {
      return "Hello! I'm offline but here for basic help.";
    }

    if (RegExp(r'^(time|current time)').hasMatch(cmd)) {
      return "While offline, I can't give exact time. Check your device clock.";
    }

    if (RegExp(r'^(date|today)').hasMatch(cmd)) {
      return "Offline date may not be exact. Today should be around ${DateTime.now().month}-${DateTime.now().day}.";
    }

    if (RegExp(r'^(who are you|your name)').hasMatch(cmd)) {
      return "I'm Assist Lens, your offline assistant.";
    }

    return "I'm offline now. Available commands: greetings, my name, or general questions.";
  }

  void dispose() {
    _processingTimeoutTimer?.cancel();
  }
}
