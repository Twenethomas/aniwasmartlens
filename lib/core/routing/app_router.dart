// lib/core/routing/app_router.dart
import 'package:assist_lens/features/aniwa_chat/aniwa_chat_page.dart';
import 'package:assist_lens/features/emergency/emergency_page.dart';
import 'package:assist_lens/features/explore_features_page.dart';
import 'package:assist_lens/features/face_recognition/facial_recognition.dart';
import 'package:assist_lens/features/history/history_page.dart';
import 'package:assist_lens/features/home/home_page.dart';
import 'package:assist_lens/features/navigation/active_navigation_screen.dart';
import 'package:assist_lens/features/navigation/map_screen.dart';
import 'package:assist_lens/features/onboarding/onboarding_page.dart';
import 'package:assist_lens/features/pc_cam/screens/object_detection_screen.dart';
import 'package:assist_lens/features/scene_description/scene_description_page.dart';
import 'package:assist_lens/features/text_reader/text_reader_page.dart';
import 'package:assist_lens/main.dart'; // For MainAppWrapper

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlong2;

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
  static const String open =
      '/open'; // This is the route for opening the app directly to the main app wrapper

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingPage());
      case mainAppWrapper:
        return MaterialPageRoute(builder: (_) => const MainAppWrapper());
      case home:
        return MaterialPageRoute(builder: (_) => const HomePage());
      case textReader:
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return MaterialPageRoute(
          builder:
              (_) => TextReaderPage(
                forChatIntegration:
                    args['forChatIntegration'] as bool? ?? false,
                autoCapture: args['autoCapture'] as bool? ?? false,
                autoTranslate: args['autoTranslate'] as bool? ?? false,
              ),
        );
      case aniwaChat:
        final args = settings.arguments as Map<String, dynamic>? ?? {};
        return MaterialPageRoute(
          builder:
              (_) => AniwaChatPage(
                initialQuery: args['initialQuery'] as String?,
                isForTabInitialization:
                    args['isForTabInitialization'] as bool? ?? false,
              ),
        );
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
              (_) => ObjectDetectionScreen(
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
          builder:
              (_) => ActiveNavigationScreen(
                initialPosition: args['initialPosition'] as Position,
                destination: args['destination'] as latlong2.LatLng,
              ),
        );
      case exploreFeatures:
        return MaterialPageRoute(builder: (_) => const ExploreFeaturesPage());
      case open:
        // This route is used to open the app directly to the main app wrapper
        return MaterialPageRoute(builder: (_) => const MainAppWrapper());
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
