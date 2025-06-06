// lib/core/services/history_services.dart
import 'dart:convert'; // For jsonEncode and jsonDecode
import 'package:flutter/foundation.dart'; // For ChangeNotifier
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

import '../../main.dart'; // For global logger

class HistoryService extends ChangeNotifier {
  final Logger _logger = Logger();
  static const String _chatHistoryKey = 'chat_history';

  // Injected SharedPreferences instance
  final SharedPreferences _prefs; // NEW: Declare _prefs as final

  // Private list to hold the in-memory conversation history
  List<Map<String, String>> _conversationHistory = [];

  // Public getter for the conversation history
  List<Map<String, String>> getHistory() {
    return List.unmodifiable(_conversationHistory); // Return unmodifiable list
  }

  // NEW: Constructor now requires SharedPreferences
  HistoryService(this._prefs) {
    _logger.i("HistoryService initialized with SharedPreferences instance.");
  }

  /// Initializes the HistoryService by loading existing chat history from SharedPreferences.
  Future<void> init() async {
    _logger.i("Initializing HistoryService by loading history...");
    await _loadHistory();
    _logger.i("HistoryService initialized. Loaded ${_conversationHistory.length} entries.");
  }

  /// Loads the chat history from SharedPreferences into memory.
  Future<void> _loadHistory() async {
    try {
      // Use the injected _prefs instance
      final String? historyJson = _prefs.getString(_chatHistoryKey);
      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> decodedList = jsonDecode(historyJson);
        _conversationHistory = decodedList.map((item) {
          // Ensure that the map values are String, convert if necessary
          return Map<String, String>.from(item.map((key, value) => MapEntry(key, value.toString())));
        }).toList();
        _logger.d("Loaded chat history from SharedPreferences.");
      } else {
        _conversationHistory = [];
        _logger.d("No existing chat history found in SharedPreferences.");
      }
    } catch (e) {
      _logger.e("Error loading chat history from SharedPreferences: $e");
      _conversationHistory = []; // Clear history on error to prevent bad state
    }
    notifyListeners(); // Notify listeners after loading
  }

  /// Adds a new entry (message) to the chat history and saves it.
  Future<void> addEntry(String content, {String role = 'assistant'}) async {
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
    _conversationHistory = [];
    // Use the injected _prefs instance
    await _prefs.remove(_chatHistoryKey);
    _logger.i("Cleared chat history from memory and SharedPreferences.");
    notifyListeners(); // Notify listeners after clearing
  }

  /// Saves the current in-memory chat history to SharedPreferences.
  Future<void> _saveHistory() async {
    try {
      // Use the injected _prefs instance
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
