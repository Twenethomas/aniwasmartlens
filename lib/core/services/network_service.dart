// lib/core/services/network_service.dart
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart'; // For ChangeNotifier
import 'package:logger/logger.dart';

import '../../main.dart'; // For global logger

class NetworkService extends ChangeNotifier {
  final Logger _logger = logger; // Use the global logger
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Use a private backing field and public getter/setter for isOnline
  // so that notifyListeners can be called when it changes.
  bool _isOnline = false;

  bool get isOnline => _isOnline;

  // Setter to allow external modification and trigger notifyListeners
  set isOnline(bool value) {
    if (_isOnline != value) {
      _isOnline = value;
      notifyListeners();
      _logger.i('NetworkService: Connectivity status changed to $_isOnline');
    }
  }

  NetworkService() {
    _logger.i("NetworkService: Initializing.");
  }

  /// Initializes the network service and starts listening for connectivity changes.
  Future<void> init() async {
    // Check initial connectivity status
    final initialResult = await Connectivity().checkConnectivity();
    isOnline = !initialResult.contains(ConnectivityResult.none);
    _logger.i("NetworkService: Initial connectivity status: $isOnline");

    // Listen for future changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      isOnline = !results.contains(ConnectivityResult.none);
    });
  }

  /// Manually checks the current network connection status.
  /// This is useful for one-off checks before an API call.
  Future<bool> checkConnectionAndReturnStatus() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    final newStatus = !connectivityResult.contains(ConnectivityResult.none);
    // Update internal state and notify listeners only if different
    isOnline = newStatus; // This setter will handle notifyListeners
    return newStatus;
  }

  @override
  void dispose() {
    _logger.i("NetworkService: Disposing.");
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
