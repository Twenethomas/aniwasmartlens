// lib/core/services/text_reader_service.dart
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'; // Correct import for TextRecognizer
import 'package:logger/logger.dart';

class NativeTextReaderService {
  final Logger _logger = Logger();
  final TextRecognizer _textRecognizer;

  /// Constructor for NativeTextReaderService.
  /// [language] is the BCP-47 language code for the text to be recognized.
  /// Defaults to 'en' (English).
  NativeTextReaderService({String language = 'en'})
    : _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Recognizes text from a given image file.
  /// Returns the recognized text as a single string.
  Future<String> recognizeText({required File imageFile}) async {
    _logger.i("Attempting to recognize text from image: ${imageFile.path}");
    try {
      final inputImage = InputImage.fromFile(imageFile);
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      String fullText = '';
      // Corrected API usage: use .blocks and .lines properties
      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          fullText +=
              '${line.text}\n'; // Append each line, add newline for readability
        }
      }
      _logger.i(
        "Text recognition completed. Recognized text length: ${fullText.length}",
      );
      return fullText.trim(); // Trim any leading/trailing whitespace
    } catch (e) {
      _logger.e("Error during text recognition: $e");
      return "Failed to recognize text: $e";
    }
  }

  /// Disposes the text recognizer to release resources.
  void dispose() {
    _logger.i("Disposing NativeTextReaderService.");
    _textRecognizer.close();
  }
}
