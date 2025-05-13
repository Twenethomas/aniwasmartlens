// lib/core/services/image_labeler_service.dart
import 'dart:io';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;

abstract class ImageLabelerService {
  Future<List<ImageLabel>> labelImage({String? base64Image});
  void dispose();
  factory ImageLabelerService() {
    if (kIsWeb) {
      return WebImageLabelerService();
    } else {
      return NativeImageLabelerService();
    }
  }
}

class NativeImageLabelerService implements ImageLabelerService {
  final ImageLabeler _labeler = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: 0.5),
  );
  
  @override
  Future<List<ImageLabel>> labelImage({String? base64Image}) async {
    if (base64Image == null) {
      throw StateError('Image not available for labeling');
    }
    
    final inputImage = InputImage.fromFilePath(base64Image);
    return await _labeler.processImage(inputImage);
  }

  @override
  void dispose() {
    _labeler.close();
  }
}

class WebImageLabelerService implements ImageLabelerService {
  final String apiKey = "K83196418688957"; // OCR.space key
  
  @override
  Future<List<ImageLabel>> labelImage({String? base64Image}) async {
    if (base64Image == null) {
      throw StateError('Image not available for labeling');
    }
    
    final uri = Uri.parse('https://api.ocr.space/parse/image');
    final response = await http.post(
      uri,
      headers: {'apikey': apiKey},
      body: {
        'base64Image': 'data:image/png;base64,$base64Image',
        'language': 'eng',
        'isOverlayRequired': 'false',
        'scale': 'true',
        'OCREngine': '2', // Better engine
      },
    );

    if (response.statusCode != 200) {
      throw Exception('OCR.space error ${response.statusCode}');
    }

    final jsonResponse = jsonDecode(response.body);
    final parsedResults = jsonResponse['ParsedResults'];
    
    if (parsedResults == null || parsedResults.isEmpty) {
      return [];
    }
    
    final text = parsedResults[0]['ParsedText'] ?? '';
    return [ImageLabel(label: text, confidence: 0.0, index: 0)];
  }

  @override
  void dispose() {
    // No resources to dispose for web
  }
}