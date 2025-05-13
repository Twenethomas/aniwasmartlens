// lib/features/emergency/pages/emergency_page.dart
import 'package:flutter/material.dart';
import 'package:telephony/telephony.dart';
import 'package:geolocator/geolocator.dart';

class EmergencyPage extends StatelessWidget {
  const EmergencyPage({super.key});

  Future<void> _sendSos() async {
    final location = await Geolocator.getCurrentPosition();
    final message = "SOS! My location: ${location.latitude},${location.longitude}";
    
    final contact = '0542845581'; // Should be dynamic
    final telephony = Telephony.instance;
    await telephony.sendSms(to: contact, message: message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red[50],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber, size: 80, color: Colors.red),
            const SizedBox(height: 20),
            const Text(
              'Emergency Assistance',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _sendSos,
              icon: const Icon(Icons.send),
              label: const Text('Send SOS'),
            ),
            const SizedBox(height: 20),
            const Text('This will send your location to emergency contacts'),
          ],
        ),
      ),
    );
  }
}