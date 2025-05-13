import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  final _stt = SpeechToText();
  final _tts = FlutterTts();

  Future<void> init() async {
    await _stt.initialize();
    await _tts.setLanguage('en-US');
  }

  Future<String?> listen() async {
    return null;
  
    // TODO: implement listening
  }

  Future<void> speak(String text) async {
    await _tts.speak(text);
  }
}
