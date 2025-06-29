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
  static const String _themeModeKey = 'themeMode';
  static const String _gemini2EnabledKey = 'gemini2Enabled';
  static const String _userImageKey = 'userImage';

  // Internal state fields
  bool _onboardingComplete;
  String _userName;
  int _currentTabIndex;
  ThemeMode _currentThemeMode;
  bool _isGemini2Enabled;
  String? _userImagePath;

  // Getters
  bool get onboardingComplete => _onboardingComplete;
  String get userName => _userName; // <--- This getter is now defined
  int get currentTabIndex => _currentTabIndex;
  ThemeMode get currentThemeMode => _currentThemeMode;
  bool get isGemini2Enabled => _isGemini2Enabled;
  String? get userImagePath => _userImagePath;

  AppState(this._prefs)
    : _onboardingComplete = _prefs.getBool(_onboardingCompleteKey) ?? false,
      _userName = _prefs.getString(_userNameKey) ?? 'Guest',
      _currentTabIndex = _prefs.getInt(_currentTabIndexKey) ?? 0,
      _currentThemeMode = ThemeMode.values[_prefs.getInt(_themeModeKey) ?? 0],
      _isGemini2Enabled = _prefs.getBool(_gemini2EnabledKey) ?? false,
      _userImagePath = _prefs.getString(_userImageKey) {
    _logger.i(
      "AppState initialized. Onboarding: $_onboardingComplete, User: $_userName, Tab: $_currentTabIndex, ThemeMode: $_currentThemeMode, Gemini2Enabled: $_isGemini2Enabled, UserImagePath: $_userImagePath",
    );
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

  set userImagePath(String? value) {
    if (_userImagePath != value) {
      _userImagePath = value;
      if (value != null) {
        _prefs.setString(_userImageKey, value);
      } else {
        _prefs.remove(_userImageKey);
      }
      _logger.d("User image path set to: $value");
      notifyListeners();
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (_currentThemeMode != mode) {
      _currentThemeMode = mode;
      _prefs.setInt(_themeModeKey, mode.index);
      _logger.d("Theme mode set to: $mode");
      notifyListeners();
    }
  }

  void setGemini2Enabled(bool enabled) {
    if (_isGemini2Enabled != enabled) {
      _isGemini2Enabled = enabled;
      _prefs.setBool(_gemini2EnabledKey, enabled);
      _logger.d("Gemini 2.0 ${enabled ? 'enabled' : 'disabled'}");
      notifyListeners();
    }
  }

  // Optional: A method to reset all app state (e.g., for logout or re-onboarding)
  Future<void> resetAppState() async {
    _onboardingComplete = false;
    _userName = 'Guest';
    _currentTabIndex = 0;
    _currentThemeMode = ThemeMode.system;
    _isGemini2Enabled = false;
    _userImagePath = null;
    await _prefs.clear(); // Clears all data stored by the app
    _logger.i("AppState reset. All SharedPreferences cleared.");
    notifyListeners();
  }
}
