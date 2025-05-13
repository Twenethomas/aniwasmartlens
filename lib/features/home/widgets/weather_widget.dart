import 'package:flutter/material.dart';

class WeatherWidget extends StatelessWidget {
  const WeatherWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: replace with real weather data
    return Row(
      children: const [
        Icon(Icons.wb_sunny, size: 20, color: Colors.orange),
        SizedBox(width: 4),
        Text('28°C'),
      ],
    );
  }
}
