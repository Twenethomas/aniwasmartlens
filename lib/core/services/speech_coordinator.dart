// lib/core/services/speech_coordinator.dart
import 'dart:async';
import 'package:logger/logger.dart';
import 'speech_service.dart';

/// A centralized service to coordinate speech output requests from multiple sources,
/// ensuring serialized, non-overlapping speech and managing speech state.
class SpeechCoordinator {
  final SpeechService _speechService;
  final Logger _logger = Logger();

  SpeechService get speechService => _speechService;

  // Queue of speech requests
  final List<_SpeechRequest> _speechQueue = [];

  // Current speech request being processed
  _SpeechRequest? _currentRequest;

  // Completer to track when current speech finishes
  Completer<void>? _speechCompleter;

  // Whether the speech service is currently speaking
  bool get isSpeaking => _speechService.isSpeaking;

  SpeechCoordinator(this._speechService) {
    // Listen to speech service speaking status to know when speech ends
    _speechService.speakingStatusStream.listen((speaking) {
      if (!speaking) {
        _onSpeechFinished();
      }
    });
  }

  /// Request to speak a text string.
  /// Returns a Future that completes when the speech finishes.
  Future<void> speak(String text) {
    final request = _SpeechRequest(text);
    _speechQueue.add(request);
    _logger.i('SpeechCoordinator: Added speech request: "$text"');
    _tryProcessNext();
    return request.completer.future;
  }

  /// Stops any ongoing speech and clears the queue.
  Future<void> stopSpeaking() async {
    _logger.i('SpeechCoordinator: Stopping speech and clearing queue.');
    _speechQueue.clear();
    _currentRequest = null;
    _speechCompleter = null;
    await _speechService.stopSpeaking();
  }

  /// Internal method to start next speech request if none is active.
  void _tryProcessNext() {
    if (_currentRequest != null) {
      // Already speaking
      return;
    }
    if (_speechQueue.isEmpty) {
      return;
    }
    _currentRequest = _speechQueue.removeAt(0);
    _speechCompleter = Completer<void>();
    _logger.i('SpeechCoordinator: Starting speech: "${_currentRequest!.text}"');
    _speechService.speak(_currentRequest!.text).then((_) {
      // SpeechService.speak completes when speech starts, not ends
      // We rely on speakingStatusStream to detect end
    }).catchError((e) {
      _logger.e('SpeechCoordinator: Error during speech: $e');
      _speechCompleter?.completeError(e);
      _currentRequest = null;
      _speechCompleter = null;
      _tryProcessNext();
    });
  }

  /// Called when speech finishes to complete current request and start next.
  void _onSpeechFinished() {
    if (_currentRequest != null) {
      _logger.i('SpeechCoordinator: Speech finished: "${_currentRequest!.text}"');
      _currentRequest!.completer.complete();
      _currentRequest = null;
      _speechCompleter = null;
      // Start next speech if any
      _tryProcessNext();
    }
  }
}

class _SpeechRequest {
  final String text;
  final Completer<void> completer = Completer<void>();

  _SpeechRequest(this.text);
}
