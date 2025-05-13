// lib/core/services/network_service.dart
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NetworkService with ChangeNotifier {
  bool _isOnline = true;

  bool get isOnline => _isOnline;

  Future<void> init() async {
    final connectivityResult = await (Connectivity().checkConnectivity());
    _isOnline = connectivityResult != ConnectivityResult.none;
    notifyListeners();
  }

  Future<void> checkConnection(Function(BuildContext) builder) async {
    final prefs = await SharedPreferences.getInstance();
    final connectivityResult = await Connectivity().checkConnectivity();
    _isOnline = connectivityResult != ConnectivityResult.none;
    notifyListeners();
  }
}