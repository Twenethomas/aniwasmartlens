// lib/core/services/gemini_service.dart
import 'dart:convert';
import 'dart:io'; // Added for File and base64Encode
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import '../../main.dart'; // For global logger instance
import 'network_service.dart'; // For network connectivity check

class GeminiService {
  final Logger _logger = logger; // Use global logger
  final NetworkService _networkService; // Injected NetworkService

  // IMPORTANT: Specify the Gemini 2.0 Flash model
  static const String _modelId = 'gemini-2.0-flash';
  // Leave API key empty; it will be provided by Canvas runtime if needed.
  static const String _apiKey = 'AIzaSyB_P6mKKBgw9acwZ2S3hC5HTSQxdNf6JME';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  GeminiService(this._networkService); // Constructor for dependency injection

  /// Makes a request to the Gemini API to get a chat response.
  ///
  /// [chatHistory]: A list of chat messages in the format expected by the Gemini API.
  /// Each message should be a Map with 'role' (e.g., 'user', 'model') and 'parts'
  /// (a list, where each part is a Map with 'text' or 'inlineData' for images).
  ///
  /// Example `chatHistory` for text:
  /// `[{"role": "user", "parts": [{"text": "Hello, how are you?"}]}]`
  ///
  /// Example `chatHistory` for text and image:
  /// `[{"role": "user", "parts": [{"text": "What is this?", "inlineData": {"mimeType": "image/jpeg", "data": "BASE64_IMAGE_DATA"}}]}]`
  ///
  /// [generationConfig]: Optional configuration for text generation,
  ///   can include `responseMimeType` and `responseSchema` for structured output.
  ///
  /// Returns the AI's response as a String (could be raw text or stringified JSON).
  /// Throws an exception if the network is offline or API call fails.
  Future<String> getChatResponse(
    List<Map<String, dynamic>> chatHistory, {
    Map<String, dynamic>? generationConfig,
    String? modelId, // Allow overriding the model ID
  }) async {
    const int maxRetries = 3;
    int retryCount = 0;
    int delaySeconds = 2;

    if (chatHistory.isEmpty) {
      _logger.e(
        "GeminiService: Chat history is empty. Cannot generate content.",
      );
      throw Exception(
        "GenerateContentRequest.contents: contents is not specified (chatHistory is empty).",
      );
    }

    final String targetModel =
        modelId ?? _modelId; // Use provided modelId or default
    final String url = '$_baseUrl/$targetModel:generateContent?key=$_apiKey';

    final Map<String, dynamic> payload = {'contents': chatHistory};

    if (generationConfig != null) {
      payload['generationConfig'] = generationConfig;
    }

    while (retryCount < maxRetries) {
      if (!_networkService.isOnline) {
        _logger.e("GeminiService: No internet connection for Gemini API call.");
        throw Exception("No internet connection.");
      }

      try {
        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(payload),
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> jsonResponse = json.decode(response.body);
          _logger.d("GeminiService: Raw API response: $jsonResponse");

          if (jsonResponse.containsKey('candidates') &&
              jsonResponse['candidates'] is List &&
              jsonResponse['candidates'].isNotEmpty &&
              jsonResponse['candidates'][0].containsKey('content') &&
              jsonResponse['candidates'][0]['content'].containsKey('parts') &&
              jsonResponse['candidates'][0]['content']['parts'] is List &&
              jsonResponse['candidates'][0]['content']['parts'].isNotEmpty) {
            final firstPart =
                jsonResponse['candidates'][0]['content']['parts'][0];
            if (firstPart.containsKey('text')) {
              String rawText = firstPart['text'];
              // If a schema was used and mimeType was application/json, parse the stringified JSON
              if (generationConfig != null &&
                  generationConfig['responseMimeType'] == 'application/json') {
                try {
                  // Return the parsed JSON as a string, or you could return Map<String, dynamic>
                  // and handle it in ChatService. For simplicity in current flow, return string.
                  // ChatService will parse it from string to map.
                  return rawText; // The rawText will be the JSON string from Gemini
                } catch (e) {
                  _logger.e(
                    "GeminiService: Failed to parse JSON response: $rawText, Error: $e",
                  );
                  return rawText; // Fallback to raw text if JSON parsing fails
                }
              }
              return rawText; // Return raw text if no JSON schema was requested
            }
          }
          _logger.e(
            "GeminiService: Unexpected API response structure or missing text content: $jsonResponse",
          );
          throw Exception(
            "Failed to parse AI response: Unexpected structure or missing text.",
          );
        } else {
          _logger.e(
            "GeminiService: API call failed with status ${response.statusCode}: ${response.body}",
          );
          throw Exception(
            "Gemini API error: ${response.statusCode} - ${response.body}",
          );
        }
      } catch (e) {
        retryCount++;
        _logger.e("GeminiService: Error during API request: $e. Retry $retryCount/$maxRetries");
        if (retryCount >= maxRetries) {
          throw Exception("Failed to get response from Gemini API after $maxRetries attempts: $e");
        }
        await Future.delayed(Duration(seconds: delaySeconds));
        delaySeconds *= 2; // Exponential backoff
      }
    }
    throw Exception("Failed to get response from Gemini API after $maxRetries attempts.");
  }

  /// Corrects OCR errors in the given text using the GPT model.
  /// (Note: This is now routed through getChatResponse with a specific prompt).
  Future<String> correctOcrErrors(String ocrText) async {
    _logger.i("Correcting OCR errors for text: $ocrText");
    final prompt =
        "Correct any OCR errors in the following text and return only the corrected text:\n\"$ocrText\"";
    final messages = [
      {
        "role": "user",
        "parts": [
          {"text": prompt},
        ],
      },
    ];
    return await getChatResponse(messages);
  }

  /// Detects the language of the given text using the GPT model.
  /// (Note: This is now routed through getChatResponse with a specific prompt).
  Future<String> detectLanguage(String text) async {
    _logger.i("Detecting language for text: $text");
    final prompt =
        "Detect the language of the following text and return only the language name (e.g., English, Spanish, French):\n\"$text\"";
    final messages = [
      {
        "role": "user",
        "parts": [
          {"text": prompt},
        ],
      },
    ];
    return await getChatResponse(messages);
  }

  /// Translates the given text to the target language using the GPT model.
  /// (Note: This is now routed through getChatResponse with a specific prompt).
  Future<String> translateText(String text, String targetLanguage) async {
    _logger.i("Translating text to $targetLanguage: $text");
    final prompt =
        "Translate the following text into $targetLanguage:\n\"$text\"";
    final messages = [
      {
        "role": "user",
        "parts": [
          {"text": prompt},
        ],
      },
    ];
    return await getChatResponse(messages);
  }

  /// Generates an image using the Imagen 3.0 model.
  Future<String> generateImage(String prompt) async {
    if (!_networkService.isOnline) {
      _logger.e("GeminiService: No internet connection for Imagen API call.");
      throw Exception("No internet connection.");
    }

    // Imagen 3.0 uses a different predict endpoint
    const String imagenModelId = 'imagen-3.0-generate-002';
    final String url = '$_baseUrl/$imagenModelId:predict?key=$_apiKey';

    final Map<String, dynamic> payload = {
      'instances': {'prompt': prompt},
      'parameters': {'sampleCount': 1}, // Requesting one image
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        _logger.d("GeminiService: Raw Imagen API response: $jsonResponse");

        if (jsonResponse.containsKey('predictions') &&
            jsonResponse['predictions'] is List &&
            jsonResponse['predictions'].isNotEmpty &&
            jsonResponse['predictions'][0].containsKey('bytesBase64Encoded')) {
          final String base64Image =
              jsonResponse['predictions'][0]['bytesBase64Encoded'];
          final String imageUrl = 'data:image/png;base64,$base64Image';
          _logger.i("GeminiService: Image generated successfully.");
          return imageUrl;
        } else {
          _logger.e(
            "GeminiService: Unexpected Imagen API response structure: $jsonResponse",
          );
          throw Exception(
            "Failed to parse Imagen response: Unexpected structure.",
          );
        }
      } else {
        _logger.e(
          "GeminiService: Imagen API call failed with status ${response.statusCode}: ${response.body}",
        );
        throw Exception(
          "Imagen API error: ${response.statusCode} - ${response.body}",
        );
      }
    } catch (e) {
      _logger.e("GeminiService: Error during Imagen API request: $e");
      throw Exception("Failed to generate image: $e");
    }
  }

  /// Extracts text from an image using the Gemini 2.0 Flash (multimodal) model.
  /// This method is designed to use the Gemini model for image understanding.
  Future<String> extractTextFromImage(String imagePath) async {
    _logger.i("GeminiService: Extracting text from image: $imagePath");
    try {
      if (!_networkService.isOnline) {
        _logger.e(
          "GeminiService: No internet connection for image text extraction.",
        );
        throw Exception("No internet connection for image text extraction.");
      }

      final imageBytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final chatHistory = [
        {
          "role": "user",
          "parts": [
            {
              "text":
                  "Extract all readable text from this image as accurately as possible. Focus on complete words and sentences, even if they are broken across lines. Do not add any conversational filler, just the extracted text.",
            },
            {
              "inlineData": {"mimeType": "image/jpeg", "data": base64Image},
            }, // Assuming JPEG, adjust if needed
          ],
        },
      ];
      // Use the gemini-2.0-flash model for multimodal understanding
      return await getChatResponse(chatHistory, modelId: 'gemini-2.0-flash');
    } catch (e) {
      _logger.e("GeminiService: Error extracting text from image: $e");
      throw Exception("Failed to extract text from image using Gemini: $e");
    }
  }

  /// Describes an image using the Gemini 2.0 Flash (multimodal) model.
  Future<String> describeImage(String imagePath) async {
    _logger.i("GeminiService: Describing image: $imagePath");
    try {
      if (!_networkService.isOnline) {
        _logger.e(
          "GeminiService: No internet connection for image description.",
        );
        throw Exception("No internet connection for image description.");
      }

      final imageBytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final chatHistory = [
        {
          "role": "user",
          "parts": [
            {
              "text":
                  "Describe this image in detail, focusing on objects, people, environment, and general context. Be concise and precise. Max 100 words.",
            },
            {
              "inlineData": {"mimeType": "image/jpeg", "data": base64Image},
            }, // Assuming JPEG, adjust if needed
          ],
        },
      ];
      // Use the gemini-2.0-flash model for multimodal understanding
      return await getChatResponse(chatHistory, modelId: 'gemini-2.0-flash');
    } catch (e) {
      _logger.e("GeminiService: Error describing image: $e");
      throw Exception("Failed to describe image using Gemini: $e");
    }
  }

  void dispose() {
    _logger.i("GeminiService disposed.");
  }
}
