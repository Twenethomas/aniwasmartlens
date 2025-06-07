// lib/main.dart
import 'package:assist_lens/features/explore_features_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

// Import your services
import 'core/routing/app_router.dart'; // Import the new AppRouter
import 'core/services/network_service.dart';
import 'core/services/speech_service.dart';
import 'core/services/gemini_service.dart'; // Changed from azure_gpt_service.dart to gemini_service.dart
import 'core/services/face_recognizer_service.dart'; // NEW: Import FaceRecognizerService
import 'features/aniwa_chat/state/chat_state.dart'; // Import the new ChatState
import 'features/aniwa_chat/aniwa_chat_page.dart'; // Still needed for _pages in MainAppWrapper
// Import your pages
import 'state/app_state.dart';
import './features/home/home_page.dart';
import './features/face_recognition/facial_recognition_state.dart'; // Import FacialRecognitionState
import './features/scene_description/scene_description_state.dart'; // Import SceneDescriptionState
import './features/emergency/emergency_state.dart'; // Import EmergencyState
import './features/text_reader/text_reader_state.dart'; // Import TextReaderState
import './core/services/history_services.dart';
import './core/services/chat_service.dart'; // Import ChatService

// Global logger instance
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 2, // number of method calls to be displayed
    errorMethodCount: 8, // number of method calls if stacktrace is provided
    lineLength: 120, // width of the output
    colors: true, // Colorful log messages
    printEmojis: true, // Print an emoji for each log message
    dateTimeFormat: DateTimeFormat.none, // Use this instead of printTime, which is deprecated
  ),
);

// Global RouteObserver for navigation awareness
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

/// Main entry point for the Assist Lens application.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  await Firebase.initializeApp(
    name: 'assist_lens', // Use the name from your Firebase project
    options: const FirebaseOptions(
      apiKey: 'YOUR_API_KEY', // IMPORTANT: Replace with your actual Firebase API Key
      appId: 'YOUR_APP_ID', // IMPORTANT: Replace with your actual Firebase App ID
      messagingSenderId: 'YOUR_MESSAGING_SENDER_ID', // IMPORTANT: Replace with your actual Firebase Messaging Sender ID
      projectId: 'YOUR_PROJECT_ID', // IMPORTANT: Replace with your actual Firebase Project ID
    ),
  );

  // Initialize core services
  final networkService = NetworkService();
  await networkService.init(); // Check initial connectivity

  final speechService = SpeechService();
  await speechService.init(); // Initialize TTS, STT, and Porcupine

  final historyService = HistoryService(prefs); // Pass prefs to HistoryService
  await historyService.init(); // Initialize HistoryService

  // Initialize GeminiService, injecting NetworkService
  final geminiService = GeminiService(networkService); // Use GeminiService instead of AzureGptService

  // Initialize FaceRecognizerService (singleton)
  final faceRecognizerService = FaceRecognizerService();
  await faceRecognizerService.loadModel(); // Ensure model is loaded on app start

  runApp(
    MultiProvider(
      providers: [
        // AppState is a ChangeNotifier and uses SharedPreferences
        ChangeNotifierProvider<AppState>.value(
          value: AppState(prefs),
        ), // Initialize AppState with prefs
        // NetworkService is a ChangeNotifier
        ChangeNotifierProvider<NetworkService>.value(value: networkService),

        // SpeechService is now a ChangeNotifier, use ChangeNotifierProvider.value
        ChangeNotifierProvider<SpeechService>.value(value: speechService),

        // GeminiService is not a ChangeNotifier but is a singleton, use Provider.value
        Provider<GeminiService>.value(value: geminiService), // Use GeminiService

        // HistoryService is a ChangeNotifier
        ChangeNotifierProvider<HistoryService>.value(value: historyService),

        // FaceRecognizerService is a singleton. Provide its instance.
        Provider<FaceRecognizerService>.value(value: faceRecognizerService), // NEW: Provide FaceRecognizerService

        // Provide ChatState and its dependencies. ChatService is created here.
        ChangeNotifierProvider<ChatState>(
          create: (context) {
            final speech = context.read<SpeechService>();
            final gemini = context.read<GeminiService>(); // Use GeminiService
            final history = context.read<HistoryService>();
            final network = context.read<NetworkService>();

            // Create ChatState first, then provide its callbacks to ChatService
            final chatState = ChatState(speech, gemini, history, network);

            // Now create ChatService using the ChatState's methods as callbacks
            final chatService = ChatService(
              speech,
              gemini,
              history,
              network,
              onHistoryUpdated: chatState.updateHistory,
              onProcessingStatusChanged: chatState.setIsProcessingAI,
              onSpeak: chatState.speak,
              onVibrate: chatState.vibrate,
              onNavigate: chatState.navigateTo, // Pass chatState.navigateTo
            );
            // Assign the created chatService to ChatState if it needs it internally
            chatState.chatService = chatService; // Assuming you add this setter in ChatState
            return chatState;
          },
        ),

        // Provide ChatService explicitly for other parts of the app to read if needed,
        // although ChatState now manages its creation and internal use.
        Provider<ChatService>(
          create: (context) {
            return ChatService(
              context.read<SpeechService>(),
              context.read<GeminiService>(), // Use GeminiService
              context.read<HistoryService>(),
              context.read<NetworkService>(),
              onHistoryUpdated: (history) {},
              onProcessingStatusChanged: (status) {},
              onSpeak: (text) async {},
              onVibrate: () {},
              onNavigate: (routeName, {arguments}) {},
            );
          },
        ),

        // NEW: Updated FacialRecognitionState provider to inject dependencies
        ChangeNotifierProvider<FacialRecognitionState>(
          create: (context) => FacialRecognitionState(
            networkService: context.read<NetworkService>(),
            speechService: context.read<SpeechService>(),
            faceRecognizerService: context.read<FaceRecognizerService>(), // Injected
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => SceneDescriptionState(
            context.read<NetworkService>(), // Inject NetworkService
            context.read<GeminiService>(), // Inject GeminiService
          ),
        ),
        ChangeNotifierProvider(create: (_) => EmergencyState()),
        ChangeNotifierProvider(
          create: (context) => TextReaderState(
            speechService: context.read<SpeechService>(),
            geminiService: context.read<GeminiService>(), // Inject GeminiService
            networkService: context.read<NetworkService>(), // Inject NetworkService
          ),
        ),
      ],
      child: const AssistLensApp(),
    ),
  );
}

class AssistLensApp extends StatefulWidget {
  const AssistLensApp({super.key});

  @override
  State<AssistLensApp> createState() => _AssistLensAppState();
}

class _AssistLensAppState extends State<AssistLensApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      logger.i('Theme toggled to $_themeMode');
    });
  }

  // Define light theme colors matching the image
  final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    // primarySwatch is deprecated, use colorScheme
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF4A65FB), // Main blue for buttons, accents (from image)
      onPrimary: Colors.white, // Text/icons on primary
      secondary: Color(0xFF00BFA5), // Green from "Scheduling" (from image)
      onSecondary: Colors.white, // Text/icons on secondary
      tertiary: Color(0xFF7D59F0), // Purple from "Search by image" (from image)
      onTertiary: Colors.white, // Text/icons on tertiary
      background: Color(0xFFF7F7F7), // Background for scaffold (from image)
      onBackground: Color(0xFF34495E), // Text on background (from image)
      surface: Color(0xFFF7F7F7), // App bar background, cards, text fields (from image)
      onSurface: Color(0xFF34495E), // Text/icons on surface (from image)
      primaryContainer: Color(0xFFE0E6FD), // Light blue background (user message bubbles, premium card)
      onPrimaryContainer: Color(0xFF2C3E50), // Text on primary container
      secondaryContainer: Color(0xFFC3B0FB), // Light purple background (Aniwa message bubbles, typing indicator)
      onSecondaryContainer: Color(0xFF2C3E50), // Text on secondary container
      error: Colors.redAccent,
      onError: Colors.white,
      shadow: Color(0xFF000000), // Explicitly define shadow color for use in HomePage
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF7F7F7), // Matches app bar in image
      foregroundColor: Color(0xFF2C3E50), // Title/text color
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
      color: Colors.white, // Card background
      shadowColor: Colors.grey.withOpacity(0.1), // Subtle shadow for cards
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: Color(0xFF4A65FB), // Active tab color
      unselectedItemColor: Color(0xFF9E9E9E), // Inactive tab color
      backgroundColor: Colors.white, // Nav bar background (container for ClipRRect)
      type: BottomNavigationBarType.fixed,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500),
    ),
    textTheme: const TextTheme(
      // Ensure these match the actual usage in other files (e.g., HomePage, ChatPage)
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2C3E50),
      ), // Primary text color for titles like "Quick Actions"
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Color(0xFF2C3E50),
      ), // Primary text color for card titles, app bar titles
      bodyMedium: TextStyle(
        fontSize: 16,
        color: Color(0xFF2C3E50),
      ), // Primary text color for general body text
      bodySmall: TextStyle(
        fontSize: 14,
        color: Color(0xFF9E9E9E), // Secondary text color for descriptions
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF4A65FB), // For button labels
      ),
    ),
    // shadowColor property from root ThemeData if needed for general use
    shadowColor: Colors.black, // Default shadow color
  );

  // Define dark theme colors complementing the light theme
  final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF4A65FB), // Same primary blue
      onPrimary: Colors.white,
      secondary: Color(0xFF00BFA5), // Green
      onSecondary: Colors.white,
      tertiary: Color(0xFF7D59F0), // Purple - same as light mode
      onTertiary: Colors.white,
      background: Color(0xFF121212), // Dark background
      onBackground: Colors.white70, // Text on dark background
      surface: Color(0xFF1E1E1E), // Darker surface for cards, app bar, text fields
      onSurface: Colors.white70, // Text/icons on surface
      primaryContainer: Color(0xFF2D2058), // Darker blue/purple container
      onPrimaryContainer: Colors.white,
      secondaryContainer: Color(0xFF4A2B8B), // Darker purple container
      onSecondaryContainer: Colors.white,
      error: Colors.redAccent,
      onError: Colors.white,
      shadow: Color(0xFF000000),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E), // Dark app bar
      foregroundColor: Colors.white, // Title/text color
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
      color: const Color(0xFF2A2A2A), // Dark card background
      shadowColor: Colors.white.withOpacity(0.05),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: Color(0xFF4A65FB), // Active tab color
      unselectedItemColor: Color(0xFF757575), // Inactive tab color
      backgroundColor: Color(0xFF1E1E1E), // Nav bar background
      type: BottomNavigationBarType.fixed,
      showSelectedLabels: true,
      showUnselectedLabels: true,
      selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ), // Light text
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ), // Light text
      bodyMedium: TextStyle(
        fontSize: 16,
        color: Colors.white70,
      ), // Secondary text
      bodySmall: TextStyle(
        fontSize: 14,
        color: Color(0xFF9E9E9E),
      ), // Tertiary text
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
    final bool hasCompletedOnboarding = context.select<AppState, bool>((s) => s.onboardingComplete);

    return ThemeProvider(
      themeMode: _themeMode,
      toggleTheme: toggleTheme,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Assist Lens',
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: _themeMode,
        initialRoute:
            hasCompletedOnboarding ? AppRouter.mainAppWrapper : AppRouter.onboarding,
        onGenerateRoute: AppRouter.onGenerateRoute,
        navigatorObservers: [routeObserver],
      ),
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

class MainAppWrapper extends StatefulWidget {
  const MainAppWrapper({super.key});

  @override
  State<MainAppWrapper> createState() => _MainAppWrapperState();
}

class _MainAppWrapperState extends State<MainAppWrapper> {
  // Use AppState's currentTabIndex
  // int _selectedIndex = 0; // Removed local state

  final List<Widget> _pages = [
    const HomePage(),
    const AniwaChatPage(isForTabInitialization: true), // Mark for tab init
    const ExploreFeaturesPage(),
    const Center(
      child: Text(
        'Profile Page Content - Coming Soon!',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
    ), // Placeholder for Profile
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // No need to set initial _selectedIndex here; it's read from AppState.
  }

  void _onItemTapped(int index) {
    // Update the index in AppState
    Provider.of<AppState>(context, listen: false).currentTabIndex = index;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appState = context.watch<AppState>(); // Watch AppState for currentTabIndex

    final Color navBarBg = colorScheme.surface;
    final Color navBarShadowColor = colorScheme.shadow.withOpacity(0.1); // Using theme's shadow color

    return Scaffold(
      body: IndexedStack(index: appState.currentTabIndex, children: _pages), // Use AppState index
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBarBg,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: navBarShadowColor,
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          child: BottomNavigationBar(
            backgroundColor: Colors.transparent, // Ensures Container's color is visible
            elevation: 0,
            currentIndex: appState.currentTabIndex, // Use AppState index
            onTap: _onItemTapped,
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.chat_rounded),
                label: 'Chat',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.explore_rounded),
                label: 'Explore',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
