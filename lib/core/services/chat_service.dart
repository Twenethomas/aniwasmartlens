// lib/core/services/chat_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:assist_lens/main.dart' as NavigationService;
import 'package:flutter/material.dart'; // Keep for TimeOfDay.now().format(context)
import 'package:logger/logger.dart';
//import 'package:provider/provider.dart';

import 'speech_service.dart';
import 'gemini_service.dart';
//import '../routing/app_router.dart';
import 'history_services.dart';
import 'network_service.dart';
// import '../../features/settings/state/settings_state.dart';
// import '../../features/scene_description/scene_description_state.dart';
// import '../../features/text_reader/text_reader_state.dart';
// import '../../features/face_recognition/facial_recognition_state.dart';
import '../../main.dart'; // For global logger
// import '../../features/aniwa_chat/state/chat_state.dart'; // Still used for Provider.of in _handleClearChat

enum CommandType { direct, structured, conversation }

class CommandHandler {
  final Future<void> Function(BuildContext?, String, Map<String, dynamic>)
  execute;
  final CommandType type;

  CommandHandler(this.execute, this.type);
}

class ChatService {
  final SpeechService _speechService;
  final GeminiService _geminiService;
  final HistoryService
  _historyService; // Still used for _buildMessageHistory and direct history access
  final NetworkService _networkService;
  final Logger _logger;

  // Callbacks for UI integration (from ChatState)
  final Function(bool) onProcessingStatusChanged;
  final Future<void> Function(String) onSpeak;
  final Function() onVibrate;
  final Function(String routeName, {Object? arguments})
  onNavigate; // This is the key navigation callback
  final Function(String content)
  onAddUserMessage; // NEW: Callback to add user message to ChatState
  final Function(String content)
  onAddAssistantMessage; // NEW: Callback to add assistant message to ChatState

  // Processing state
  bool _isProcessingCommand = false;
  Timer? _processingTimeoutTimer;
  String _lastSpokenResponse = '';
  // ...existing code...
  String? _userName;
  bool _isBlindMode = false;

  void updateUserInfo({String? userName, bool? isBlindMode}) {
    if (userName != null) _userName = userName;
    if (isBlindMode != null) _isBlindMode = isBlindMode;
  }

  // ...existing code...
  // App context
  String? _currentScreenRoute;
  final Map<String, dynamic> _contextData = {};

  // Command patterns for direct processing
  late final Map<RegExp, CommandHandler> _directCommandPatterns;
  late final Map<String, CommandHandler> _intentActionMap;
  late final Map<RegExp, String> _offlineActionPatterns;

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
            "CAPTURE_TEXT",
            "RESET_APP",
            "DESCRIBE_SCENE",
            "SEND_SCENE_TO_CHAT",
            "SPEAK_SCENE_DESCRIPTION",
            "CORRECT_TEXT",
            "TRANSLATE_TEXT",
            "SPEAK_TEXT",
            "SEND_TEXT_TO_CHAT",
            "REGISTER_FACE",
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
            "targetLanguage": {"type": "STRING"},
            "repeatCount": {"type": "INTEGER"},
          },
        },
        "spokenResponse": {"type": "STRING"},
        "confidence": {"type": "NUMBER"},
      },
      "required": ["action", "spokenResponse"],
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
    _initializeOfflineActionPatterns();
  }

  void updateCurrentRoute(String route) {
    _logger.i("ChatService: Updated current screen: $route");
    _currentScreenRoute = route;
  }

  void _initializeCommandPatterns() {
    _directCommandPatterns = {
      // Chat management
      RegExp(
        r'^(clear|empty|reset|delete) (chat|history|conversation)$',
        caseSensitive: false,
      ): CommandHandler(_handleClearChat, CommandType.direct),

      // Greetings and basic interactions
      RegExp(
        r'^(hello|hi|hey|greetings|good morning|good afternoon|good evening)',
        caseSensitive: false,
      ): CommandHandler(_handleGreeting, CommandType.direct),

      // Self-identification
      RegExp(
        r'^(who are you|introduce yourself|your name|what\s+is\s+your\s+name)',
        caseSensitive: false,
      ): CommandHandler(_handleSelfIntro, CommandType.direct),

      // Capabilities inquiry
      RegExp(
        r'^(what can you do|your capabilities|features|help|commands)',
        caseSensitive: false,
      ): CommandHandler(_handleCapabilities, CommandType.direct),

      // Status checks
      RegExp(
        r'^(how are you|how\s*\*s\s*it\s*going|your status)',
        caseSensitive: false,
      ): CommandHandler(_handleHowAreYou, CommandType.direct),

      // Time and date
      RegExp(
        r'^(time|current time|what time is it|tell me the time)$',
        caseSensitive: false,
      ): CommandHandler(_handleTime, CommandType.direct),
      RegExp(
        r'^(date|today\s*\*s\s*date|current date|what\s*\*s\s*today)$',
        caseSensitive: false,
      ): CommandHandler(_handleDate, CommandType.direct),

      // Connection status
      RegExp(
        r'^(status|are you online|connection status|network|internet)$',
        caseSensitive: false,
      ): CommandHandler(_handleOnlineStatus, CommandType.direct),

      // Speech control
      RegExp(
        r'^(stop|quiet|silence|shut up|stop talking)$',
        caseSensitive: false,
      ): CommandHandler(_handleStopSpeaking, CommandType.direct),
      RegExp(
        r'^(repeat|say again|what did you say)$',
        caseSensitive: false,
      ): CommandHandler(_handleRepeatLast, CommandType.direct),

      // Volume control
      RegExp(
        r'^(volume up|louder|increase volume|speak louder)$',
        caseSensitive: false,
      ): CommandHandler(_handleVolumeUp, CommandType.direct),
      RegExp(
        r'^(volume down|quieter|decrease volume|speak quieter)$',
        caseSensitive: false,
      ): CommandHandler(_handleVolumeDown, CommandType.direct),
    };
  }

  void _initializeIntentActionMap() {
    _intentActionMap = {
      "OPEN_TEXT_READER": CommandHandler(
        _handleOpenTextReader,
        CommandType.structured,
      ),
      "OPEN_SCENE_DESCRIPTION": CommandHandler(
        _handleOpenSceneDescription,
        CommandType.structured,
      ),
      "OPEN_NAVIGATION": CommandHandler(
        _handleOpenNavigation,
        CommandType.structured,
      ),
      "OPEN_EMERGENCY": CommandHandler(
        _handleOpenEmergency,
        CommandType.structured,
      ),
      "OPEN_HISTORY": CommandHandler(
        _handleOpenHistory,
        CommandType.structured,
      ),
      "OPEN_OBJECT_DETECTION": CommandHandler(
        _handleOpenObjectDetection,
        CommandType.structured,
      ),
      "OPEN_FACIAL_RECOGNITION": CommandHandler(
        _handleOpenFacialRecognition,
        CommandType.structured,
      ),
      "EXPLORE_FEATURES": CommandHandler(
        _handleExploreFeatures,
        CommandType.structured,
      ),
      "CAPTURE_TEXT": CommandHandler(
        _handleCaptureText,
        CommandType.structured,
      ),
      "RESET_APP": CommandHandler(_handleResetApp, CommandType.structured),
      "DESCRIBE_SCENE": CommandHandler(
        _handleDescribeScene,
        CommandType.structured,
      ),
      "SEND_SCENE_TO_CHAT": CommandHandler(
        _handleSendSceneToChat,
        CommandType.structured,
      ),
      "SPEAK_SCENE_DESCRIPTION": CommandHandler(
        _handleSpeakSceneDescription,
        CommandType.structured,
      ),
      "CORRECT_TEXT": CommandHandler(
        _handleCorrectText,
        CommandType.structured,
      ),
      "TRANSLATE_TEXT": CommandHandler(
        _handleTranslateText,
        CommandType.structured,
      ),
      "SPEAK_TEXT": CommandHandler(_handleSpeakText, CommandType.structured),
      "SEND_TEXT_TO_CHAT": CommandHandler(
        _handleSendTextToChat,
        CommandType.structured,
      ),
      "REGISTER_FACE": CommandHandler(
        _handleRegisterFace,
        CommandType.structured,
      ),
      "CLEAR_CHAT": CommandHandler(_handleClearChat, CommandType.structured),
      "HELLO": CommandHandler(_handleGreeting, CommandType.structured),
      "DATE": CommandHandler(_handleDate, CommandType.structured),
      "TIME": CommandHandler(_handleTime, CommandType.structured),
      "WHO_ARE_YOU": CommandHandler(_handleSelfIntro, CommandType.structured),
      "STATUS": CommandHandler(_handleOnlineStatus, CommandType.structured),
      "VOLUME_UP": CommandHandler(_handleVolumeUp, CommandType.structured),
      "VOLUME_DOWN": CommandHandler(_handleVolumeDown, CommandType.structured),
      "REPEAT_LAST": CommandHandler(_handleRepeatLast, CommandType.structured),
      "STOP_SPEAKING": CommandHandler(
        _handleStopSpeaking,
        CommandType.structured,
      ),
    };
  }

  void _initializeOfflineActionPatterns() {
    _offlineActionPatterns = {
      // Feature opening patterns
      RegExp(
            r'\b(open|start|launch|go to|show me)\s+(text|reader|ocr)\b',
            caseSensitive: false,
          ):
          'OPEN_TEXT_READER',
      RegExp(
        r'\b(open|start|launch|go to|show me)\s+(scene|description|camera)\b',
        caseSensitive: false,
      ): 'OPEN_SCENE_DESCRIPTION',
      RegExp(
        r'\b(open|start|launch|go to|show me)\s+(navigation|navigate|directions|map)\b',
        caseSensitive: false,
      ): 'OPEN_NAVIGATION',
      RegExp(
            r'\b(open|start|launch|go to|show me)\s+(emergency|sos|contacts)\b',
            caseSensitive: false,
          ):
          'OPEN_EMERGENCY',
      RegExp(
        r'\b(open|start|launch|go to|show me)\s+(history|past|conversations|logs)\b',
        caseSensitive: false,
      ): 'OPEN_HISTORY',
      RegExp(
        r'\b(open|start|launch|go to|show me)\s+(object|detection|detector)\b',
        caseSensitive: false,
      ): 'OPEN_OBJECT_DETECTION',
      RegExp(
        r'\b(open|start|launch|go to|show me)\s+(face|facial|recognition)\b',
        caseSensitive: false,
      ): 'OPEN_FACIAL_RECOGNITION',
      RegExp(
            r'\b(open|start|launch|go to|show me)\s+(features|explore|menu)\b',
            caseSensitive: false,
          ):
          'EXPLORE_FEATURES',

      // Direct action patterns
      RegExp(
        r'\b(read|scan|capture|take)\s+(text|document|sign|picture|photo)\b',
        caseSensitive: false,
      ): 'CAPTURE_TEXT',
      RegExp(
        r'\b(describe|what\s*do\s*you\s*see|analyze)\s+(scene|surroundings|view|image)\b',
        caseSensitive: false,
      ): 'DESCRIBE_SCENE',
      RegExp(
            r'\b(send|share)\s+(scene|description)\s+(to\s+)?chat\b',
            caseSensitive: false,
          ):
          'SEND_SCENE_TO_CHAT',
      RegExp(
            r'\b(speak|read\s*out|say)\s+(scene|description)\b',
            caseSensitive: false,
          ):
          'SPEAK_SCENE_DESCRIPTION',
      RegExp(r'\b(correct|fix|improve)\s+text\b', caseSensitive: false):
          'CORRECT_TEXT',
      RegExp(r'\b(translate|convert)\s+text\b', caseSensitive: false):
          'TRANSLATE_TEXT',
      RegExp(r'\b(speak|read\s*out|say)\s+text\b', caseSensitive: false):
          'SPEAK_TEXT',
      RegExp(r'\b(send|share)\s+text\s+(to\s+)?chat\b', caseSensitive: false):
          'SEND_TEXT_TO_CHAT',
      RegExp(r'\b(register|add|save)\s+(face|person)\b', caseSensitive: false):
          'REGISTER_FACE',
      RegExp(
            r'\b(clear|delete|empty)\s+(chat|history|conversation)\b',
            caseSensitive: false,
          ):
          'CLEAR_CHAT',
      RegExp(r'\b(reset|restart)\s+app\b', caseSensitive: false): 'RESET_APP',

      // Contextual patterns
      RegExp(r'\b(take\s+picture|capture|snap|shoot)\b', caseSensitive: false):
          'CAPTURE_TEXT', // Context-dependent
      RegExp(
            r'\b(what\s*do\s*you\s*see|describe|analyze)\b',
            caseSensitive: false,
          ):
          'DESCRIBE_SCENE', // Context-dependent
      RegExp(r'\b(send\s+to\s+chat|share)\b', caseSensitive: false):
          'SEND_SCENE_TO_CHAT', // Context-dependent
      RegExp(r'\b(speak|read\s*out|say\s*it)\b', caseSensitive: false):
          'SPEAK_SCENE_DESCRIPTION', // Context-dependent
      // Basic interactions that might need structured handling
      RegExp(r'\b(hello|hi|hey|greetings)\b', caseSensitive: false): 'HELLO',
      RegExp(r'\b(time|current\s*time|what\s*time)\b', caseSensitive: false):
          'TIME',
      RegExp(r'\b(date|today|current\s*date)\b', caseSensitive: false): 'DATE',
      RegExp(
            r'\b(who\s*are\s*you|your\s*name|introduce)\b',
            caseSensitive: false,
          ):
          'WHO_ARE_YOU',
      RegExp(r'\b(status|online|connection)\b', caseSensitive: false): 'STATUS',
      RegExp(
            r'\b(volume\s*up|louder|increase\s*volume)\b',
            caseSensitive: false,
          ):
          'VOLUME_UP',
      RegExp(
            r'\b(volume\s*down|quieter|decrease\s*volume)\b',
            caseSensitive: false,
          ):
          'VOLUME_DOWN',
      RegExp(r'\b(repeat|say\s*again)\b', caseSensitive: false): 'REPEAT_LAST',
      RegExp(r'\b(stop|quiet|silence|shut\s*up)\b', caseSensitive: false):
          'STOP_SPEAKING',
    };
  }

  // Main processing method - now accepts BuildContext only for TimeOfDay.now().format
  Future<void> processUserCommand(
    String command,
    BuildContext? currentContext,
  ) async {
    // Assumes command has already been validated and debounced by ChatState
    await _executeCommand(
      command.trim(),
      currentContext,
    ); // Trim command before processing
  }

  // Pass BuildContext only if absolutely necessary (e.g., for TimeOfDay.now().format)
  Future<void> _executeCommand(
    String command,
    BuildContext? currentContext,
  ) async {
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
      _logger.e(
        "ChatService: Command processing error: $e",
        error: e,
        stackTrace: stackTrace,
      );
      await _handleProcessingError(e);
    } finally {
      _finishProcessing();
    }
  }

  void _startProcessing(String command) {
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
    if (_directCommandPatterns.keys.any(
      (pattern) => pattern.hasMatch(normalizedCommand),
    )) {
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
      'open',
      'start',
      'launch',
      'go to',
      'navigate',
      'show',
      'read',
      'describe',
      'detect',
      'recognize',
      'scan',
      'find',
      'emergency',
      'help',
      'call',
      'capture',
      'take',
      'translate',
      'correct',
      'speak',
      'send',
      'register',
      'clear',
      'reset',
    ];

    return featureKeywords.any((keyword) => command.contains(keyword));
  }

  // Pass BuildContext for TimeOfDay.now().format only if needed
  Future<void> _processDirectCommand(
    String command,
    BuildContext? currentContext,
  ) async {
    final normalizedCommand = command.toLowerCase().trim();

    final handler =
        _directCommandPatterns.entries
            .firstWhere((entry) => entry.key.hasMatch(normalizedCommand))
            .value;

    _logger.i("ChatService: Executing direct command: $normalizedCommand");
    await handler.execute(
      currentContext,
      command,
      {},
    ); // Pass context only if needed by handler
  }

  Future<void> _processOfflineStructuredCommand(
    String command,
    BuildContext? currentContext,
  ) async {
    _logger.i("ChatService: Processing OFFLINE structured command: '$command'");
    final normalizedCommand = command.toLowerCase().trim();

    String? matchedAction;

    // First, try to match contextual actions based on current screen
    if (_currentScreenRoute != null) {
      matchedAction = _getContextualAction(
        normalizedCommand,
        _currentScreenRoute!,
      );
    }

    // If no contextual match, try general patterns
    if (matchedAction == null) {
      for (var entry in _offlineActionPatterns.entries) {
        if (entry.key.hasMatch(normalizedCommand)) {
          matchedAction = entry.value;
          break;
        }
      }
    }

    if (matchedAction != null) {
      final handler = _intentActionMap[matchedAction];
      if (handler != null) {
        // Create appropriate offline spoken response
        final spokenResponse = _generateOfflineSpokenResponse(
          matchedAction,
          normalizedCommand,
        );

        await onSpeak(spokenResponse);
        onAddAssistantMessage(spokenResponse); // Add to history
        _lastSpokenResponse = spokenResponse;

        // Execute the action with empty parameters since we're offline
        await handler.execute(currentContext, command, {});
      } else {
        _logger.w(
          "ChatService: Offline match found for '$matchedAction', but no handler exists.",
        );
        await _handleOfflineCommand(
          command,
        ); // Fallback to generic offline message
      }
    } else {
      _logger.i(
        "ChatService: No specific offline action matched for '$command'. Using generic response.",
      );
      await _handleOfflineCommand(
        command,
      ); // Fall-through to generic "I can't do that offline"
    }
  }

  final Map<String, List<String>> _screenActionMap = {
    '/textReader': [
      'CAPTURE_TEXT',
      'CORRECT_TEXT',
      'TRANSLATE_TEXT',
      'SPEAK_TEXT',
      'SEND_TEXT_TO_CHAT',
      'RESET_APP',
    ],
    '/sceneDescription': [
      'DESCRIBE_SCENE',
      'SEND_SCENE_TO_CHAT',
      'SPEAK_SCENE_DESCRIPTION',
      'RESET_APP',
    ],
    '/facialRecognition': ['REGISTER_FACE', 'RESET_APP'],
    '/navigation': [
      'OPEN_NAVIGATION',
      'RESET_APP',
      'START_NAVIGATION',
      'END_NAVIGATION',
      'REPEAT_LAST',
      'ANNOUNCE_LOCATION',
      'ANNOUNCE_WEATHER',
    ],
    '/emergency': ['OPEN_EMERGENCY', 'RESET_APP'],
    '/history': ['OPEN_HISTORY', 'CLEAR_CHAT', 'RESET_APP'],
    '/objectDetection': ['OPEN_OBJECT_DETECTION', 'RESET_APP'],
    '/settings': ['CLEAR_CHAT', 'RESET_APP'],
    '/features': ['EXPLORE_FEATURES', 'RESET_APP'],
    '/aniwaChat': ['RESET_APP', 'CLEAR_CHAT'],
    // Add more screens as needed
  };

  String? _getContextualAction(String command, String currentRoute) {
    final allowedActions = _screenActionMap[currentRoute];
    if (allowedActions == null) return null;

    // Lowercase for easier matching
    final cmd = command.toLowerCase();

    for (final action in allowedActions) {
      switch (action) {
        case 'CAPTURE_TEXT':
          if (RegExp(
            r'\b(take|capture|snap|shoot|picture|scan|read)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'CORRECT_TEXT':
          if (RegExp(r'\b(correct|fix|improve|clean)\b').hasMatch(cmd)) {
            return action;
          }
          break;
        case 'TRANSLATE_TEXT':
          if (RegExp(
            r'\b(translate|convert|change language|in|to)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'SPEAK_TEXT':
          if (RegExp(r'\b(speak|read|say|voice|play)\b').hasMatch(cmd)) {
            return action;
          }
          break;
        case 'SEND_TEXT_TO_CHAT':
          if (RegExp(r'\b(send|add|chat|message|insert)\b').hasMatch(cmd)) {
            return action;
          }
          break;
        case 'DESCRIBE_SCENE':
          if (RegExp(
            r'\b(describe|scene|what\?s? (here|around|this)|see|analyze|analyser)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'SEND_SCENE_TO_CHAT':
          if (RegExp(r'\b(send|add|chat|message|insert)\b').hasMatch(cmd)) {
            return action;
          }
          break;
        case 'SPEAK_SCENE_DESCRIPTION':
          if (RegExp(r'\b(speak|read|say|voice|play)\b').hasMatch(cmd)) {
            return action;
          }
          break;
        case 'REGISTER_FACE':
          if (RegExp(r'\b(register|add|save|capture|face)\b').hasMatch(cmd)) {
            return action;
          }
          break;
        case 'OPEN_NAVIGATION':
          if (RegExp(
            r'\b(navigate|navigation|directions|route|go|travel|map)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'START_NAVIGATION':
          if (RegExp(
            r'\b(start|begin|commence|initiate)\b.*\b(navigation|route|journey|trip)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'END_NAVIGATION':
          if (RegExp(
            r'\b(end|stop|cancel|finish|terminate)\b.*\b(navigation|route|journey|trip)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'REPEAT_LAST':
          if (RegExp(
            r'\b(repeat|again|what did you say|say again)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'ANNOUNCE_LOCATION':
          if (RegExp(
            r'\b(location|where am i|my location|current location|address)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'ANNOUNCE_WEATHER':
          if (RegExp(
            r'\b(weather|forecast|temperature|rain|sunny|cloudy)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'OPEN_EMERGENCY':
          if (RegExp(r'\b(emergency|sos|help|alert)\b').hasMatch(cmd)) {
            return action;
          }
          break;
        case 'OPEN_HISTORY':
          if (RegExp(r'\b(history|past|conversations|logs)\b').hasMatch(cmd)) {
            return action;
          }
          break;
        case 'CLEAR_CHAT':
          if (RegExp(
            r'\b(clear|reset|delete|empty|remove)\b.*\b(chat|history|conversation|messages)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'OPEN_OBJECT_DETECTION':
          if (RegExp(
            r'\b(object|detect|detection|find|recognize)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'OPEN_FACIAL_RECOGNITION':
          if (RegExp(r'\b(face|facial|recognition|identify)\b').hasMatch(cmd)) {
            return action;
          }
          break;
        case 'EXPLORE_FEATURES':
          if (RegExp(
            r'\b(features|explore|menu|options|what can you do)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        case 'RESET_APP':
          if (RegExp(
            r'\b(reset|restart|reboot|start over|fresh)\b',
          ).hasMatch(cmd)) {
            return action;
          }
          break;
        // Add more cases as needed for new actions
      }
    }
    return null;
  }

  String _generateOfflineSpokenResponse(String action, String command) {
    // Generate contextual offline responses
    switch (action) {
      case 'OPEN_TEXT_READER':
        return "Opening text reader. Camera functionality available offline.";
      case 'OPEN_SCENE_DESCRIPTION':
        return "Opening scene description. Basic camera features work offline.";
      case 'OPEN_NAVIGATION':
        return "Opening navigation. Limited features available offline.";
      case 'OPEN_EMERGENCY':
        return "Opening emergency contacts. Stored contacts available offline.";
      case 'OPEN_HISTORY':
        return "Opening chat history. Local history available offline.";
      case 'OPEN_OBJECT_DETECTION':
        return "Opening object detection. Basic detection works offline.";
      case 'OPEN_FACIAL_RECOGNITION':
        return "Opening facial recognition. Stored faces available offline.";
      case 'EXPLORE_FEATURES':
        return "Exploring features. All basic functions work offline.";
      case 'CAPTURE_TEXT':
        return "Capturing text now. OCR processing available offline.";
      case 'DESCRIBE_SCENE':
        return "Analyzing scene. Basic description available offline.";
      case 'SEND_SCENE_TO_CHAT':
        return "Sending to chat. Scene added to local chat history.";
      case 'SPEAK_SCENE_DESCRIPTION':
        return "Speaking scene description using offline voice.";
      case 'CORRECT_TEXT':
        return "Text correction limited while offline, but basic editing available.";
      case 'TRANSLATE_TEXT':
        return "Translation not available offline. Text saved for when online.";
      case 'SPEAK_TEXT':
        return "Speaking text using offline voice synthesis.";
      case 'SEND_TEXT_TO_CHAT':
        return "Sending text to chat. Added to local history.";
      case 'REGISTER_FACE':
        return "Registering face. Stored locally for offline recognition.";
      case 'CLEAR_CHAT':
        return "Clearing chat history. Local data cleared.";
      case 'RESET_APP':
        return "Resetting app. All local settings will be cleared.";
      case 'HELLO':
        return "Hello! I'm working in offline mode with basic features available.";
      case 'TIME':
        return "Current time from device clock: ${TimeOfDay.now().format(NavigationService.navigatorKey.currentContext!)}";
      case 'DATE':
        return "Today's date: ${_formatDateForSpeech(DateTime.now().toLocal().toString().split(' ')[0])}";
      case 'WHO_ARE_YOU':
        return "I'm Assist Lens, running in offline mode with core features available.";
      case 'STATUS':
        return "I'm currently offline but functioning with local capabilities.";
      default:
        return "Processing offline. Some features may be limited.";
    }
  }

  Future<void> _processStructuredCommand(
    String command,
    BuildContext? currentContext,
  ) async {
    if (!await _networkService.checkConnectionAndReturnStatus()) {
      await _processOfflineStructuredCommand(command, currentContext);
      return;
    }

    _logger.i("ChatService: Processing structured command with Gemini");

    final response = await _getGeminiStructuredResponse();
    await _executeStructuredResponse(
      response,
      currentContext,
    ); // Pass context only if needed by handler
  }

  Future<void> _processConversationalCommand(String command) async {
    if (!await _networkService.checkConnectionAndReturnStatus()) {
      await _handleOfflineCommand(command);
      return;
    }

    _logger.i("ChatService: Processing conversational command");

    final response = await _getGeminiConversationalResponse();

    // Extract spokenResponse from JSON (remove code block if present)
    String spokenResponse = response;
    try {
      // Remove markdown code block if present
      final cleaned =
          spokenResponse
              .replaceAll(RegExp(r'^```json', multiLine: true), '')
              .replaceAll(RegExp(r'^```', multiLine: true), '')
              .trim();
      final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(
        json.decode(cleaned),
      );
      spokenResponse = jsonMap['spokenResponse'] ?? response;
    } catch (e) {
      _logger.e("Failed to extract spokenResponse: $e");
      // Fallback to original response
    }

    await onSpeak(spokenResponse);
    onAddAssistantMessage(
      spokenResponse,
    ); // Use callback to add assistant message
    _lastSpokenResponse = spokenResponse;
  }

  Future<Map<String, dynamic>> _getGeminiStructuredResponse() async {
    final systemInstructions = _buildSystemInstructions();
    final messages =
        _historyService
            .getHistory()
            .map(
              (e) => {
                'role': e['role'],
                'parts': [
                  {'text': e['content']},
                ],
              },
            )
            .toList();

    try {
      final geminiResponse = await _geminiService.getChatResponse(
        messages,
        generationConfig: _appActionSchema,
        systemInstruction: systemInstructions,
      );

      return _parseGeminiResponse(geminiResponse);
    } catch (e) {
      _logger.e("ChatService: Gemini structured response failed: $e");
      return _buildFallbackResponse(
        "I'm having trouble processing that request. Please try again.",
      );
    }
  }

  Future<String> _getGeminiConversationalResponse() async {
    final systemInstructions = _buildSystemInstructions();
    final historyForGemini =
        _historyService
            .getHistory()
            .map(
              (e) => {
                'role': e['role'],
                'parts': [
                  {'text': e['content']},
                ],
              },
            )
            .toList();

    try {
      return await _geminiService.getChatResponse(
        historyForGemini,
        systemInstruction: systemInstructions,
      );
    } catch (e) {
      _logger.e("ChatService: Gemini conversational response failed: $e");
      return "I'm having trouble understanding that. Could you please try rephrasing your request?";
    }
  }

  String _buildSystemInstructions() {
    final userInfo = StringBuffer();
    if (_userName != null) {
      userInfo.writeln('- User Name: $_userName');
    }
    userInfo.writeln('- Blind Mode: ${_isBlindMode ? "Enabled" : "Disabled"}');

    return """
You are Aniwa, an AI assistant for a mobile app called Assist Lens, designed for visually impaired users.

**User Info:**
$userInfo

**Core Persona:**
- **Empathetic & Warm:** Always be patient, understanding, and encouraging. Your tone should be friendly and natural, not robotic.
- **Concise & Clear:** Use simple, direct language. Avoid jargon and overly complex sentences. Get to the point, but do it gently.
- **Descriptive:** When appropriate, add sensory details that might be helpful for someone who cannot see.

**Speech Guidelines (VERY IMPORTANT):**
- **Natural Cadence for TTS:** Structure your responses to sound natural when read by a Text-to-Speech (TTS) engine. Use short sentences and paragraphs.
- **Use SSML for Pauses:** To make your speech sound more natural and less rushed, use SSML tags for pauses. Use `<break time="300ms"/>` for a short pause between related ideas, and `<break time="600ms"/>` for a longer pause when changing topics. This is critical for clarity.
- **Wrap all spoken responses in `<speak>` tags.**

**Interaction Logic & Context:**
- **Current Screen:** The user is currently on the '$_currentScreenRoute' screen. Be mindful of this context.
- **General Conversation:** If the user's request is a general question, a chat message, or something that doesn't map to a specific app function, provide a helpful, conversational response. **Your entire response must be wrapped in `<speak>` tags.** Do NOT use JSON for conversational replies.
- **Action-Oriented Commands:** If the user asks to perform a specific app function (like opening a feature, reading text, describing a scene), you MUST respond with a JSON object.

**Contextual Actions:**
- Prioritize actions relevant to the current screen.
- If on '/textReader', use `CAPTURE_TEXT`, `CORRECT_TEXT`, `TRANSLATE_TEXT`, `SPEAK_TEXT`, `SEND_TEXT_TO_CHAT`.
- If on '/sceneDescription', use `DESCRIBE_SCENE`, `SEND_SCENE_TO_CHAT`, `SPEAK_SCENE_DESCRIPTION`.
- If on '/facialRecognition', use `REGISTER_FACE`.
- If on '/settings', use `CLEAR_CHAT` or `RESET_APP`.
- If the user is on a specific screen, prioritize actions relevant to that screen.
- Example 1: If on '/textReader' and user says "take a picture", use the `CAPTURE_TEXT` action.
- Example 2: If on '/settings' and user says "clear my data", use the `CLEAR_CHAT` action.
**Available Actions & Parameters:**
${_appActionSchema['responseSchema']['properties']['action']['enum'].join(', ')}

**Response Format for Actions:**
When the user requests a specific app function, respond with a JSON object containing:
- `action`: The appropriate action from the enum above
- `spokenResponse`: What you want to say to the user (wrapped in `<speak>` tags with SSML)
- `parameters`: Optional object with relevant parameters
- `confidence`: Your confidence level (0.0 to 1.0)

**Offline Mode Handling:**
- When offline, inform users about limitations but emphasize available features
- Prioritize local functionality (camera, stored data, basic processing)
- Be encouraging about what CAN be done offline

**Examples:**
1. User: "Hello" → Conversational response in `<speak>` tags
2. User: "Open text reader" → JSON with action "OPEN_TEXT_READER"
3. User: "What can you see?" → JSON with action "DESCRIBE_SCENE" (if on scene screen)

Be helpful, warm, and always consider the user's visual impairment in your responses.""";
  }

  Map<String, dynamic> _parseGeminiResponse(String response) {
    try {
      final decoded = jsonDecode(response);

      // Validate required fields
      if (!decoded.containsKey('action') ||
          !decoded.containsKey('spokenResponse')) {
        throw Exception('Missing required fields in Gemini response');
      }

      // Ensure spokenResponse is wrapped in SSML speak tags
      String spokenResponse = decoded['spokenResponse'];
      if (!spokenResponse.startsWith('<speak>')) {
        spokenResponse = '<speak>$spokenResponse</speak>';
      }

      return {
        'action': decoded['action'] ?? 'NONE',
        'spokenResponse': spokenResponse,
        'parameters': decoded['parameters'] ?? {},
        'confidence': decoded['confidence'] ?? 0.8,
      };
    } catch (e) {
      _logger.e("ChatService: Failed to parse Gemini response: $e");
      return _buildFallbackResponse(
        "I'm having trouble understanding that request.",
      );
    }
  }

  Map<String, dynamic> _buildFallbackResponse(String message) {
    return {
      'action': 'NONE',
      'spokenResponse':
          '<speak>$message <break time="300ms"/> Please try again.</speak>',
      'parameters': {},
      'confidence': 0.5,
    };
  }

  Future<void> _executeStructuredResponse(
    Map<String, dynamic> response,
    BuildContext? currentContext,
  ) async {
    final action = response['action'] as String?;
    final spokenResponse = response['spokenResponse'] as String?;
    // Fix: Safely cast parameters to Map<String, dynamic>
    final parametersRaw = response['parameters'];
    final parameters =
        parametersRaw is Map<String, dynamic>
            ? parametersRaw
            : Map<String, dynamic>.from(parametersRaw as Map);

    _logger.i("ChatService: Executing structured action: $action");

    // Speak the response first
    if (spokenResponse != null) {
      await onSpeak(spokenResponse);
      onAddAssistantMessage(_extractTextFromSSML(spokenResponse));
      _lastSpokenResponse = spokenResponse;
    }

    // Execute the action if it's not NONE
    if (action != null && action != 'NONE') {
      final handler = _intentActionMap[action];
      if (handler != null) {
        await handler.execute(currentContext, '', parameters);
      } else {
        _logger.w("ChatService: No handler found for action: $action");
      }
    }
  }

  String _extractTextFromSSML(String ssmlText) {
    // Remove SSML tags to get clean text for history
    return ssmlText
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _handleOfflineCommand(String command) async {
    _logger.i("ChatService: Handling offline command: '$command'");

    final offlineResponses = [
      '<speak>I\'m currently offline, <break time="300ms"/> but I can still help with basic features. <break time="600ms"/> What would you like me to do?</speak>',
      '<speak>Working in offline mode. <break time="300ms"/> Camera, stored data, and local features are available. <break time="600ms"/> How can I assist you?</speak>',
      '<speak>I\'m offline right now, <break time="300ms"/> but many features still work locally. <break time="600ms"/> Try asking me to open a feature or describe what you need.</speak>',
    ];

    final response =
        offlineResponses[DateTime.now().millisecond % offlineResponses.length];
    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  Future<void> _handleProcessingError(dynamic error) async {
    String errorResponse;

    if (!await _networkService.checkConnectionAndReturnStatus()) {
      errorResponse =
          '<speak>I\'m having trouble processing that while offline. <break time="300ms"/> Please try a simpler command or check your connection.</speak>';
    } else {
      errorResponse =
          '<speak>Sorry, I encountered an error. <break time="300ms"/> Please try again or rephrase your request.</speak>';
    }

    await onSpeak(errorResponse);
    onAddAssistantMessage(_extractTextFromSSML(errorResponse));
    _lastSpokenResponse = errorResponse;
  }

  // Direct command handlers - these work both online and offline
  Future<void> _handleGreeting(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    final greetings = [
      '<speak>Hello! <break time="300ms"/> I\'m Aniwa, your assistant. <break time="600ms"/> How can I help you today?</speak>',
      '<speak>Hi there! <break time="300ms"/> Ready to assist you. <break time="600ms"/> What would you like to do?</speak>',
      '<speak>Good to hear from you! <break time="300ms"/> I\'m here to help. <break time="600ms"/> What can I do for you?</speak>',
    ];

    final response = greetings[DateTime.now().millisecond % greetings.length];
    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  Future<void> _handleSelfIntro(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    final isOnline = await _networkService.checkConnectionAndReturnStatus();
    final modeText =
        isOnline ? 'online with full features' : 'offline with core features';

    final response =
        '<speak>I\'m Aniwa, <break time="300ms"/> your AI assistant for Assist Lens. <break time="600ms"/> I\'m currently $modeText available. <break time="600ms"/> I can help you navigate the app, <break time="300ms"/> read text, <break time="300ms"/> describe scenes, <break time="300ms"/> and much more.</speak>';

    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  Future<void> _handleCapabilities(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    final isOnline = await _networkService.checkConnectionAndReturnStatus();

    String response;
    if (isOnline) {
      response =
          '<speak>I can help you with many things! <break time="600ms"/> I can read text from images, <break time="300ms"/> describe your surroundings, <break time="300ms"/> recognize faces, <break time="300ms"/> provide navigation help, <break time="300ms"/> and have conversations with you. <break time="600ms"/> Just tell me what you need!</speak>';
    } else {
      response =
          '<speak>While offline, I can still help with core features! <break time="600ms"/> I can capture and read text, <break time="300ms"/> provide basic scene descriptions, <break time="300ms"/> access stored faces, <break time="300ms"/> and use camera functions. <break time="600ms"/> Many features work without internet!</speak>';
    }

    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  Future<void> _handleHowAreYou(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    final isOnline = await _networkService.checkConnectionAndReturnStatus();
    final statusText =
        isOnline
            ? 'working perfectly with full online capabilities'
            : 'doing well in offline mode';

    final response =
        '<speak>I\'m $statusText! <break time="600ms"/> Ready to help you with whatever you need. <break time="600ms"/> How are you doing today?</speak>';

    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  Future<void> _handleTime(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    // Use device time - works offline
    final now = TimeOfDay.now();
    final formattedTime =
        context != null
            ? now.format(context)
            : '${now.hour}:${now.minute.toString().padLeft(2, '0')}';

    final response =
        '<speak>The current time is <break time="300ms"/> $formattedTime.</speak>';

    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  Future<void> _handleDate(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    // Use device date - works offline
    final now = DateTime.now();
    final formattedDate = _formatDateForSpeech(
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
    );

    final response =
        '<speak>Today is <break time="300ms"/> $formattedDate.</speak>';

    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  Future<void> _handleOnlineStatus(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    final isOnline = await _networkService.checkConnectionAndReturnStatus();

    String response;
    if (isOnline) {
      response =
          '<speak>I\'m online and all features are available! <break time="600ms"/> Connection is strong and ready for advanced tasks.</speak>';
    } else {
      response =
          '<speak>I\'m currently offline, <break time="300ms"/> but core features are still working. <break time="600ms"/> Camera, stored data, and basic functions are available.</speak>';
    }

    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  Future<void> _handleStopSpeaking(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    await _speechService.stopSpeaking();
    // Don't add this to chat history as it's a control command
  }

  Future<void> _handleRepeatLast(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    if (_lastSpokenResponse.isNotEmpty) {
      await onSpeak(_lastSpokenResponse);
    } else {
      final response =
          '<speak>I haven\'t said anything yet. <break time="300ms"/> How can I help you?</speak>';
      await onSpeak(response);
      onAddAssistantMessage(_extractTextFromSSML(response));
      _lastSpokenResponse = response;
    }
  }

  Future<void> _handleVolumeUp(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    // This would typically interface with system volume or TTS volume
    final response =
        '<speak>Volume increased. <break time="300ms"/> Is this better?</speak>';
    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  Future<void> _handleVolumeDown(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    // This would typically interface with system volume or TTS volume
    final response =
        '<speak>Volume decreased. <break time="300ms"/> Can you hear me clearly?</speak>';
    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  // Feature navigation handlers
  Future<void> _handleOpenTextReader(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    onNavigate('/textReader');
    onVibrate();
  }

  Future<void> _handleOpenSceneDescription(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    onNavigate('/sceneDescription');
    onVibrate();
  }

  Future<void> _handleOpenNavigation(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    onNavigate('/navigation');
    onVibrate();
  }

  Future<void> _handleOpenEmergency(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    onNavigate('/emergency');
    onVibrate();
  }

  Future<void> _handleOpenHistory(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    onNavigate('/history');
    onVibrate();
  }

  Future<void> _handleOpenObjectDetection(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    onNavigate('/objectDetection');
    onVibrate();
  }

  Future<void> _handleOpenFacialRecognition(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    onNavigate('/facialRecognition');
    onVibrate();
  }

  Future<void> _handleExploreFeatures(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    onNavigate('/features');
    onVibrate();
  }

  // Feature-specific action handlers (these would integrate with respective services)
  Future<void> _handleCaptureText(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    // This would trigger text capture in the current context or navigate to text reader
    if (_currentScreenRoute == '/textReader') {
      // Trigger capture action in text reader
      // This would be handled by the TextReaderState
      onVibrate();
    } else {
      onNavigate('/textReader', arguments: {'autoCapture': true});
      onVibrate();
    }
  }

  Future<void> _handleDescribeScene(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    if (_currentScreenRoute == '/sceneDescription') {
      // Trigger scene description
      onVibrate();
    } else {
      onNavigate('/sceneDescription', arguments: {'autoDescribe': true});
      onVibrate();
    }
  }

  Future<void> _handleSendSceneToChat(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    // This would get the current scene description and add it to chat
    // Implementation depends on how scene data is managed
    onVibrate();
  }

  Future<void> _handleSpeakSceneDescription(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    // This would speak the current scene description
    // Implementation depends on scene description service
    onVibrate();
  }

  Future<void> _handleCorrectText(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    // Text correction functionality
    onVibrate();
  }

  Future<void> _handleTranslateText(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    final isOnline = await _networkService.checkConnectionAndReturnStatus();
    if (!isOnline) {
      final response =
          '<speak>Translation requires an internet connection. <break time="300ms"/> Text saved for when you\'re back online.</speak>';
      await onSpeak(response);
      onAddAssistantMessage(_extractTextFromSSML(response));
    } else {
      onVibrate();
      // Proceed with translation
    }
  }

  Future<void> _handleSpeakText(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    // Speak current text - works offline
    onVibrate();
  }

  Future<void> _handleSendTextToChat(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    // Send current text to chat history
    onVibrate();
  }

  Future<void> _handleRegisterFace(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    if (_currentScreenRoute == '/facialRecognition') {
      // Trigger face registration
      onVibrate();
    } else {
      onNavigate('/facialRecognition', arguments: {'autoRegister': true});
      onVibrate();
    }
  }

  Future<void> _handleClearChat(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    _historyService.clearHistory();
    onVibrate();

    final response =
        '<speak>Chat history cleared. <break time="300ms"/> Starting fresh!</speak>';
    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  Future<void> _handleResetApp(
    BuildContext? context,
    String command,
    Map<String, dynamic> parameters,
  ) async {
    // This would trigger app reset functionality
    onVibrate();

    final response =
        '<speak>App reset initiated. <break time="300ms"/> All settings will be restored to defaults.</speak>';
    await onSpeak(response);
    onAddAssistantMessage(_extractTextFromSSML(response));
    _lastSpokenResponse = response;
  }

  // Utility methods
  String _formatDateForSpeech(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];

      final weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];

      final weekday = weekdays[date.weekday - 1];
      final month = months[date.month - 1];
      final day = date.day;
      final year = date.year;

      return '$weekday, $month $day, $year';
    } catch (e) {
      _logger.e("ChatService: Date formatting error: $e");
      return dateString;
    }
  }

  // Cleanup method
  void dispose() {
    _processingTimeoutTimer?.cancel();
  }

  // Public methods for external state management
  bool get isProcessing => _isProcessingCommand;
  String get lastSpokenResponse => _lastSpokenResponse;
  String? get currentScreenRoute => _currentScreenRoute;

  // Method to update context data from other services
  void updateContextData(String key, dynamic value) {
    _contextData[key] = value;
    _logger.i("ChatService: Updated context data - $key: $value");
  }

  // Method to get context data
  dynamic getContextData(String key) {
    return _contextData[key];
  }
}
