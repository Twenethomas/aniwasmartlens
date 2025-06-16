import 'dart:async';
import 'package:flutter/material.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart'; // New Google Maps import
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart'
    as latlong2; // Keeping latlong2 for compatibility with geolocator/geocoding, but converting to LatLng for Google Maps
import 'package:assist_lens/core/services/speech_service.dart'; // Import SpeechService
import 'package:logger/logger.dart';
import 'package:google_fonts/google_fonts.dart'; // Added import for GoogleFonts

import 'package:assist_lens/main.dart'; // For routeObserver
import 'package:assist_lens/core/routing/app_router.dart';
// Import AppRouter

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

  GoogleMapController? _googleMapController;

  latlong2.LatLng? _currentLocation; // From geolocator/latlong2
  LatLng? _googleMapCurrentLocation; // Converted to Google Maps LatLng
  LatLng? _destinationLocation; // Google Maps LatLng for destination

  final Set<Marker> _markers = {};

  String _currentAddress = 'Fetching current location...';
  String _destinationAddress = '';
  StreamSubscription<Position>? _positionStreamSubscription;
  final SpeechService _speechService = SpeechService();

  bool _isLocationServiceEnabled = false;
  LocationPermission _locationPermission = LocationPermission.denied;
  bool _isRequestingPermission =
      false; // NEW: Flag to prevent concurrent permission requests

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(
      this,
    ); // Add observer for lifecycle events
    _checkLocationPermissions().then((_) {
      // Start location updates only after initial permission check is done
      _startLocationUpdates();
    });
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
      _checkLocationPermissions().then((_) {
        // Only restart if permissions are already granted or were just granted
        _startLocationUpdates();
      });
    }
  }

  Future<void> _checkLocationPermissions() async {
    _isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    _locationPermission = await Geolocator.checkPermission();
    if (mounted) {
      setState(() {}); // Update UI to reflect current permission status
    }
  }

  Future<void> _startLocationUpdates() async {
    // NEW: Prevent multiple concurrent permission requests
    if (_isRequestingPermission) {
      _logger.d("Already requesting location permissions, skipping.");
      return;
    }

    // Re-check status just before initiating updates/requests
    await _checkLocationPermissions();

    if (!_isLocationServiceEnabled ||
        _locationPermission == LocationPermission.denied ||
        _locationPermission == LocationPermission.deniedForever) {
      _logger.w(
        "Location services not enabled or permissions denied. Attempting to request...",
      );

      if (_locationPermission == LocationPermission.deniedForever) {
        _speechService.speak(
          "Location permissions are permanently denied. Please enable them from your device settings.",
        );
        _logger.e(
          "Location permissions permanently denied. Cannot request programmatically.",
        );
        return;
      }

      // Only request if not denied forever and not already requesting
      _isRequestingPermission = true;
      try {
        _locationPermission = await Geolocator.requestPermission();
        if (mounted) setState(() {}); // Update UI after request attempt
      } finally {
        _isRequestingPermission = false; // Reset flag
      }

      // After request, check if permissions are now granted and service is enabled
      if (!mounted ||
          !_isLocationServiceEnabled ||
          _locationPermission == LocationPermission.denied ||
          _locationPermission == LocationPermission.deniedForever) {
        _speechService.speak(
          "Location services are not enabled or permissions are denied. Please enable them in your settings.",
        );
        _logger.e("Failed to obtain location permission after request.");
        return;
      }
    }

    // If we reach here, permissions should be granted and service enabled.
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
            _googleMapCurrentLocation = LatLng(
              position.latitude,
              position.longitude,
            );
            if (_googleMapController != null) {
              _googleMapController!.animateCamera(
                CameraUpdate.newLatLng(_googleMapCurrentLocation!),
              );
            }
            _updateCurrentLocationMarker();
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

  /// Updates the marker for the user's current location on the Google Map.
  void _updateCurrentLocationMarker() {
    if (_googleMapCurrentLocation == null) return;

    final markerId = MarkerId('currentLocation');
    final marker = Marker(
      markerId: markerId,
      position: _googleMapCurrentLocation!,
      infoWindow: InfoWindow(
        title: 'Your Current Location',
        snippet: _currentAddress,
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueAzure,
      ), // A blue marker
    );

    // Add or update the current location marker
    if (mounted) {
      setState(() {
        _markers.removeWhere(
          (m) => m.markerId == markerId,
        ); // Remove old marker if exists
        _markers.add(marker);
      });
    }
  }

  Future<void> _resolveCurrentAddress(Position position) async {
    try {
      List<geocoding.Placemark> placemarks = await geocoding
          .placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        if (mounted) {
          setState(() {
            _currentAddress =
                '${placemark.street}, ${placemark.locality}, ${placemark.country}';
            _updateCurrentLocationMarker(); // Update marker info window with new address
          });
        }
      }
    } catch (e) {
      _logger.e("Error resolving current address: $e");
      if (mounted) {
        setState(() {
          _currentAddress = 'Address not found.';
          _updateCurrentLocationMarker(); // Update marker info window
        });
      }
    }
  }

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
        final newDestination = LatLng(
          location.latitude,
          location.longitude,
        ); // Google Maps LatLng
        if (mounted) {
          setState(() {
            _destinationLocation = newDestination;
            _addDestinationMarker(newDestination); // Add marker for destination
            _googleMapController?.animateCamera(
              CameraUpdate.newLatLngZoom(
                newDestination,
                15.0,
              ), // Move map to destination
            );
          });
          await _resolveDestinationAddress(
            newDestination,
          ); // Resolve the address for display
          _speechService.speak("Destination set to: $_destinationAddress");
        }
      } else {
        _speechService.speak(
          "Could not find any location for that search query. Please try again.",
        );
        if (mounted) {
          setState(() {
            _destinationAddress = 'Not found';
            _clearDestinationMarker(); // Clear marker if not found
          });
        }
      }
    } catch (e) {
      _logger.e("Error searching destination: $e");
      _speechService.speak(
        "An error occurred while searching for the destination.",
      );
      if (mounted) {
        setState(() {
          _destinationAddress = 'Error searching';
          _clearDestinationMarker(); // Clear marker on error
        });
      }
    }
  }

  /// Adds a marker for the destination location.
  void _addDestinationMarker(LatLng position) {
    final markerId = MarkerId('destinationLocation');
    final marker = Marker(
      markerId: markerId,
      position: position,
      infoWindow: InfoWindow(
        title: 'Destination',
        snippet: _destinationAddress,
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueRed,
      ), // Red marker
    );
    if (mounted) {
      setState(() {
        _markers.removeWhere(
          (m) => m.markerId == markerId,
        ); // Remove old destination marker
        _markers.add(marker);
      });
    }
  }

  /// Clears the destination marker from the map.
  void _clearDestinationMarker() {
    final markerId = MarkerId('destinationLocation');
    if (mounted) {
      setState(() {
        _markers.removeWhere((m) => m.markerId == markerId);
      });
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
          // Convert Google Maps LatLng back to latlong2.LatLng for ActiveNavigationScreen if it expects it
          'destination': latlong2.LatLng(
            _destinationLocation!.latitude,
            _destinationLocation!.longitude,
          ),
        },
      );
    } else {
      _speechService.speak(
        "Please set both your current location and a destination to start navigation.",
      );
    }
  }

  Future<void> _resolveDestinationAddress(LatLng latlng) async {
    try {
      List<geocoding.Placemark> placemarks = await geocoding
          .placemarkFromCoordinates(latlng.latitude, latlng.longitude);
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        if (mounted) {
          setState(() {
            _destinationAddress =
                '${placemark.street}, ${placemark.locality}, ${placemark.country}';
            // Update the info window of the existing destination marker
            _addDestinationMarker(latlng);
          });
        }
      }
    } catch (e) {
      _logger.e("Error resolving destination address from LatLng: $e");
      if (mounted) {
        setState(() {
          _destinationAddress = 'Destination address not found.';
          _addDestinationMarker(latlng); // Update info window
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
    _googleMapController?.dispose(); // Dispose GoogleMapController
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
            child:
                _googleMapCurrentLocation == null
                    ? const Center(child: CircularProgressIndicator())
                    : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _googleMapCurrentLocation!,
                        zoom: 15.0,
                      ),
                      onMapCreated: (controller) {
                        _googleMapController = controller;
                        _updateCurrentLocationMarker(); // Add current location marker once map is created
                      },
                      myLocationEnabled:
                          true, // Shows blue dot for current location
                      myLocationButtonEnabled:
                          false, // Hide default button, we have our own
                      zoomControlsEnabled: false, // Hide default zoom controls
                      markers: _markers, // Pass the set of markers
                      onTap: (latlng) async {
                        if (mounted) {
                          setState(() {
                            _destinationLocation = latlng;
                            _addDestinationMarker(
                              latlng,
                            ); // Add/update marker for tapped location
                          });
                        }
                        try {
                          List<geocoding.Placemark> placemarks = await geocoding
                              .placemarkFromCoordinates(
                                latlng.latitude,
                                latlng.longitude,
                              );
                          if (placemarks.isNotEmpty) {
                            final placemark = placemarks.first;
                            if (mounted) {
                              setState(() {
                                _destinationAddress =
                                    '${placemark.street}, ${placemark.locality}, ${placemark.country}';
                                _destinationController.text =
                                    _destinationAddress; // Update text field
                                // Update the info window of the existing destination marker
                                _addDestinationMarker(latlng);
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
                            setState(() {
                              _destinationAddress = 'Address not found';
                              _addDestinationMarker(
                                latlng,
                              ); // Update info window even if address not found
                            });
                          }
                        }
                      },
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
                    if (_googleMapCurrentLocation != null &&
                        _googleMapController != null) {
                      _googleMapController!.animateCamera(
                        CameraUpdate.newLatLngZoom(
                          _googleMapCurrentLocation!,
                          15.0,
                        ),
                      );
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
                      setState(() {
                        _destinationLocation = null;
                        _clearDestinationMarker(); // Clear marker
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
