Assist Lens: Your Hands-Free AI Companion
Assist Lens is a cutting-edge mobile application designed to empower visually impaired individuals with enhanced accessibility and independence. Leveraging advanced AI capabilities, the app provides real-time information and assistance through voice commands, visual recognition, and smart navigation.

Features
Aniwa AI Chat: Engage in natural language conversations with Aniwa, your intelligent AI assistant, powered by the Gemini API.

Voice Control & Hands-Free Operation: Control the app and its features using intuitive voice commands, providing a seamless and accessible user experience.

Text Reader: Instantly recognize and read text from images (OCR), correct errors, and translate content into English.

Scene Description: Capture a picture of your surroundings and receive a detailed AI-generated description of the scene.

Object Detection: Get real-time identification of objects in your camera's view, with AI-powered descriptions on demand.

Facial Recognition: Identify known individuals through your camera, providing information about who is around you.

Smart Navigation: Plan routes, get real-time voice-guided directions, and receive proximity alerts to your destination.

Emergency Assistance: Quickly access emergency contacts and share your location in critical situations.

Activity History: Keep track of your past interactions and information queries.

Adaptive Themes: Switch between light and dark modes for optimal visual comfort.

Technologies Used
Flutter SDK: For cross-platform mobile application development.

Google ML Kit:

Text Recognition

Object Detection

Face Detection

Gemini API: For powerful conversational AI, image understanding, and text processing.

Flutter TTS (Text-to-Speech): For vocalizing AI responses and app information.

Speech-to-Text: For transcribing voice commands and inputs.

Picovoice Porcupine: For efficient and low-power wake word detection (e.g., "Hey Assist Lens").

Camera: For accessing device cameras.

Geolocator & Flutter Map: For location services, mapping, and navigation.

Connectivity Plus: For monitoring network connectivity.

Permission Handler: For managing runtime permissions.

Firebase Core: For core app functionalities and potentially future backend services.

Provider: For state management.

Logger: For robust logging and debugging.

Vibration: For haptic feedback.

Shared Preferences: For local data persistence (e.g., app settings, history).

HTTP & Web Socket Channel: For network communication.

TF Lite Flutter: For running on-device machine learning models.

SQFlite: For local database storage (if used).

Google Fonts: For custom typography.

Flutter SpinKit: For loading indicators.

Location, Sensors Plus, Geocoding, Intl, URL Launcher: Other utility packages.

Getting Started
Follow these instructions to set up and run the Assist Lens app on your local machine.

Prerequisites
Flutter SDK (Version 3.7.2 or higher recommended)

Android Studio / VS Code with Flutter and Dart plugins

A physical Android or iOS device, or an emulator/simulator.

Installation
Clone the repository:

git clone [your-repo-url]
cd assist_lens

Install Flutter dependencies:

flutter pub get

Configure API Keys and Firebase:

Firebase:
Open lib/main.dart and replace the placeholder values (YOUR_API_KEY, YOUR_APP_ID, YOUR_MESSAGING_SENDER_ID, YOUR_PROJECT_ID) within FirebaseOptions with your actual Firebase project credentials.

// lib/main.dart
await Firebase.initializeApp(
  name: 'assist_lens',
  options: const FirebaseOptions(
    apiKey: 'YOUR_API_KEY',
    appId: 'YOUR_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
  ),
);

Gemini API:
The GeminiService in lib/core/services/gemini_service.dart typically uses an API key. Ensure that const apiKey = "" is present, as the Canvas environment will inject the API key at runtime. If you're running outside the Canvas, you'll need to provide your actual Gemini API key there:

// lib/core/services/gemini_service.dart
// ...
const apiKey = ""; // Canvas will inject at runtime. For local dev, replace with your key if not using Canvas
// ...

ML Models: Ensure the ML models are correctly placed in the assets/ml/ directory. Your pubspec.yaml already lists them.

Native Platform Setup
For Android:

Refer to the detailed instructions in the android-native-setup document. Key steps include:

AndroidManifest.xml: Add necessary permissions (RECORD_AUDIO, INTERNET, CAMERA, ACCESS_FINE_LOCATION, FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE, etc.) and declare VoiceAssistantService.

android/app/build.gradle: Ensure minSdkVersion is 21 or higher and add implementation 'io.flutter.plugins.camera:camera-camera2:0.11.1' for Camera2 API.

VoiceAssistantService.kt: Ensure this Kotlin file is correctly placed under android/app/src/main/kotlin/com/example/assist_lens/ (adjust package name to match your applicationId). This service handles background microphone listening and communication with Flutter via Method/Event Channels.

For iOS:

(Note: iOS native setup details for background audio/speech were not explicitly provided in the context, but common requirements include:)

Info.plist: Add privacy descriptions for microphone, camera, and location usage (NSMicrophoneUsageDescription, NSCameraUsageDescription, NSLocationWhenInUseUsageDescription, etc.).

Background Modes: Enable "Audio, AirPlay, and Picture in Picture" and "Voice over IP" in your project's Signing & Capabilities for background audio processing if implementing always-on listening similar to Android's foreground service.

Running the Application
Connect a device or start an emulator/simulator.

Run the app:

flutter run

If you encounter compilation errors, run flutter clean and flutter pub get first.

Usage
Voice Commands: Once the app is running, say "Hey Assist Lens" (or your configured wake word if using Porcupine) to activate the voice assistant. You can then speak commands like:

"Describe the scene."

"Read this text."

"Find a restaurant near me."

"Who is this person?"

"Call emergency."

AI Chat: Navigate to the "Chat" tab to type messages and interact with Aniwa.

Explore Features: Use the "Explore" tab to manually access Text Reader, Scene Description, Object Detection, Facial Recognition, Navigation, and Emergency features.

Contributing
Contributions are welcome! If you have suggestions or want to contribute to the codebase, please fork the repository and submit a pull request.

License
This project is licensed under the MIT License - see the LICENSE.md file for details.
