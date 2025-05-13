// lib/features/home/widgets/pairing_status_widget.dart
import 'package:flutter/material.dart';

class PairingStatusWidget extends StatelessWidget {
  const PairingStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: const [
            Icon(Icons.person, color: Colors.green),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Caretaker Status'),
                  SizedBox(height: 4),
                  Text('Connected', style: TextStyle(color: Colors.green)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.message),
              onPressed: null,
            ),
          ],
        ),
      ),
    );
  }
}