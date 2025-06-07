// lib/features/emergency/emergency_state.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyState extends ChangeNotifier {
  final Logger _logger = Logger();
  bool _isSendingSos = false;
  String? _errorMessage;
  String? _successMessage;

  bool get isSendingSos => _isSendingSos;
  String? get errorMessage => _errorMessage;
  String? get successMessage => _successMessage;

  void clearMessages() {
    _errorMessage = null;
    _successMessage = null;
    // No need to notifyListeners if UI isn't directly observing these for clearing
  }

  Future<bool> _requestPermissions() async {
    var locationStatus = await Permission.locationWhenInUse.status;
    if (!locationStatus.isGranted) {
      locationStatus = await Permission.locationWhenInUse.request();
    }
    if (!locationStatus.isGranted) {
      _errorMessage =
          'Location permission denied. Cannot send SOS with location.';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> sendSos() async {
    if (_isSendingSos) return;

    _isSendingSos = true;
    _errorMessage = null;
    _successMessage = null;
    notifyListeners();

    if (!await _requestPermissions()) {
      _isSendingSos = false;
      notifyListeners(); // Error message is already set in _requestPermissions
      return;
    }

    try {
      _logger.i("Fetching current location...");
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
      _logger.i(
        "Location fetched: ${position.latitude}, ${position.longitude}",
      );

      final message =
          "SOS! I need help. My current location is: http://maps.google.com/maps?q=${position.latitude},${position.longitude}";
      final contact = '0542845581'; // TODO: Replace with a dynamic contact
      _logger.i("Preparing SOS for $contact: $message");

      final Uri smsLaunchUri = Uri(
        scheme: 'sms',
        path: contact,
        queryParameters: <String, String>{'body': message},
      );

      if (await canLaunchUrl(smsLaunchUri)) {
        await launchUrl(smsLaunchUri);
        _successMessage =
            'SOS prepared. Please send the message via your SMS app.';
      } else {
        _errorMessage = 'Could not open SMS app. Is one installed?';
      }
    } on PlatformException catch (e) {
      _logger.e("Platform error during SOS: ${e.message}");
      _errorMessage = 'Permission error: ${e.message}';
    } catch (e) {
      _logger.e("Error sending SOS: $e");
      _errorMessage = 'Failed to send SOS. Please try again. Error: $e';
    } finally {
      _isSendingSos = false;
      notifyListeners();
    }
  }
}
