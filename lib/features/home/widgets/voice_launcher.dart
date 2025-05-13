// lib/features/home/widgets/voice_launcher.dart
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceLauncher extends StatelessWidget {
  const VoiceLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () async {
        final stt = SpeechToText();
        final tts = FlutterTts();

        if (!(await stt.hasPermission)) {
          await stt.initialize();
        }

        if (stt.isNotListening) {
          await stt.listen();
          await stt.listen(onResult: (result) async {
            await tts.speak(result.recognizedWords);
          });
        } else {
          await stt.stop();
          await tts.stop();
        }
      },
      child: const Icon(Icons.mic),
    );
  }
}