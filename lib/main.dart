// main.dart
import 'package:assist_lens/core/services/face_database_helper.dart' show FaceDatabaseHelper;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:vibration/vibration.dart'; // Added for vibration

// Import your services
import 'core/routing/app_router.dart';
import 'core/services/network_service.dart';
import 'core/services/speech_service.dart';
import 'core/services/gemini_service.dart';
import 'core/services/face_recognizer_service.dart';
import 'core/services/text_reader_service.dart';
import 'core/services/history_services.dart';
import 'core/services/chat_service.dart';
import 'core/services/speech_service.dart' show PorcupineInitializationException; // Import the custom exception
import 'core/services/camera_service.dart'; // NEW: Import CameraService

// Import your pages/states
import 'state/app_state.dart';
import 'features/aniwa_chat/state/chat_state.dart';
import 'features/face_recognition/facial_recognition_state.dart';
import 'features/scene_description/scene_description_state.dart';
import 'features/emergency/emergency_state.dart';
import 'features/text_reader/text_reader_state.dart';

// Global logger instance
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.none,
  ),
);

// Global RouteObserver for navigation awareness
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// Global Key for NavigatorState to allow navigation from anywhere in the app
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Main entry point for the Assist Lens application.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool criticalServicesInitialized = true;

  try {
    final prefs = await SharedPreferences.getInstance();

    // Initialize Firebase
    await Firebase.initializeApp(
      name: 'assist_lens',
      options: const FirebaseOptions(
        apiKey: 'YOUR_API_KEY', // Replace with your actual API Key
        appId: 'YOUR_APP_ID', // Replace with your actual App ID
        messagingSenderId:
            'YOUR_MESSAGING_SENDER_ID', // Replace with your actual Messaging Sender ID
        projectId: 'YOUR_PROJECT_ID', // Replace with your actual Project ID
      ),
    );

    // Initialize core services
    final networkService = NetworkService();
    await networkService.init();

    final speechService = SpeechService();
    try {
      await speechService.init(); // Initialize speech service here
    } on PorcupineInitializationException catch (e) { // Catch specific exception
      logger.f("FATAL: Wake Word (Porcupine) initialization failed: $e. Application will not start.");
      criticalServicesInitialized = false;
      rethrow; // Rethrow to cause a crash or halt
    }


    final historyService = HistoryService(prefs);
    await historyService.init();

    final geminiService = GeminiService(networkService);
    final faceDatabaseHelper = FaceDatabaseHelper(); // Instantiate FaceDatabaseHelper
    final faceRecognizerService = FaceRecognizerService(
        faceDatabaseHelper: faceDatabaseHelper); // Provide DB helper here
    final textReaderService = TextReaderServices();
    final cameraService = CameraService(); // NEW: Initialize CameraService
    // Load face recognition model on startup
    await faceRecognizerService.loadModel();
    
    if (criticalServicesInitialized) {
      runApp(
        MultiProvider(
          providers: [
            // Core app state
            ChangeNotifierProvider<AppState>(create: (_) => AppState(prefs)),

            // Core services
            ChangeNotifierProvider<NetworkService>.value(value: networkService),
            ChangeNotifierProvider<SpeechService>.value(value: speechService),
            ChangeNotifierProvider<HistoryService>.value(value: historyService),
            Provider<GeminiService>.value(value: geminiService),
            Provider<FaceRecognizerService>.value(value: faceRecognizerService),
            Provider<TextReaderServices>.value(value: textReaderService),
            ChangeNotifierProvider<CameraService>.value(
              value: cameraService,
            ), // NEW: Provide CameraService
            Provider<FaceDatabaseHelper>.value(
                value: faceDatabaseHelper), // Provide FaceDatabaseHelper
            // Chat state with proper dependency injection
            ChangeNotifierProvider<ChatState>(
              create: (context) {
                final speech = context.read<SpeechService>();
                final gemini = context.read<GeminiService>();
                final history = context.read<HistoryService>();
                final network = context.read<NetworkService>();

                final chatState = ChatState(speech, gemini, history, network);

                // Set the navigation callback for ChatState
                chatState.onNavigateRequested = (routeName, {arguments}) {
                  if (navigatorKey.currentState != null &&
                      navigatorKey.currentState!.mounted) {
                    navigatorKey.currentState!.pushNamed(
                      routeName,
                      arguments: arguments,
                    );
                  } else {
                    logger.w(
                      "Navigator state not available for navigation to $routeName.",
                    );
                  }
                };

                // Initialize ChatService with proper callbacks AFTER ChatState is created
                chatState.chatService = ChatService(
                  speech,
                  gemini,
                  history,
                  network,
                  onProcessingStatusChanged: chatState.setIsProcessingAI,
                  onSpeak: chatState.speak,
                  onVibrate: () async {
                    if (await Vibration.hasVibrator() ?? false) {
                      Vibration.vibrate(duration: 50);
                    }
                  },
                  // The onNavigate for ChatService should call ChatState's navigateTo method
                  onNavigate: chatState.navigateTo,
                  onAddUserMessage:
                      chatState.addUserMessage, // Pass callback for user messages
                  onAddAssistantMessage:
                      chatState
                          .addAssistantMessage, // Pass callback for assistant messages
                );

                return chatState;
              },
            ),

            // Feature states
            ChangeNotifierProvider<FacialRecognitionState>(
              create:
                  (context) => FacialRecognitionState(
                    networkService: context.read<NetworkService>(),
                    speechService: context.read<SpeechService>(),
                    faceRecognizerService: context.read<FaceRecognizerService>(),
                    cameraService:
                        context
                            .read<CameraService>(), 
                    faceDatabaseHelper:context.read<FaceDatabaseHelper>() , // NEW: Inject CameraService
                  ),
            ),
            ChangeNotifierProvider<SceneDescriptionState>(
              create:
                  (context) => SceneDescriptionState(
                    context.read<NetworkService>(),
                    context.read<SpeechService>(), // NEW: Inject CameraService
                    context.read<GeminiService>(),
                    context.read<CameraService>(),
                  ),
            ),
            ChangeNotifierProvider<EmergencyState>(
              create: (_) => EmergencyState(),
            ),
            ChangeNotifierProvider<TextReaderState>(
              create:
                  (context) => TextReaderState(
                    speechService: context.read<SpeechService>(),
                    geminiService: context.read<GeminiService>(),
                    networkService: context.read<NetworkService>(),
                    historyService: context.read<HistoryService>(),
                    textReaderService: context.read<TextReaderServices>(),
                    cameraService:
                        context
                            .read<CameraService>(), // NEW: Inject CameraService
                  ),
            ),
          ],
          child: const AssistLensApp(),
        ),
      );
    } else {
      // If critical services failed, run the ErrorApp or simply don't run the main app.
      // The rethrow should ideally handle the "crush" part.
      logger.f("Not running AssistLensApp due to critical initialization failure.");
      runApp(const ErrorApp(message: "Critical component (Wake Word) failed to initialize. App cannot start."));
    }
  } catch (e, s) { // Catch any exception from the main try block, including rethrown ones
    logger.f('FATAL: Unhandled exception during app initialization: $e', error: e, stackTrace: s);
    // You might want to show an error screen here
    runApp(ErrorApp(message: "A critical error occurred during app startup: $e"));
  }
}

/// Error app to show when initialization fails
class ErrorApp extends StatelessWidget {
  final String message;
  const ErrorApp({super.key, this.message = "An unknown error occurred."});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Failed to initialize app',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // You could implement app restart logic here
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom theme extension for chat-specific colors
class ChatThemeExtension extends ThemeExtension<ChatThemeExtension> {
  const ChatThemeExtension({
    required this.chatBackground,
    required this.userMessageGradient,
    required this.aiMessageBackground,
    required this.aiAvatarGradient,
    required this.userAvatarGradient,
    required this.speakingGradient,
    required this.inputBackground,
    required this.inputBorder,
    required this.focusedInputBorder,
    required this.sendButtonGradient,
    required this.wakeWordColor,
    required this.statusColors,
  });

  final LinearGradient chatBackground;
  final LinearGradient userMessageGradient;
  final Color aiMessageBackground;
  final LinearGradient aiAvatarGradient;
  final LinearGradient userAvatarGradient;
  final LinearGradient speakingGradient;
  final Color inputBackground;
  final Color inputBorder;
  final Color focusedInputBorder;
  final LinearGradient sendButtonGradient;
  final Color wakeWordColor;
  final StatusColors statusColors;

  @override
  ChatThemeExtension copyWith({
    LinearGradient? chatBackground,
    LinearGradient? userMessageGradient,
    Color? aiMessageBackground,
    LinearGradient? aiAvatarGradient,
    LinearGradient? userAvatarGradient,
    LinearGradient? speakingGradient,
    Color? inputBackground,
    Color? inputBorder,
    Color? focusedInputBorder,
    LinearGradient? sendButtonGradient,
    Color? wakeWordColor,
    StatusColors? statusColors,
  }) {
    return ChatThemeExtension(
      chatBackground: chatBackground ?? this.chatBackground,
      userMessageGradient: userMessageGradient ?? this.userMessageGradient,
      aiMessageBackground: aiMessageBackground ?? this.aiMessageBackground,
      aiAvatarGradient: aiAvatarGradient ?? this.aiAvatarGradient,
      userAvatarGradient: userAvatarGradient ?? this.userAvatarGradient,
      speakingGradient: speakingGradient ?? this.speakingGradient,
      inputBackground: inputBackground ?? this.inputBackground,
      inputBorder: inputBorder ?? this.inputBorder,
      focusedInputBorder: focusedInputBorder ?? this.focusedInputBorder,
      sendButtonGradient: sendButtonGradient ?? this.sendButtonGradient,
      wakeWordColor: wakeWordColor ?? this.wakeWordColor,
      statusColors: statusColors ?? this.statusColors,
    );
  }

  @override
  ChatThemeExtension lerp(ChatThemeExtension? other, double t) {
    if (other is! ChatThemeExtension) {
      return this;
    }
    return ChatThemeExtension(
      chatBackground:
          LinearGradient.lerp(chatBackground, other.chatBackground, t)!,
      userMessageGradient:
          LinearGradient.lerp(
            userMessageGradient,
            other.userMessageGradient,
            t,
          )!,
      aiMessageBackground:
          Color.lerp(aiMessageBackground, other.aiMessageBackground, t)!,
      aiAvatarGradient:
          LinearGradient.lerp(aiAvatarGradient, other.aiAvatarGradient, t)!,
      userAvatarGradient:
          LinearGradient.lerp(userAvatarGradient, other.userAvatarGradient, t)!,
      speakingGradient:
          LinearGradient.lerp(speakingGradient, other.speakingGradient, t)!,
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      inputBorder: Color.lerp(inputBorder, other.inputBorder, t)!,
      focusedInputBorder:
          Color.lerp(focusedInputBorder, other.focusedInputBorder, t)!,
      sendButtonGradient:
          LinearGradient.lerp(sendButtonGradient, other.sendButtonGradient, t)!,
      wakeWordColor: Color.lerp(wakeWordColor, other.wakeWordColor, t)!,
      statusColors: StatusColors.lerp(statusColors, other.statusColors, t),
    );
  }
}

// Status colors for different chat states
class StatusColors {
  const StatusColors({
    required this.thinking,
    required this.speaking,
    required this.listening,
    required this.wakeWord,
    required this.ready,
  });

  final Color thinking;
  final Color speaking;
  final Color listening;
  final Color wakeWord;
  final Color ready;

  static StatusColors lerp(StatusColors a, StatusColors b, double t) {
    return StatusColors(
      thinking: Color.lerp(a.thinking, b.thinking, t)!,
      speaking: Color.lerp(a.speaking, b.speaking, t)!,
      listening: Color.lerp(a.listening, b.listening, t)!,
      wakeWord: Color.lerp(a.wakeWord, b.wakeWord, t)!,
      ready: Color.lerp(a.ready, b.ready, t)!,
    );
  }
}

class AssistLensApp extends StatefulWidget {
  const AssistLensApp({super.key});

  @override
  State<AssistLensApp> createState() => _AssistLensAppState();
}

class _AssistLensAppState extends State<AssistLensApp> {
  ThemeMode _themeMode = ThemeMode.system; // Default to system theme

  void toggleTheme() {
    setState(() {
      _themeMode = switch (_themeMode) {
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
        ThemeMode.system => ThemeMode.light,
      };
      logger.i('Theme changed to $_themeMode');
    });
  }

  // Define light theme colors matching the image with chat theme extensions
  final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF4A65FB),
      onPrimary: Colors.white,
      secondary: Color(0xFF00BFA5),
      onSecondary: Colors.white,
      tertiary: Color(0xFF7D59F0),
      onTertiary: Colors.white,
      surface: Color(0xFFF7F7F7),
      onSurface: Color(0xFF34495E),
      primaryContainer: Color(0xFFE0E6FD),
      onPrimaryContainer: Color(0xFF2C3E50),
      secondaryContainer: Color(0xFFC3B0FB),
      onSecondaryContainer: Color(0xFF2C3E50),
      error: Colors.redAccent,
      onError: Colors.white,
      shadow: Color(0xFF000000), // Light gradient equivalent
      onSurfaceVariant: Color(0xFF2C3E50),
      // Added missing colors to match potential usage
      surfaceContainerHigh: Color(0xFFE0E0E0), // Example light color
      surfaceContainerHighest: Color(0xFFD0D0D0), // Example light color
      tertiaryContainer: Color(
        0xFFEBE0FF,
      ), // Example light color for tertiary container
    ),
    extensions: const [
      ChatThemeExtension(
        chatBackground: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8F4FD), // Light blue
            Color(0xFFF0F0FF), // Light purple-white
            Color(0xFFE8E4FF), // Light purple
          ],
          stops: [0.0, 0.6, 1.0],
        ),
        userMessageGradient: LinearGradient(
          colors: [Color(0xFF4A65FB), Color(0xFF7D59F0)],
        ),
        aiMessageBackground: Color(0xFFFFFFFF),
        aiAvatarGradient: LinearGradient(
          colors: [Color(0xFF7D59F0), Color(0xFFE91E63)],
        ),
        userAvatarGradient: LinearGradient(
          colors: [Color(0xFF4A65FB), Color(0xFF00BFA5)],
        ),
        speakingGradient: LinearGradient(
          colors: [Color(0xFF7D59F0), Color(0xFF4A65FB), Color(0xFF00BFA5)],
        ),
        inputBackground: Color(0xFFFFFFFF),
        inputBorder: Color(0xFFE0E6FD),
        focusedInputBorder: Color(0xFF4A65FB),
        sendButtonGradient: LinearGradient(
          colors: [Color(0xFF4A65FB), Color(0xFF7D59F0)],
        ),
        wakeWordColor: Color(0xFF7D59F0),
        statusColors: StatusColors(
          thinking: Color(0xFFFFC107),
          speaking: Color(0xFF4CAF50),
          listening: Color(0xFF4A65FB),
          wakeWord: Color(0xFF7D59F0),
          ready: Color(0xFF9E9E9E),
        ),
      ),
    ],
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF7F7F7),
      foregroundColor: Color(0xFF2C3E50),
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Color(0xFF2C3E50),
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardTheme(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      shadowColor: Colors.grey.withOpacity(0.1),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2C3E50),
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Color(0xFF2C3E50),
      ),
      bodyMedium: TextStyle(fontSize: 16, color: Color(0xFF2C3E50)),
      bodySmall: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF4A65FB),
      ),
    ),
    shadowColor: Colors.black,
  );

  // Define dark theme colors complementing the chat screen
  final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF4A65FB),
      onPrimary: Colors.white,
      secondary: Color(0xFF00BFA5),
      onSecondary: Colors.white,
      tertiary: Color(0xFF7D59F0),
      onTertiary: Colors.white,
      surface: Color(0xFF0A0E1A), // Dark chat background
      onSurface: Colors.white70,
      primaryContainer: Color(0xFF1A1F3A),
      onPrimaryContainer: Colors.white,
      secondaryContainer: Color(0xFF2D1B69),
      onSecondaryContainer: Colors.white,
      error: Colors.redAccent,
      onError: Colors.white,
      shadow: Color(0xFF000000),
      onSurfaceVariant: Colors.white70,
      // Added missing colors to match potential usage
      surfaceContainerHigh: Color(0xFF2A2E4A), // Example dark color
      surfaceContainerHighest: Color(0xFF3A3E5A), // Example dark color
      tertiaryContainer: Color(
        0xFF4D3A8A,
      ), // Example dark color for tertiary container
    ),
    extensions: const [
      ChatThemeExtension(
        chatBackground: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A0E1A), // Dark blue-black
            Color(0xFF1A1F3A), // Medium dark blue
            Color(0xFF2D1B69), // Dark purple
          ],
          stops: [0.0, 0.6, 1.0],
        ),
        userMessageGradient: LinearGradient(
          colors: [Color(0xFF4A65FB), Color(0xFF7D59F0)],
        ),
        aiMessageBackground: Color(0x1AFFFFFF), // 10% white opacity
        aiAvatarGradient: LinearGradient(
          colors: [Color(0xFF7D59F0), Color(0xFFE91E63)],
        ),
        userAvatarGradient: LinearGradient(
          colors: [Color(0xFF4A65FB), Color(0xFF00BFA5)],
        ),
        speakingGradient: LinearGradient(
          colors: [Color(0xFF7D59F0), Color(0xFF4A65FB), Color(0xFF00BFA5)],
        ),
        inputBackground: Color(0x1AFFFFFF), // 10% white opacity
        inputBorder: Color(0x33FFFFFF), // 20% white opacity
        focusedInputBorder: Color(0x80_4A65FB), // 50% opacity blue
        sendButtonGradient: LinearGradient(
          colors: [Color(0xFF4A65FB), Color(0xFF7D59F0)],
        ),
        wakeWordColor: Color(0xFF7D59F0),
        statusColors: StatusColors(
          thinking: Color(0xFFFFC107),
          speaking: Color(0xFF4CAF50),
          listening: Color(0xFF4A65FB),
          wakeWord: Color(0xFFBA68C8), // Light purple
          ready: Color(0xFF9E9E9E),
        ),
      ),
    ],
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF0A0E1A),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardTheme(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF1A1F3A),
      shadowColor: Colors.white.withOpacity(0.05),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      bodyMedium: TextStyle(fontSize: 16, color: Colors.white70),
      bodySmall: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    shadowColor: Colors.black,
  );

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return ThemeProvider(
          themeMode: _themeMode,
          toggleTheme: toggleTheme,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Assist Lens',
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: _themeMode,
            // Set the global navigatorKey here
            navigatorKey: navigatorKey,
            // Directly route to HomePage instead of MainAppWrapper
            initialRoute:
                appState.onboardingComplete
                    ? AppRouter.mainAppWrapper
                    : AppRouter.onboarding,
            onGenerateRoute: AppRouter.onGenerateRoute,
            navigatorObservers: [routeObserver],
          ),
        );
      },
    );
  }
}

class ThemeProvider extends InheritedWidget {
  final ThemeMode themeMode;
  final VoidCallback toggleTheme;

  const ThemeProvider({
    super.key,
    required this.themeMode,
    required this.toggleTheme,
    required super.child,
  });

  static ThemeProvider of(BuildContext context) {
    final ThemeProvider? result =
        context.dependOnInheritedWidgetOfExactType<ThemeProvider>();
    assert(result != null, 'No ThemeProvider found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(ThemeProvider oldWidget) {
    return oldWidget.themeMode != themeMode;
  }
}
