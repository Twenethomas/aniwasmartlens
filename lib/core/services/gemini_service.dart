// lib/core/services/gemini_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart'; // Import logger
import 'package:assist_lens/core/services/network_service.dart'; // Import NetworkService

// Global logger instance from main.dart
import '../../main.dart';

class GeminiService {
  final String _geminiApiKey = 'AIzaSyB_P6mKKBgw9acwZ2S3hC5HTSQxdNf6JME'; // IMPORTANT: Replace with your actual Gemini API Key
  final String _textModel = 'gemini-2.0-flash'; // Or 'gemini-1.5-flash', 'gemini-1.5-pro' depending on availability and needs
  final String _visionModel = 'gemini-pro-vision'; // For multimodal inputs
  final Logger _logger = logger; // Use the global logger
  final NetworkService _networkService; // Inject NetworkService

  GeminiService(this._networkService); // Constructor for dependency injection

  // Base API call for text generation
  Future<String> getGeminiResponse(List<Map<String, dynamic>> messages, {String model = 'gemini-2.0-flash'}) async {
    if (!_networkService.isOnline) {
      _logger.w("GeminiService: No internet connection. Cannot get Gemini response.");
      return "No internet connection. Please connect to the internet to use AI features.";
    }

    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_geminiApiKey');
    _logger.d("Sending Gemini request to: $url with model: $model");
    _logger.d("Messages: $messages");

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'contents': messages,
          // You can add generationConfig here if you need specific parameters
          'generationConfig': {
            'temperature': 0.7,
            'topK': 40,
            'topP': 0.95,
            'maxOutputTokens': 1024,
          },
        }),
      ).timeout(const Duration(seconds: 30)); // Add a timeout

      _logger.d("Gemini response status: ${response.statusCode}");
      _logger.d("Gemini response body: ${response.body}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          return data['candidates'][0]['content']['parts'][0]['text'];
        } else {
          _logger.w("GeminiService: No candidates found in response: ${response.body}");
          return "No response from AI. Please try again.";
        }
      } else {
        _logger.e("GeminiService: API Error ${response.statusCode}: ${response.body}");
        return "AI service error: ${response.statusCode}. Please try again.";
      }
    } on http.ClientException catch (e) {
      _logger.e("GeminiService: HTTP Client Error: $e");
      return "Network error occurred. Please check your internet connection.";
    } on FormatException catch (e) {
      _logger.e("GeminiService: JSON Format Error: $e");
      return "Failed to parse AI response.";
    } on TimeoutException {
      _logger.e("GeminiService: API request timed out.");
      return "AI response timed out. Please try again.";
    } catch (e) {
      _logger.e("GeminiService: Unexpected error during API call: $e");
      return "An unexpected error occurred with the AI service.";
    }
  }

  // --- NEW: Text Processing Methods for TextReaderState ---

  Future<String> correctOcrErrors(String text) async {
    _logger.d("GeminiService: Correcting OCR errors for: $text");
    final prompt = "Correct any OCR-related errors in the following text, and return only the corrected text. Do not add any conversational phrases or explanations:\n$text";
    return await getGeminiResponse([
      {'role': 'user', 'parts': [{'text': prompt}]}
    ], model: _textModel);
  }

  Future<String> detectLanguage(String text) async {
    _logger.d("GeminiService: Detecting language for: $text");
    final prompt = "Detect the language of the following text and return only the language name (e.g., 'English', 'French', 'Spanish'). Do not add any conversational phrases or explanations:\n$text";
    final response = await getGeminiResponse([
      {'role': 'user', 'parts': [{'text': prompt}]}
    ], model: _textModel);
    // Simple sanitization for a clean language name
    return response.replaceAll(RegExp(r'[^a-zA-Z\s]'), '').trim();
  }

  Future<String> translateText(String text, String targetLanguage) async {
    _logger.d("GeminiService: Translating '$text' to '$targetLanguage'");
    final prompt = "Translate the following text into $targetLanguage. Return only the translated text. Do not add any conversational phrases or explanations:\n$text";
    return await getGeminiResponse([
      {'role': 'user', 'parts': [{'text': prompt}]}
    ], model: _textModel);
  }


  // Original chat method
  Future<String> getChatResponse(List<Map<String, dynamic>> chatHistory) async {
    _logger.d("GeminiService: Getting chat response.");
    return await getGeminiResponse(chatHistory, model: _textModel);
  }

  // Original vision method
  Future<String> getVisionResponse(String prompt, String base64Image) async {
    if (!_networkService.isOnline) {
      _logger.w("GeminiService: No internet connection. Cannot get vision response.");
      return "No internet connection. Please connect to the internet to use AI features.";
    }

    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_visionModel:generateContent?key=$_geminiApiKey');
    _logger.d("Sending Gemini Vision request to: $url");

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
                {'inlineData': {'mimeType': 'image/jpeg', 'data': base64Image}}, // Assuming JPEG
              ],
            },
          ],
        }),
      ).timeout(const Duration(seconds: 45)); // Longer timeout for vision

      _logger.d("Gemini Vision response status: ${response.statusCode}");
      _logger.d("Gemini Vision response body: ${response.body}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          return data['candidates'][0]['content']['parts'][0]['text'];
        } else {
          _logger.w("GeminiService: No candidates found in vision response: ${response.body}");
          return "No response from AI for image. Please try again.";
        }
      } else {
        _logger.e("GeminiService: Vision API Error ${response.statusCode}: ${response.body}");
        return "AI vision service error: ${response.statusCode}. Please try again.";
      }
    } on http.ClientException catch (e) {
      _logger.e("GeminiService: HTTP Client Error for vision: $e");
      return "Network error occurred. Please check your internet connection for vision AI.";
    } on FormatException catch (e) {
      _logger.e("GeminiService: JSON Format Error for vision: $e");
      return "Failed to parse AI vision response.";
    } on TimeoutException {
      _logger.e("GeminiService: Vision API request timed out.");
      return "AI vision response timed out. Please try again.";
    } catch (e) {
      _logger.e("GeminiService: Unexpected error during vision API call: $e");
      return "An unexpected error occurred with the AI vision service.";
    }
  }
}
