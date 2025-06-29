// lib/features/emergency/pages/emergency_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_fonts/google_fonts.dart'; // Import for consistent fonts
import 'package:logger/logger.dart';
// import 'package:flutter_sms/flutter_sms.dart'; // Removed flutter_sms
import 'dart:io' show Platform; // Added for platform checking
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/routing/app_router.dart';
import '../aniwa_chat/state/chat_state.dart';
import '../../main.dart';

class EmergencyPage extends StatefulWidget {
  const EmergencyPage({super.key});

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> with RouteAware {
  final Logger _logger = Logger();
  bool _isSendingSos = false;
  late ChatState _chatState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatState = Provider.of<ChatState>(context, listen: false);
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    _chatState.updateCurrentRoute(AppRouter.emergency);
    _chatState.setChatPageActive(true);
    _chatState.resume();
  }

  @override
  void didPopNext() {
    _chatState.updateCurrentRoute(AppRouter.emergency);
    _chatState.setChatPageActive(true);
    _chatState.resume();
  }

  @override
  void didPushNext() {
    _chatState.setChatPageActive(false);
    _chatState.pause();
  }

  @override
  void didPop() {
    _chatState.setChatPageActive(false);
    _chatState.pause();
  }

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

    // SMS permission is implicitly handled by url_launcher opening the default SMS app.
    // No need to explicitly request Permission.sms if not using direct send.
    // if (Platform.isAndroid) {
    //   var smsStatus = await Permission.sms.status;
    //   if (!smsStatus.isGranted) {
    //     _logger.i("Requesting SMS permission for direct send.");
    //     smsStatus = await Permission.sms.request();
    //   }
    //   if (!smsStatus.isGranted) {
    //     _logger.w(
    //       "SMS permission denied for direct send. Will fallback to opening SMS app.",
    //     );
    //   }
    // }
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
      _logger.i("Fetching current location using getPositionStream().first...");
      LocationSettings locationSettings;
      if (Platform.isAndroid) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          // distanceFilter: 100, // Optional: Define a distance filter
          // forceLocationManager: false, // Optional
        );
      } else if (Platform.isIOS || Platform.isMacOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.other, // General activity type
          // distanceFilter: 100, // Optional
          // pauseAutomatically: true, // Optional
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          // distanceFilter: 100, // Optional
        );
      }

      Position position =
          await Geolocator.getPositionStream(locationSettings: locationSettings)
              .timeout(
                const Duration(seconds: 20),
              ) // Apply timeout to the stream
              .first;
      _logger.i(
        "Location fetched: ${position.latitude}, ${position.longitude}",
      );

      final message =
          "SOS! I need help. My current location is: http://maps.google.com/maps?q=${position.latitude},${position.longitude}";
      final contact =
          '0542845581'; // TODO: Replace with a dynamic contact from settings
      _logger.i("Preparing SOS for $contact: $message");

      // Always use url_launcher to open the default SMS app
      await _launchSmsWithUrlLauncher(contact, message);
    } on PlatformException catch (e, s) {
      _logger.e(
        "Platform error during SOS: ${e.message}",
        error: e,
        stackTrace: s,
      );
      _showErrorSnackbar('SOS failed due to a platform issue: ${e.message}');
    } catch (e, s) {
      _logger.e("Error sending SOS: $e", error: e, stackTrace: s);
      _showErrorSnackbar('Failed to send SOS. An unexpected error occurred.');
    } finally {
      if (mounted) {
        setState(() {
          _isSendingSos = false;
        });
      }
    }
  }

  Future<void> _launchSmsWithUrlLauncher(String contact, String message) async {
    _logger.i("Launching SMS app with pre-filled message for $contact.");
    final Uri smsLaunchUri = Uri(
      scheme: 'sms',
      path: contact,
      queryParameters: <String, String>{'body': message},
    );

    if (await canLaunchUrl(smsLaunchUri)) {
      await launchUrl(smsLaunchUri);
      _showSuccessSnackbar(
        'SOS prepared. Please confirm and send the message via your SMS app.',
      );
    } else {
      _showErrorSnackbar('Could not open SMS app. Is one installed?');
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
                color: colorScheme.onSurface.withAlpha(
                  (0.7 * 255).round(),
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
