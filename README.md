# 👁️ Assist Lens: Your Hands-Free AI Companion

**Assist Lens** is a mobile app designed to help **visually impaired people** live more independently. Using **real-time AI**, **voice control**, and **smart computer vision**, it serves as a hands-free companion.  
Just say: _**“Hey Assist Lens”**_ to begin.

---

## 🌟 Features

| 🔹 Feature | 📝 Description |
|-----------|----------------|
| 🧠 **Aniwa AI Chat** | Talk to **Aniwa**, your AI assistant powered by **Gemini AI**. Ask anything, get smart, human-like responses. |
| 🎙️ **Voice Control** | Fully voice-enabled. Control everything with simple voice commands—no touch needed. |
| 📖 **Text Reader** | Point the camera at any printed material (signs, books, menus) and the app reads it aloud. It can auto-correct recognition errors and translate to English. |
| 🌄 **Scene Description** | Take a photo and get a natural-language description of what’s in the image. E.g., _“A park with trees and two people walking.”_ |
| 🧠 **Object Detection** | Recognizes everyday objects in real-time (e.g., “chair,” “dog,” “bottle”). |
| 🧑‍🤝‍🧑 **Face Recognition** | Identifies familiar faces using your device camera. |
| 🗺️ **Smart Navigation** | Get voice directions, object distance alerts, and destination notifications using maps and sensors. |
| 🚨 **Emergency Help** | Quickly alert emergency contacts and share your live GPS location with one tap or command. |
| 🕓 **Activity History** | Access logs of past chats, AI descriptions, and user interactions. |
| 🌗 **Day & Night Mode** | Adaptive themes for daylight and low-light conditions—automatically or manually switch. |

---

## 🛠️ Technology Stack

| 🧩 Technology | 🔧 Description |
|--------------|----------------|
| 💙 **Flutter** | Cross-platform mobile framework used for building the app. |
| 🪄 **Provider** | Lightweight, reactive state management. |
| 🔍 **Google ML Kit** | On-device OCR, face detection, and object recognition. |
| 🧠 **Gemini API** | Conversational AI from Google powering Aniwa. |
| 🗣️ **Speech-to-Text (STT)** | Converts user speech into actionable commands. |
| 🔊 **Text-to-Speech (TTS)** | Reads back AI responses, recognized text, or scene descriptions. |
| 🧏 **Picovoice Porcupine** | Lightweight wake-word engine for always-on listening. |
| 📍 **Geolocator + Flutter Map** | Real-time location tracking and smart voice navigation. |
| 📷 **Flutter Camera & Permissions** | Camera integration for vision features. |
| ☁️ **Firebase** | Backend services including real-time database and cloud functions. |

---
## 📂 Project Structure
```

```markdown
assist\_lens/
├── android/                   # Android-specific code
├── assets/                    # Images, fonts, AI models
├── lib/
│   ├── core/
│   │   ├── routing/           # Navigation between screens
│   │   └── services/          # Speech, AI, network helpers
│   ├── features/              # Core features (chat, camera, etc.)
│   │   ├── aniwa\_chat/
│   │   ├── pc\_cam/
│   │   └── ...
│   └── main.dart              # App entry point
├── pubspec.yaml               # Project dependencies
└── README.md                  # This file

```
## 🚀 Getting Started

### ✅ Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.7.2 or newer)
- VS Code or Android Studio (with Flutter/Dart plugins)
- JDK 11+
- Android/iOS device or emulator

### 📥 Installation

1. Clone the repo:

```bash
git clone https://github.com/yTwenethomas/aniwasmartlens.git
cd assist_lens
````

2. Install dependencies:

```bash
flutter pub get
```

3. Set up Firebase:

* Create a project in [Firebase Console](https://console.firebase.google.com/)
* Add Android/iOS app
* Download:

  * `google-services.json` → `android/app/`
  * `GoogleService-Info.plist` → `ios/Runner/`

4. Fill in your Firebase details in `lib/main.dart`:

```dart
await Firebase.initializeApp(
  name: 'assist_lens',
  options: const FirebaseOptions(
    apiKey: 'YOUR_API_KEY',
    appId: 'YOUR_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
  ),
);
```

5. Add Gemini API Key in `lib/core/services/gemini_service.dart`:

```dart
const apiKey = "YOUR_GEMINI_API_KEY";
```

6. Add AI model files (`.tflite`, `.txt`) in `assets/ml/`.

---

## 🤖 Android Setup

1. Add permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
```

2. Define the voice service:

```xml
<application>
    <service
        android:name=".VoiceAssistantService"
        android:foregroundServiceType="microphone" />
</application>
```

3. In `android/app/build.gradle`:

```gradle
android {
    defaultConfig {
        minSdk = 21
    }
}
dependencies {
    implementation 'io.flutter.plugins.camera:camera-camera2:0.11.1'
}
```

4. Check `VoiceAssistantService.kt` (path: `android/app/src/main/kotlin/...`):

```kotlin
package com.example.assist_lens
```

Update the package name if different.

---

## 🍎 iOS Setup

1. Add permission descriptions in `ios/Runner/Info.plist`.

2. In Xcode, go to **Signing & Capabilities** > enable:

* Background Modes

  * ✅ Audio, AirPlay, Picture in Picture
  * ✅ Voice over IP

---

## ▶️ Run the App

```bash
flutter clean
flutter pub get
flutter run
```

---

## 🗣️ Using the App

* Say **“Hey Assist Lens”** to activate the assistant.

* Use commands like:

  * “Describe the scene.”
  * “Read this text.”
  * “Who’s around me?”
  * “Call emergency.”

* Tap the **Chat** tab to chat with Aniwa.

* Use the **Explore** tab for manual features.

---

## 🤝 Contributing

We welcome contributions!

1. Fork the repo
2. Create your feature branch: `git checkout -b feature/your-feature`
3. Commit: `git commit -m "Added new feature"`
4. Push: `git push origin feature/your-feature`
5. Open a **Pull Request**

Try to follow existing code style and naming conventions.

---

## 📄 License

This project is licensed under the MIT License. See [`LICENSE.md`](./LICENSE.md) for details.

---

**Built with 💙 for the visually impaired community.**

