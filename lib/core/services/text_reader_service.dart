import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;

abstract class TextReaderService {
  Future<String> recognizeText({String? base64Image});
  void dispose();
  factory TextReaderService({File? imageFile, String language = 'eng'}) {
    if (kIsWeb) {
      return WebTextReaderService(language: language);
    } else {
      if (imageFile == null) {
        throw ArgumentError('imageFile must be provided on mobile');
      }
      return NativeTextReaderService(imageFile: imageFile, language: language);
    }
  }
}

class NativeTextReaderService implements TextReaderService {
  final File imageFile;
  final String language;
  late final TextRecognizer _recognizer;
  
  NativeTextReaderService({required this.imageFile, this.language = 'eng'}) {
    _recognizer = TextRecognizer();
  }

  @override
  Future<String> recognizeText({String? base64Image}) async {
    final inputImage = InputImage.fromFile(imageFile);
    final visionResult = await _recognizer.processImage(inputImage);
    
    final buffer = StringBuffer();
    for (final block in visionResult.blocks) {
      for (final line in block.lines) {
        buffer.writeln(line.text);
      }
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    _recognizer.close();
  }
}
class WebTextReaderService implements TextReaderService {
  final String language;
  String? _base64Image;

  WebTextReaderService({this.language = 'eng'});

  Future<void> _pickAndEncodeImage() async {
    final uploadInput = html.FileUploadInputElement()..accept = 'image/*';
    uploadInput.click();
    await uploadInput.onChange.first;
    final file = uploadInput.files!.first;

    final reader = html.FileReader();
    reader.readAsDataUrl(file);
    await reader.onLoad.first;
    final dataUrl = reader.result as String;
    _base64Image = dataUrl.split(',').last;
  }

  @override
  Future<String> recognizeText({String? base64Image}) async {
    if (base64Image != null && base64Image.isNotEmpty) {
      _base64Image = base64Image;
    } else if (_base64Image == null) {
      await _pickAndEncodeImage();
    }

    final uri = Uri.parse('https://api.ocr.space/parse/image');
    final response = await http.post(
      uri,
      headers: {'apikey': 'K83196418688957'},
      body: {
        'base64Image': 'data:image/png;base64,$_base64Image',
        'language': language,
        'isOverlayRequired': 'false',
        'scale': 'true', // Improve image scaling
        'OCREngine': '2', // Better engine
      },
    );

    if (response.statusCode != 200) {
      throw Exception('OCR.space API Error: ${response.statusCode}');
    }

    final jsonResponse = jsonDecode(response.body);
    final parsedResults = jsonResponse['ParsedResults'];
    
    if (parsedResults == null || parsedResults.isEmpty) {
      return '';
    }

    return parsedResults[0]['ParsedText'] ?? '';
  }

  @override
  void dispose() {
    // No resources to dispose for web
  }
}