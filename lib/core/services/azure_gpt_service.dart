// lib/core/services/azure_gpt_service.dart
import 'package:http/http.dart' as http;
import 'dart:convert';

class AzureGptService {
  final String azureApiKey;
  final String azureEndpoint;

  AzureGptService({required this.azureApiKey, required this.azureEndpoint});

  /// Corrects OCR errors and structures text
  Future<String> correctOcrErrors(String rawText) async {
    final headers = {
      'Content-Type': 'application/json',
      'api-key': azureApiKey,
    };

    final body = jsonEncode({
      'messages': [
        {
          'role': 'user',
          'content': 'Correct any OCR errors in the following text and structure it properly:\n\n$rawText'
        }
      ],
      'temperature': 0.3,
      'max_tokens': 2000,
    });

    final response = await http.post(
      Uri.parse(azureEndpoint),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse['choices'][0]['message']['content'];
    } else {
      throw Exception('Azure API Error: ${response.statusCode} - ${response.body}');
    }
  }

  /// Detects text language
  Future<String> detectLanguage(String text) async {
    final headers = {
      'Content-Type': 'application/json',
      'api-key': azureApiKey,
    };

    final body = jsonEncode({
      'messages': [
        {
          'role': 'system',
          'content': 'You are a professional language detector. Return only the detected language code without any additional text.'
        },
        {'role': 'user', 'content': text}
      ],
      'temperature': 0.1,
      'max_tokens': 800,
    });

    final response = await http.post(
      Uri.parse('$azureEndpoint?api-version=2023-03-15-preview'),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      final detectedLang = jsonResponse['choices'][0]['message']['content'].trim().toLowerCase();
      
      // Map to OCR.space language codes
      final langMap = {
        'english': 'eng',
        'spanish': 'spa',
        'french': 'fra',
        'german': 'deu',
        'italian': 'ita',
        'portuguese': 'por',
      };
      
      return langMap[detectedLang] ?? 'eng';
    } else {
      throw Exception('Language detection failed');
    }
  }

  /// Translates text between languages
  Future<String> translateText({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) async {
    final headers = {
      'Content-Type': 'application/json',
      'api-key': azureApiKey,
    };

    final body = jsonEncode({
      'messages': [
        {
          'role': 'system',
          'content': 'You are a professional translator. Translate the text from $sourceLang to $targetLang without any additional text.'
        },
        {'role': 'user', 'content': text}
      ],
      'temperature': 0.1,
      'max_tokens': 800,
    });

    final response = await http.post(
      Uri.parse('$azureEndpoint?api-version=2023-03-15-preview'),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse['choices'][0]['message']['content'].trim();
    } else {
      throw Exception('Translation Error: ${response.statusCode} - ${response.body}');
    }
  }
}