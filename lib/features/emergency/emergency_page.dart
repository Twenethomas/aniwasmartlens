// lib/features/emergency/pages/emergency_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart'; // Import for consistent fonts
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key});

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> {
  final Logger _logger = Logger();
  bool _isSendingSos = false;

  Future<bool> _requestPermissions() async {
    // Request Location Permission
    var locationStatus = await Permission.locationWhenInUse.status;
    if (!locationStatus.isGranted) {
      locationStatus = await Permission.locationWhenInUse.request();
    }
    if (!locationStatus.isGranted) {
      _showErrorSnackbar(
        'Location permission denied. Cannot send SOS with location.',
      );
      return false;
    }

    // SMS permission is not strictly needed for url_launcher with 'sms:' scheme,
    // as it delegates to the default SMS app, which handles its own permissions.
    return true;
  }

  Future<void> _sendSos() async {
    if (_isSendingSos) return;

    setState(() {
      _isSendingSos = true;
    });

    if (!await _requestPermissions()) {
      setState(() {
        _isSendingSos = false;
      });
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
      final contact =
          '0542845581'; // TODO: Replace with a dynamic contact from settings
      _logger.i("Preparing SOS for $contact: $message");

      final Uri smsLaunchUri = Uri(
        scheme: 'sms',
        path: contact,
        queryParameters: <String, String>{'body': message},
      );

      if (await canLaunchUrl(smsLaunchUri)) {
        await launchUrl(smsLaunchUri);
        _showSuccessSnackbar(
          'SOS prepared. Please send the message via your SMS app.',
        );
      } else {
        _showErrorSnackbar('Could not open SMS app. Is one installed?');
      }
    } on PlatformException catch (e) {
      _logger.e("Platform error during SOS: ${e.message}");
      _showErrorSnackbar('Permission error: ${e.message}');
    } catch (e) {
      _logger.e("Error sending SOS: $e");
      _showErrorSnackbar('Failed to send SOS. Please try again. Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingSos = false;
        });
      }
    }
  }

  void _showErrorSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(color: Theme.of(context).colorScheme.onError),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _showSuccessSnackbar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme =
        Theme.of(context).colorScheme; // Get colorScheme for easy access

    return Scaffold(
      backgroundColor: colorScheme.surface, // Use themed background color
      appBar: AppBar(
        backgroundColor: colorScheme.surface, // Themed app bar background
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Emergency',
          style: GoogleFonts.inter(
            // Changed font for consistency
            // Using Orbitron for consistent app titles
            color: colorScheme.primary, // Themed primary color
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.warning_amber,
              size: 80,
              color: colorScheme.error,
            ), // Themed error color
            const SizedBox(height: 20),
            Text(
              'Emergency Assistance',
              style: textTheme.headlineSmall?.copyWith(
                // Use textTheme
                color: colorScheme.onSurface, // Themed text color
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isSendingSos ? null : _sendSos,
              icon: Icon(
                Icons.sos_rounded, // Changed icon
                color: colorScheme.onError,
              ), // Themed on error color
              label: Text(
                _isSendingSos ? 'Sending SOS...' : 'Send SOS',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onError,
                ), // Use textTheme
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isSendingSos
                        ? Colors.grey
                        : colorScheme.error, // Themed error color
                foregroundColor:
                    colorScheme.onError, // Themed text color for foreground
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'This will send your location to emergency contacts',
              style: textTheme.bodySmall?.copyWith(
                // Use textTheme
                color: colorScheme.onSurface.withOpacity(
                  0.7,
                ), // Themed text color with opacity
              ), // Themed text color with opacity
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
