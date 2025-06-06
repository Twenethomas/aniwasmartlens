import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart'
    as latlong2; // Explicitly import LatLng from latlong2 with a prefix
import 'package:permission_handler/permission_handler.dart';
import 'package:assist_lens/core/services/speech_service.dart'; // Import SpeechService
import 'package:logger/logger.dart';
import 'package:google_fonts/google_fonts.dart'; // Added import for GoogleFonts

import 'package:assist_lens/main.dart'; // For routeObserver
// We will assume active_navigation_screen.dart will also use latlong2.LatLng
// So, we don't need to hide LatLng from it anymore.
import 'package:assist_lens/core/routing/app_router.dart';
import 'package:vibration/vibration.dart'; // Import AppRouter

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with TickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  final Logger _logger = Logger();
  final _formKey = GlobalKey<FormState>(); // For text field
  final TextEditingController _destinationController = TextEditingController();
  late MapController _mapController;
  latlong2.LatLng? _currentLocation;
  latlong2.LatLng? _destinationLocation;
  Marker? _destinationMarker;
  String _currentAddress = 'Fetching current location...';
  String _destinationAddress = '';
  StreamSubscription<Position>? _positionStreamSubscription;
  final SpeechService _speechService = SpeechService();

  bool _isLocationServiceEnabled = false;
  LocationPermission _locationPermission = LocationPermission.denied;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(
      this,
    ); // Add observer for lifecycle events
    _mapController = MapController();
    _checkLocationPermissions();
    _startLocationUpdates();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute? route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  // --- RouteAware Methods ---
  @override
  void didPush() {
    _logger.i("MapScreen: didPush - Page is active.");
    _startLocationUpdates(); // Resume location updates when page is pushed
    super.didPush();
  }

  @override
  void didPopNext() {
    _logger.i("MapScreen: didPopNext - Returning to page.");
    _startLocationUpdates(); // Resume location updates when returning to page
    super.didPopNext();
  }

  @override
  void didPushNext() {
    _logger.i("MapScreen: didPushNext - Navigating away from page.");
    _positionStreamSubscription
        ?.cancel(); // Stop location updates when navigating away
    super.didPushNext();
  }

  @override
  void didPop() {
    _logger.i("MapScreen: didPop - Page is being popped.");
    _positionStreamSubscription
        ?.cancel(); // Stop location updates when page is popped
    super.didPop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _logger.i("App inactive, stopping location updates.");
      _positionStreamSubscription?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _logger.i("App resumed, restarting location updates.");
      _checkLocationPermissions();
      _startLocationUpdates();
    }
  }

  Future<void> _checkLocationPermissions() async {
    _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    _locationPermission = await Geolocator.checkPermission();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startLocationUpdates() async {
    if (!_isLocationServiceEnabled ||
        _locationPermission == LocationPermission.denied ||
        _locationPermission == LocationPermission.deniedForever) {
      _logger.w(
        "Location services not enabled or permissions denied. Requesting...",
      );
      await Geolocator.requestPermission();
      await _checkLocationPermissions(); // Re-check after requesting
      if (!mounted ||
          !_isLocationServiceEnabled || // Added mounted check
          _locationPermission == LocationPermission.denied ||
          _locationPermission == LocationPermission.deniedForever) {
        _speechService.speak(
          "Location services are not enabled or permissions are denied. Please enable them in your settings.",
        );
        return;
      }
    }

    _positionStreamSubscription?.cancel(); // Cancel any existing subscription

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters
      ),
    ).listen(
      (Position position) {
        if (mounted) {
          setState(() {
            _currentLocation = latlong2.LatLng(
              position.latitude,
              position.longitude,
            );
            _mapController.move(
              _currentLocation!,
              _mapController.camera.zoom,
            ); // Corrected to .camera.zoom
          });
          _resolveCurrentAddress(position);
        }
      },
      onError: (e) {
        _logger.e("Error getting location stream: $e");
        _speechService.speak(
          "Failed to get your current location. Please check your device settings.",
        );
      },
    );
  }

  Future<void> _resolveCurrentAddress(Position position) async {
    try {
      List<geocoding.Placemark> placemarks = await geocoding
          .placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        if (mounted) {
          // Added mounted check
          setState(() {
            _currentAddress =
                '${placemark.street}, ${placemark.locality}, ${placemark.country}';
          });
        }
      }
    } catch (e) {
      _logger.e("Error resolving current address: $e");
      if (mounted) {
        // Added mounted check
        setState(() {
          _currentAddress = 'Address not found.';
        });
      }
    }
  }

  //   Future<void> _resolveDestinationAddress() async {
  //     try {
  //       List<geocoding.Placemark> placemarks =
  //  await geocoding.placemarkFromCoordinates(
  //  widget.destinationLocation!.latitude,
  //         widget.destination.longitude,
  //       );
  //       if (placemarks.isNotEmpty) {
  //         final placemark = placemarks.first;
  //         if (mounted) { // Added mounted check
  //           setState(() {
  //             _destinationAddress =
  //                 '${placemark.street}, ${placemark.locality}, ${placemark.country}';
  //           });
  //         }
  //       }
  //     } catch (e) {
  //       _logger.e("Error resolving destination address: $e");
  //       if (mounted) { // Added mounted check
  //         setState(() {
  //           _destinationAddress = 'Destination address not found.';
  //         });
  //       }
  //     }
  //   }

  Future<void> _searchDestination(String query) async {
    if (query.isEmpty) {
      _speechService.speak("Please enter a destination to search.");
      return;
    }

    try {
      List<geocoding.Location> locations = await geocoding.locationFromAddress(
        query,
      );
      if (locations.isNotEmpty) {
        final location = locations.first;
        final latlng = latlong2.LatLng(location.latitude, location.longitude);
        if (mounted) {
          setState(() {
            _destinationLocation = latlng;
            _destinationMarker = Marker(
              point: _destinationLocation!,
              width: 80,
              height: 80,
              child: const Icon(
                Icons.location_pin,
                color: Colors.red,
                size: 40,
              ),
            );
          });
          _mapController.move(
            latlng,
            15.0,
          ); // Move map to the searched location
          _resolveDestinationAddressFromLatLng(
            latlng,
          ); // Resolve address for the found location
        }
      } else {
        _speechService.speak(
          "Could not find a location for '$query'. Please try a different query.",
        );
      }
    } catch (e) {
      _logger.e("Error searching for destination: $e");
      _speechService.speak(
        "An error occurred while searching for the destination.",
      );
    }
  }

  void _startActiveNavigation() {
    if (_currentLocation != null && _destinationLocation != null) {
      _positionStreamSubscription?.cancel(); // Stop passive updates
      Navigator.of(context).pushNamed(
        AppRouter.activeNavigation,
        arguments: {
          'initialPosition': Position(
            latitude: _currentLocation!.latitude,
            longitude: _currentLocation!.longitude,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          ),
          'destination': _destinationLocation!,
        },
      );
    } else {
      _speechService.speak(
        "Please set both your current location and a destination to start navigation.",
      );
    }
  }

  Future<void> _resolveDestinationAddressFromLatLng(
    latlong2.LatLng latlng,
  ) async {
    try {
      List<geocoding.Placemark> placemarks = await geocoding
          .placemarkFromCoordinates(latlng.latitude, latlng.longitude);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        if (mounted) {
          setState(() {
            _destinationAddress =
                '${placemark.street}, ${placemark.locality}, ${placemark.country}';
          });
        }
      }
    } catch (e) {
      _logger.e("Error resolving destination address from LatLng: $e");
      if (mounted) {
        setState(() {
          _destinationAddress = 'Destination address not found.';
        });
      }
    }
  }

  @override
  void dispose() {
    _logger.i("MapScreen disposed, releasing resources.");
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _positionStreamSubscription?.cancel();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        backgroundColor: colorScheme.primary,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colorScheme.onPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline, color: colorScheme.onPrimary),
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'Assist Lens',
                applicationVersion: '1.0.0',
                applicationIcon: const Icon(Icons.navigation),
                children: [
                  Text(
                    'This feature helps you navigate to a destination using your current location and object detection.',
                    style: GoogleFonts.inter(
                      // Corrected GoogleFonts usage
                      color: colorScheme.onSurface,
                      fontSize: 16,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Form(
              key: _formKey,
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _destinationController,
                      decoration: InputDecoration(
                        labelText: 'Enter Destination',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed:
                              () => _searchDestination(
                                _destinationController.text.trim(),
                              ),
                        ),
                      ),
                      onFieldSubmitted: _searchDestination,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed:
                        () => _searchDestination(
                          _destinationController.text.trim(),
                        ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Search'),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Text(
              'Current Address: $_currentAddress',
              style: TextStyle(
                color: colorScheme.onSurface.withAlpha((0.7 * 255).round()),
              ), // Using withAlpha
            ),
          ),
          if (_destinationLocation != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 4.0,
              ),
              child: Text(
                'Destination Address: $_destinationAddress',
                style: TextStyle(
                  color: colorScheme.onSurface.withAlpha((0.7 * 255).round()),
                ), // Using withAlpha
              ),
            ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation ?? latlong2.LatLng(0, 0),
                initialZoom: 15.0,
                onTap: (tapPosition, latlng) async {
                  if (mounted) {
                    // Added mounted check
                    setState(() {
                      _destinationLocation = latlng;
                      _destinationMarker = Marker(
                        point: _destinationLocation!,
                        width: 80,
                        height: 80,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40,
                        ), // Corrected to child
                      );
                    });
                  }
                  try {
                    // Moved address resolution logic here
                    List<geocoding.Placemark> placemarks = await geocoding
                        .placemarkFromCoordinates(
                          latlng.latitude,
                          latlng.longitude,
                        );
                    if (placemarks.isNotEmpty) {
                      final placemark = placemarks.first;
                      if (mounted) {
                        // Added mounted check
                        setState(() {
                          _destinationAddress =
                              '${placemark.street}, ${placemark.locality}, ${placemark.country}';
                          _destinationController.text =
                              _destinationAddress; // Update text field
                        });
                      }
                      _speechService.speak(
                        "Destination set to: $_destinationAddress",
                      );
                    }
                  } catch (e) {
                    _logger.e("Error resolving tapped address: $e");
                    _speechService.speak(
                      "Could not resolve address for this location.",
                    );
                    if (mounted) {
                      // Added mounted check
                      setState(() {
                        _destinationAddress = 'Address not found';
                      });
                    }
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.assistlens.app',
                ),
                CurrentLocationLayer(
                  alignPositionOnUpdate: AlignOnUpdate.always,
                  alignDirectionOnUpdate: AlignOnUpdate.always,
                  style: LocationMarkerStyle(
                    marker: DefaultLocationMarker(
                      color: colorScheme.secondary,
                      child: Icon(
                        // Corrected to child
                        Icons.navigation,
                        color: colorScheme.onSecondary,
                      ),
                    ),
                    markerSize: const Size(40, 40),
                    markerDirection: MarkerDirection.heading,
                  ),
                ),
                if (_destinationMarker != null)
                  MarkerLayer(markers: [_destinationMarker!]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAccessibleButton(
                  icon: Icons.my_location_rounded,
                  label: 'My Location',
                  onPressed: () {
                    if (_currentLocation != null) {
                      _mapController.move(_currentLocation!, 15.0);
                      _speechService.speak(
                        "Centered on your current location.",
                      );
                    } else {
                      _speechService.speak(
                        "Your current location is not available yet.",
                      );
                    }
                  },
                  color: colorScheme.tertiary,
                ),
                _buildAccessibleButton(
                  icon: Icons.directions_run_rounded,
                  label: 'Start Navigation',
                  onPressed: _startActiveNavigation,
                  color: colorScheme.primary,
                ),
                _buildAccessibleButton(
                  icon: Icons.cancel_rounded,
                  label: 'Clear Destination',
                  onPressed: () {
                    if (mounted) {
                      // Added mounted check
                      setState(() {
                        _destinationLocation = null;
                        _destinationMarker = null;
                        _destinationController.clear();
                        _destinationAddress = '';
                      });
                    }
                    _speechService.speak("Destination cleared.");
                  },
                  color: Theme.of(context).colorScheme.error.withAlpha(
                    (0.7 * 255).round(),
                  ), // Using withAlpha
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessibleButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color, // Button color passed as parameter
            foregroundColor:
                Theme.of(context).colorScheme.onPrimary, // Text color on button
            padding: const EdgeInsets.symmetric(vertical: 10),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 12, // Adjusted for smaller buttons
              fontWeight: FontWeight.bold,
            ),
            minimumSize: const Size.fromHeight(60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Column(
            // Corrected to child
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
