// lib/features/settings/state/settings_state.dart
import 'package:flutter/material.dart';
import 'package:assist_lens/core/services/speech_service.dart';
import 'package:assist_lens/core/services/history_services.dart';
import 'package:assist_lens/state/app_state.dart';
import 'package:assist_lens/main.dart'; // for logger

class SettingsState extends ChangeNotifier {
  final SpeechService _speechService;
  final AppState _appState;
  final HistoryService _historyService;

  SettingsState({
    required SpeechService speechService,
    required AppState appState,
    required HistoryService historyService,
  }) : _speechService = speechService,
       _appState = appState,
       _historyService = historyService {
    // Listen to changes in the services to keep UI in sync
    _speechService.addListener(_onSettingsChanged);
    _appState.addListener(_onSettingsChanged);
  }

  // Getters for UI
  double get speechVolume => _speechService.currentVolume;
  double get speechRate => _speechService.currentSpeechRate;
  double get speechPitch => _speechService.currentPitch;

  void _onSettingsChanged() {
    notifyListeners();
  }

  // Setters for UI controls
  Future<void> setSpeechVolume(double volume) async {
    await _speechService.setVolume(volume);
    // notifyListeners() will be called by _onSettingsChanged via the listener
  }

  Future<void> setSpeechRate(double rate) async {
    await _speechService.setSpeechRate(rate);
  }

  Future<void> setSpeechPitch(double pitch) async {
    await _speechService.setPitch(pitch);
  }

  Future<void> clearChatHistory() async {
    await _historyService.clearHistory();
    logger.i("SettingsState: Chat history cleared.");
    // HistoryService will notify its listeners, which ChatState listens to.
  }

  Future<void> resetApp() async {
    await _appState.resetAppState();
    logger.i("SettingsState: App state reset.");
    // AppState will notify its listeners.
  }

  @override
  void dispose() {
    _speechService.removeListener(_onSettingsChanged);
    _appState.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
