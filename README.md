> A cross‑platform Flutter app providing vision‑enabled accessibility features  
> for visually impaired users and their caregivers.

![Flutter Version](https://img.shields.io/badge/flutter-3.7.2-blue)  
![Dart Version](https://img.shields.io/badge/dart-3.1.5-blue)  
![License](https://img.shields.io/badge/license-MIT-green)

---

## 🚀 Features

- **Onboarding**  
  Animated, full‑screen walkthrough with high‑contrast branding.

- **Home Dashboard**  
  Dynamic greeting, quick‑action carousel, recent activity, and caretaker panel.

- **Text Reader**  
  Live camera capture (mobile & web), OCR via Azure GPT, TTS playback with play/stop controls.

- **Scene Description**  
  Describe surroundings, identify objects & colors via ML Kit.

- **Navigation Aid**  
  Voice‑guided indoor/outdoor routing with obstacle alerts.

- **Face Recognition**  
  Detect & name familiar faces via ML Kit Face Detection.

- **Emergency SOS**  
  One‑tap alert calls & location sharing with paired caregiver.

- **Video Call**  
  Two‑way RTC video chat between user and caregiver.

- **ESP32 Cam Integration**  
  Optional external camera support for arduino‑powered wearables.

---

## 📦 Tech Stack & Dependencies

- **Flutter** (≥ 3.7.2) & **Dart** (≥ 3.1.5)  
- **State Management**: Provider  
- **OCR & Vision**:  
  - Google ML Kit (Text, Face, Object)  
  - Azure OpenAI GPT‑4 Vision endpoint  
- **TTS**: `flutter_tts`  
- **Camera**: `camera` + Web `<video>` via `dart:html`  
- **Networking**: `http`, `connectivity_plus`  
- **Local Storage**: `shared_preferences`  
- **Mapping**: `flutter_map` + `latlong2`  
- **WebRTC**: `flutter_webrtc`  
- **Others**: `permission_handler`, `image`, `logger`, `url_launcher`

---

## ⚙️ Getting Started

### 1. Clone the repo

git clone https://github.com/Twenethomas/aniwasmartlens.git
cd aniwasmartlens2. Configure environment
Copy the example env file and fill in your keys:

bash
Copy
Edit
cp .env.example .env
Edit .env and set:

dotenv
Copy
Edit
AZURE_OPENAI_ENDPOINT=https://buzznewwithgpt4.openai.azure.com
AZURE_OPENAI_KEY=YOUR_API_KEY
AZURE_COGNITIVE_SERVICES_KEY=YOUR_COGNITIVE_KEY
3. Install dependencies
bash
Copy
Edit
flutter pub get
4. Run the app
Mobile (Android/iOS):

bash
Copy
Edit
flutter run
Web:

bash
Copy
Edit
flutter run -d chrome
🧩 Project Structure
perl
Copy
Edit
lib/
├── core/
│   ├── services/       # OCR, networking, history, state
│   └── utils/          # image preprocessing, token trimming
├── features/
│   ├── onboarding/     # Onboarding screens & widgets
│   ├── home/           # Dashboard & widgets
│   ├── text_reader/    # Capture, OCR & TTS UI
│   ├── scene_description/
│   ├── navigation/
│   ├── face_recognition/
│   ├── emergency/
│   ├── video_call/
│   └── esp32_cam/      # (stub for future)
├── state/              # AppState & Provider setup
└── widgets/            # Shared UI components
📖 Usage
On first launch, swipe through onboarding slides.

From Home, tap any feature card to launch.

Text Reader: capture or pick an image → auto‑compress & send to Azure OCR → view & speak text.

History: view past readings in the History screen.

Emergency: quickly alert your paired caregiver.

🤝 Contributing
Fork the repository

Create a feature branch (git checkout -b feature/YourFeature)

Commit your changes (git commit -m 'Add some feature')

Push to the branch (git push origin feature/YourFeature)

Open a Pull Request

Please adhere to the existing code style and include relevant tests if possible.

📝 License
This project is licensed under the MIT License.

📞 Support
If you run into issues or have questions, please file an issue on GitHub or email support@aniwasmartlens.org.

Built with ❤️ by the AniwaSmartLens team
