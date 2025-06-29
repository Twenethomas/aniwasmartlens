// lib/core/services/history_services.dart
import 'dart:convert'; // For jsonEncode and jsonDecode
import 'package:flutter/foundation.dart'; // For ChangeNotifier
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

import '../../main.dart'; // For global logger

/// A service to manage the application's conversation history.
/// It uses SharedPreferences for persistence and extends ChangeNotifier
/// to notify listeners of history updates.
class HistoryService extends ChangeNotifier {
  final Logger _logger = logger; // Use global logger
  static const String _chatHistoryKey = 'chat_history';

  // Injected SharedPreferences instance
  final SharedPreferences _prefs;
  bool _isInitialized = false; // Flag to track if the service has been initialized

  // Private list to hold the in-memory conversation history
  List<Map<String, String>> _conversationHistory = [];

  // Public getter for the conversation history
  List<Map<String, String>> getHistory() {
    // If not initialized, try to load it now to ensure data is available,
    // or return an empty list if initialization fails.
    if (!_isInitialized) {
      _logger.w("HistoryService accessed before initialization. Attempting to load history.");
      _loadHistory(); // Attempt to load synchronously, though init() is preferred for async.
    }
    return List.unmodifiable(_conversationHistory); // Return unmodifiable list
  }

  /// Constructor now requires SharedPreferences.
  HistoryService(this._prefs) {
    _logger.i("HistoryService initialized with SharedPreferences instance.");
  }

  /// Initializes the HistoryService by loading existing chat history from SharedPreferences.
  Future<void> init() async {
    _logger.i("Initializing HistoryService by loading history...");
    await _loadHistory();
    _isInitialized = true; // Set initialized flag after loading
    _logger.i("HistoryService initialized. Loaded ${_conversationHistory.length} entries.");
  }

  /// Loads the chat history from SharedPreferences into memory.
  Future<void> _loadHistory() async {
    try {
      final String? historyJson = _prefs.getString(_chatHistoryKey);
      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> decodedList = jsonDecode(historyJson);
        _conversationHistory = decodedList.map((item) {
          // Robustly convert each item to Map<String, String>.
          // Handle cases where content might be nested (e.g., from Gemini's 'parts' array).
          final Map<String, dynamic> entryMap = Map<String, dynamic>.from(item);
          final String role = entryMap['role']?.toString() ?? 'unknown';
          String content = '';

          // If 'content' is a simple string
          if (entryMap['content'] is String) {
            content = entryMap['content'].toString();
          }
          // If 'content' is a list (e.g., from Gemini's 'parts' array)
          else if (entryMap['content'] is List) {
            final List<dynamic> parts = entryMap['content'];
            content = parts.map((part) => part['text']?.toString() ?? '').join(' ');
          }
          // If 'parts' is a top-level key (another common Gemini response structure)
          else if (entryMap['parts'] is List) {
            final List<dynamic> parts = entryMap['parts'];
            content = parts.map((part) => part['text']?.toString() ?? '').join(' ');
          }

          return {'role': role, 'content': content};
        }).toList();
        _logger.d("Loaded chat history from SharedPreferences: ${_conversationHistory.length} entries.");
      } else {
        _conversationHistory = [];
        _logger.d("No existing chat history found in SharedPreferences.");
      }
    } catch (e) {
      _logger.e("Error loading chat history from SharedPreferences: $e");
      _conversationHistory = []; // Clear history on error to prevent bad state
    }
    // No notifyListeners here; it's called by the init() method when the service is ready.
  }

  /// Adds a new entry (message) to the chat history and saves it.
  Future<void> addEntry(String content, {String role = 'assistant'}) async {
    if (!_isInitialized) {
      _logger.e("HistoryService not initialized. Cannot add entry '$content'. Call init() first.");
      return;
    }
    _conversationHistory.add({"role": role, "content": content});
    await _saveHistory();
    _logger.d("Added new history entry: $role - $content");
    notifyListeners(); // Notify listeners after adding
  }

  /// Adds a user message to the chat history.
  Future<void> addUserMessage(String content) async {
    await addEntry(content, role: 'user');
  }

  /// Adds an assistant message to the chat history.
  Future<void> addAssistantMessage(String content) async {
    await addEntry(content, role: 'assistant');
  }

  /// Clears the entire chat history from memory and SharedPreferences.
  Future<void> clearHistory() async {
    if (!_isInitialized) {
      _logger.e("HistoryService not initialized. Cannot clear history. Call init() first.");
      return;
    }
    _conversationHistory = [];
    await _prefs.remove(_chatHistoryKey);
    _logger.i("Cleared chat history from memory and SharedPreferences.");
    notifyListeners(); // Notify listeners after clearing
  }

  /// Saves the current in-memory chat history to SharedPreferences.
  Future<void> _saveHistory() async {
    if (!_isInitialized) {
      _logger.e("HistoryService not initialized. Cannot save history. Call init() first.");
      return;
    }
    try {
      final String historyJson = jsonEncode(_conversationHistory);
      await _prefs.setString(_chatHistoryKey, historyJson);
      _logger.d("Saved chat history to SharedPreferences.");
    } catch (e) {
      _logger.e("Error saving chat history to SharedPreferences: $e");
    }
  }

  @override
  void dispose() {
    _logger.i("Disposing HistoryService.");
    // No specific streams or listeners to cancel here, as it's primarily storage
    super.dispose();
  }
}
