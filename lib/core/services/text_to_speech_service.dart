// lib/core/services/text_to_speech_service.dart
import 'package:flutter_tts/flutter_tts.dart';

class TextToSpeechService {
  final FlutterTts _tts = FlutterTts();

  Future<void> speak(String text, String languageCode) async {
    await _tts.setLanguage(mapLanguageCode(languageCode));
    await _tts.speak(text);
  }

  String mapLanguageCode(String code) {
    switch (code) {
      case 'spa': return 'es-ES';
      case 'fra': return 'fr-FR';
      case 'deu': return 'de-DE';
      case 'ita': return 'it-IT';
      case 'por': return 'pt-BR';
      default: return 'en-US';
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}