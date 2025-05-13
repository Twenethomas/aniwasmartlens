// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/services/network_service.dart';
import 'state/app_state.dart';
import 'features/onboarding/onboarding_page.dart';
import './features/home/home_page.dart';
import './features/text_reader/text_reader_page.dart';
import './features/scene_description/scene_description_page.dart'; // Add
import './features/emergency/emergency_page.dart'; // Add
import './features/pc_cam/pc_cam_page.dart'; // Add
import './features/history/history_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NetworkService()..init()),
        ChangeNotifierProvider(create: (_) => AppState(prefs)),
      ],
      child: AssistLensApp(),
    ),
  );
}

class AssistLensApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final done = context.select<AppState, bool>((s) => s.onboardingComplete);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Assist Lens',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: const AppBarTheme(
          elevation: 2,
          backgroundColor: Colors.indigo,
          centerTitle: true,
        ),
      ),
      initialRoute: done ? '/home' : '/onboarding',
      routes: {
        '/onboarding': (_) => OnboardingPage(),
        '/home': (_) => const HomePage(),
        '/textReader': (_) => const TextReaderPage(),
        '/sceneDescription': (_) => const SceneDescriptionPage(), // Add
       // Add '/navigation': (_) => const NavigationPage(), // Add
        '/emergency': (_) => const EmergencyPage(), // Add
        '/pcCam': (_) => const PcCamPage(), // Add
        '/history': (_) => const HistoryPage(),
      },
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => Scaffold(
          body: Center(
            child: Text('404 - Page not found: ${settings.name}'),
          ),
        ),
      ),
    );
  }
}