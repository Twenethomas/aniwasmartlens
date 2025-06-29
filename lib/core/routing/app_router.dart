// lib/core/routing/app_router.dart
import 'package:assist_lens/features/aniwa_chat/aniwa_chat_page.dart';
import 'package:assist_lens/features/emergency/emergency_page.dart';
import 'package:assist_lens/features/explore_features_page.dart';
import 'package:assist_lens/features/face_recognition/facial_recognition.dart';
import 'package:assist_lens/features/history/history_page.dart';
import 'package:assist_lens/features/home/home_page.dart';
import 'package:assist_lens/features/navigation/active_navigation_screen.dart';
import 'package:assist_lens/features/navigation/map_screen.dart';
import 'package:assist_lens/features/object_detection/object_detection_page.dart';
import 'package:assist_lens/features/onboarding/onboarding_page.dart';
import 'package:assist_lens/features/scene_description/scene_description_page.dart';
import 'package:assist_lens/features/text_reader/text_reader_page.dart';
import 'package:assist_lens/features/settings/settings_page.dart'; // NEW: Import SettingsPage
// For MainAppWrapper
import 'package:assist_lens/features/raspberry_pi/raspberry_pi_page.dart';
import 'package:assist_lens/features/raspberry_pi/raspberry_pi_view_page.dart';

import 'package:assist_lens/features/profile/profile_page.dart';

import 'package:flutter/material.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:latlong2/latlong.dart' as latlong2;

class AppRouter {
  static const String onboarding = '/onboarding';
  static const String mainAppWrapper = '/'; // Or '/main'
  static const String home =
      '/home'; // This is now a distinct route from mainAppWrapper
  static const String textReader = '/textReader';
  static const String sceneDescription = '/sceneDescription';
  static const String navigation = '/navigation';
  static const String emergency = '/emergency';
  static const String history = '/history';
  static const String objectDetector = '/objectDetector';
  static const String facialRecognition = '/facialRecognition';
  static const String aniwaChat = '/aniwaChat';
  static const String activeNavigation = '/activeNavigation';
  static const String exploreFeatures = '/exploreFeatures';
  static const String profile = '/profile';
  static const String raspberryPiConnect = '/raspberryPiConnect';
  static const String raspberryPiView = '/raspberryPiView';
  static const String settings = '/settings'; // NEW: Add settings route
  static const String homeRoute = '/home'; // For profile page

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingPage());
      case mainAppWrapper:
        return MaterialPageRoute(builder: (_) => const HomePage());
      case home:
        return MaterialPageRoute(builder: (_) => const HomePage());
      case textReader:
        return MaterialPageRoute(builder: (_) => TextReaderPage());
      case aniwaChat:
        // No longer takes initialQuery or isForTabInitialization
        return MaterialPageRoute(builder: (_) => const AniwaChatPage());
      case sceneDescription:
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return MaterialPageRoute(
          builder:
              (_) => SceneDescriptionPage(
                autoDescribe: args['autoDescribe'] as bool? ?? false,
              ),
        );
      case navigation:
        return MaterialPageRoute(builder: (_) => const MapScreen());
      case emergency:
        return MaterialPageRoute(builder: (_) => const EmergencyPage());
      case history:
        return MaterialPageRoute(builder: (_) => const HistoryPage());
      case objectDetector:
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return MaterialPageRoute(
          builder:
              (_) => ObjectDetectionPage(
                autoStartLive: args['autoStartLive'] as bool? ?? false,
              ),
        );
      case facialRecognition:
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return MaterialPageRoute(
          builder:
              (_) => FacialRecognition(
                autoStartLive: args['autoStartLive'] as bool? ?? false,
              ),
        );
      case activeNavigation:
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => ActiveNavigationScreen(),
          settings: settings,
        );
      case exploreFeatures:
        return MaterialPageRoute(builder: (_) => const ExploreFeaturesPage());
      case raspberryPiConnect:
        return MaterialPageRoute(
          builder: (_) => const RaspberryPiConnectPage(),
        );
      case raspberryPiView:
        return MaterialPageRoute(builder: (_) => const RaspberryPiViewPage());

      case profile:
        return MaterialPageRoute(builder: (_) => const ProfilePage());
      case AppRouter.settings:
        return MaterialPageRoute(builder: (_) => const SettingsPage());
      default:
        return MaterialPageRoute(
          builder:
              (_) => Scaffold(
                body: Center(
                  child: Text('No route defined for ${settings.name}'),
                ),
              ),
        );
    }
  }
}
