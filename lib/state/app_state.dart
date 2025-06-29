// lib/state/app_state.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart'; // Import logger

import '../main.dart'; // For global logger

class AppState extends ChangeNotifier {
  final SharedPreferences _prefs;
  final Logger _logger = logger; // Use the global logger

  // Keys for SharedPreferences
  static const String _onboardingCompleteKey = 'onboardingComplete';
  static const String _userNameKey = 'userName';
  static const String _currentTabIndexKey = 'currentTabIndex';

  // Internal state fields
  bool _onboardingComplete;
  String _userName;
  int _currentTabIndex;

  // Getters
  bool get onboardingComplete => _onboardingComplete;
  String get userName => _userName; // <--- This getter is now defined
  int get currentTabIndex => _currentTabIndex;

  AppState(this._prefs)
      : _onboardingComplete = _prefs.getBool(_onboardingCompleteKey) ?? false,
        _userName = _prefs.getString(_userNameKey) ?? 'Guest',
        _currentTabIndex = _prefs.getInt(_currentTabIndexKey) ?? 0 {
    _logger.i("AppState initialized. Onboarding: $_onboardingComplete, User: $_userName, Tab: $_currentTabIndex");
  }

  // Setters and associated persistence logic
  set onboardingComplete(bool value) {
    if (_onboardingComplete != value) {
      _onboardingComplete = value;
      _prefs.setBool(_onboardingCompleteKey, value);
      _logger.d("Onboarding status set to: $value");
      notifyListeners();
    }
  }

  set userName(String value) {
    if (_userName != value) {
      _userName = value;
      _prefs.setString(_userNameKey, value);
      _logger.d("User name set to: $value");
      notifyListeners();
    }
  }

  set currentTabIndex(int value) {
    if (_currentTabIndex != value) {
      _currentTabIndex = value;
      _prefs.setInt(_currentTabIndexKey, value);
      _logger.d("Current tab index set to: $value");
      notifyListeners();
    }
  }

  // Optional: A method to reset all app state (e.g., for logout or re-onboarding)
  Future<void> resetAppState() async {
    _onboardingComplete = false;
    _userName = 'Guest';
    _currentTabIndex = 0;
    await _prefs.clear(); // Clears all data stored by the app
    _logger.i("AppState reset. All SharedPreferences cleared.");
    notifyListeners();
  }
}
