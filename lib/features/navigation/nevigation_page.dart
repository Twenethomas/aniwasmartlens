// lib/features/navigation/pages/navigation_page.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class NavigationPage extends StatefulWidget {
  const NavigationPage({super.key});

  @override
  _NavigationPageState createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  late final MapController _mapController;
  late Position _currentLocation;

  @override
  void initState() {
    super.initState();
    _initMap();
  }

  Future<void> _initMap() async {
    final location = await Geolocator.getCurrentPosition();
    setState(() {
      _mapController = MapController();
      _mapController.move(LatLng(location.latitude, location.longitude), 15);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getLocation,
          )
        ],
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: _currentLocation != null 
            ? LatLng(_currentLocation.latitude, _currentLocation.longitude)
            : LatLng(0, 0), // Provide a default value for initialCenter
          minZoom: 15,
        ),
        mapController: _mapController,
        children: [
          TileLayer(
            urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            subdomains: ['a', 'b', 'c'],
          ),
          if (_currentLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  width: 80.0,
                  height: 80.0,
                  point: LatLng(_currentLocation.latitude, _currentLocation.longitude),
                  child: const Icon(Icons.location_on, size: 32, color: Colors.red),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _getLocation() async {
    final location = await Geolocator.getCurrentPosition();
    setState(() => _currentLocation = location);
  }
}