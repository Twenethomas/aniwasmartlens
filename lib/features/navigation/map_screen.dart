// lib/features/navigation/map_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:assist_lens/core/services/speech_service.dart';
import 'package:logger/logger.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:assist_lens/main.dart';
import 'package:assist_lens/core/routing/app_router.dart';
import '../aniwa_chat/state/chat_state.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

enum MapScreenStateStatus {
  initializing,
  permissionDenied,
  serviceDisabled,
  ready,
  error,
}

class _MapScreenState extends State<MapScreen>
    with TickerProviderStateMixin, RouteAware, WidgetsBindingObserver {
  final Logger _logger = Logger();
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _destinationController = TextEditingController();

  GoogleMapController? _googleMapController;

  latlong2.LatLng? _currentLocation;
  LatLng? _googleMapCurrentLocation;
  LatLng? _destinationLocation;

  final Set<Marker> _markers = {};

  String _currentAddress = 'Fetching current location...';
  String _destinationAddress = '';
  StreamSubscription<Position>? _positionStreamSubscription;
  late ChatState _chatState;
  late SpeechService _speechService;

  MapScreenStateStatus _status = MapScreenStateStatus.initializing;
  bool _isRequestingPermission = false;
  bool _hasSpokenPermissionMessage = false;
  bool _hasSpokenServiceMessage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speechService = context.read<SpeechService>();
      _initializeMapAndLocation();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatState = Provider.of<ChatState>(context, listen: false);
    final ModalRoute? route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() {
    _logger.i("MapScreen: didPush - Page is active.");
    _chatState.updateCurrentRoute(AppRouter.navigation);
    _chatState.setChatPageActive(true);
    _chatState.resume();
    _initializeMapAndLocation();
    super.didPush();
  }

  @override
  void didPopNext() {
    _logger.i("MapScreen: didPopNext - Returning to page.");
    _chatState.updateCurrentRoute(AppRouter.navigation);
    _chatState.setChatPageActive(true);
    _chatState.resume();
    _initializeMapAndLocation();
    super.didPopNext();
  }

  @override
  void didPushNext() {
    _logger.i("MapScreen: didPushNext - Navigating away from page.");
    _chatState.setChatPageActive(false);
    _chatState.pause();
    _positionStreamSubscription?.cancel();
    _resetSpeechFlags();
    super.didPushNext();
  }

  @override
  void didPop() {
    _logger.i("MapScreen: didPop - Page is being popped.");
    _chatState.setChatPageActive(false);
    _chatState.pause();
    _positionStreamSubscription?.cancel();
    _resetSpeechFlags();
    super.didPop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _logger.i("App inactive, stopping location updates.");
      _positionStreamSubscription?.cancel();
      _resetSpeechFlags();
    } else if (state == AppLifecycleState.resumed) {
      _logger.i("App resumed, restarting location updates.");
      _initializeMapAndLocation();
    }
  }

  void _resetSpeechFlags() {
    _hasSpokenPermissionMessage = false;
    _hasSpokenServiceMessage = false;
  }

  Future<void> _initializeMapAndLocation() async {
    if (!mounted) return;
    if (_isRequestingPermission) {
      _logger.d("Already requesting location permissions, skipping.");
      return;
    }

    setState(() {
      _status = MapScreenStateStatus.initializing;
    });

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;

    if (!serviceEnabled) {
      setState(() {
        _status = MapScreenStateStatus.serviceDisabled;
      });
      if (!_hasSpokenServiceMessage) {
        _speechService.speak(
          "Location services are disabled. Please enable them in your device settings to use navigation.",
        );
        _hasSpokenServiceMessage = true;
      }
      return;
    }

    if (_status == MapScreenStateStatus.serviceDisabled) {
      _hasSpokenServiceMessage = false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (!mounted) return;

    if (permission == LocationPermission.denied) {
      _isRequestingPermission = true;
      try {
        permission = await Geolocator.requestPermission();
      } finally {
        _isRequestingPermission = false;
      }
      if (!mounted) return;
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _status = MapScreenStateStatus.permissionDenied;
      });
      if (!_hasSpokenPermissionMessage) {
        final message =
            permission == LocationPermission.deniedForever
                ? "Location permissions are permanently denied. Please enable them from your device settings."
                : "Location permission is denied. Please grant permission to use navigation.";
        _speechService.speak(message);
        _hasSpokenPermissionMessage = true;
      }
      return;
    }

    if (_status == MapScreenStateStatus.permissionDenied) {
      _hasSpokenPermissionMessage = false;
    }

    setState(() {
      _status = MapScreenStateStatus.ready;
    });
    _startLocationUpdatesInternal();
  }

  Future<void> _startLocationUpdatesInternal() async {
    if (!mounted || _status != MapScreenStateStatus.ready) {
      _logger.d(
        "Not starting location updates. Mounted: $mounted, Status: $_status",
      );
      return;
    }

    _logger.i("Starting internal location updates.");
    _positionStreamSubscription?.cancel();

    try {
      Position initialPos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      if (mounted) {
        _updateLocationFromPosition(initialPos);
        _resolveCurrentAddress(initialPos);
        setState(() {});
      }
    } catch (e) {
      _logger.w(
        "Could not get initial position quickly: $e. Relying on stream.",
      );
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (Position position) {
        if (mounted) {
          bool wasLoadingLocation = _googleMapCurrentLocation == null;
          _updateLocationFromPosition(position);

          if (_googleMapController != null) {
            if (wasLoadingLocation) {
              _googleMapController!.animateCamera(
                CameraUpdate.newLatLngZoom(_googleMapCurrentLocation!, 15.0),
              );
            } else {
              _googleMapController!.animateCamera(
                CameraUpdate.newLatLng(_googleMapCurrentLocation!),
              );
            }
          }
          _resolveCurrentAddress(position);
          setState(() {});
        }
      },
      onError: (e) {
        _logger.e("Error getting location stream: $e");
        _speechService.speak(
          "Failed to get your current location. Please check your device settings.",
        );
        if (mounted) {
          setState(() {
            _status = MapScreenStateStatus.error;
            _currentAddress = "Error fetching location.";
          });
        }
      },
    );
  }

  void _updateLocationFromPosition(Position position) {
    _currentLocation = latlong2.LatLng(position.latitude, position.longitude);
    _googleMapCurrentLocation = LatLng(position.latitude, position.longitude);
    _updateCurrentLocationMarker();
  }

  void _updateCurrentLocationMarker() {
    if (_googleMapCurrentLocation == null) return;

    const markerId = MarkerId('currentLocation');
    final marker = Marker(
      markerId: markerId,
      position: _googleMapCurrentLocation!,
      infoWindow: InfoWindow(
        title: 'Your Current Location',
        snippet: _currentAddress,
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    );

    if (mounted) {
      setState(() {
        _markers.removeWhere((m) => m.markerId == markerId);
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
            _updateCurrentLocationMarker();
          });
        }
      }
    } catch (e) {
      _logger.e("Error resolving current address: $e");
      if (mounted) {
        setState(() {
          _currentAddress = 'Address not found.';
          _updateCurrentLocationMarker();
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
        final newDestination = LatLng(location.latitude, location.longitude);
        if (mounted) {
          setState(() {
            _destinationLocation = newDestination;
            _addDestinationMarker(newDestination);
            _googleMapController?.animateCamera(
              CameraUpdate.newLatLngZoom(newDestination, 15.0),
            );
          });
          await _resolveDestinationAddress(newDestination);
          _speechService.speak("Destination set to: $_destinationAddress");
        }
      } else {
        _speechService.speak(
          "Could not find any location for that search query. Please try again.",
        );
        if (mounted) {
          setState(() {
            _destinationAddress = 'Not found';
            _clearDestinationMarker();
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
          _clearDestinationMarker();
        });
      }
    }
  }

  void _addDestinationMarker(LatLng position) {
    final markerId = MarkerId('destinationLocation');
    final marker = Marker(
      markerId: markerId,
      position: position,
      infoWindow: InfoWindow(
        title: 'Destination',
        snippet: _destinationAddress,
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    );
    if (mounted) {
      setState(() {
        _markers.removeWhere((m) => m.markerId == markerId);
        _markers.add(marker);
      });
    }
  }

  void _clearDestinationMarker() {
    final markerId = MarkerId('destinationLocation');
    if (mounted) {
      setState(() {
        _markers.removeWhere((m) => m.markerId == markerId);
      });
    }
  }

  Future<void> _startActiveNavigation() async {
    if (_currentLocation == null) {
      _speechService.speak(
        "Your current location is not yet available. Please wait a moment.",
      );
      _logger.w("Attempted to start navigation without current location.");
      return;
    }
    if (_destinationLocation == null) {
      _speechService.speak("Please search for and select a destination first.");
      _logger.w("Attempted to start navigation without a destination set.");
      return;
    }

    final distance = (Geolocator.distanceBetween(
              _currentLocation!.latitude,
              _currentLocation!.longitude,
              _destinationLocation!.latitude,
              _destinationLocation!.longitude,
            ) /
            1000)
        .toStringAsFixed(1);

    Navigator.of(context).pushNamed(
      AppRouter.activeNavigation,
      arguments: {
        'initialPosition': Position(
          latitude: _currentLocation!.latitude,
          longitude: _currentLocation!.longitude,
          timestamp: DateTime.now(),
          accuracy: 10.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 5.0,
          altitudeAccuracy: 10.0,
          headingAccuracy: 15.0,
        ),
        'destination': latlong2.LatLng(
          _destinationLocation!.latitude,
          _destinationLocation!.longitude,
        ),
        'currentAddress': _currentAddress,
        'destinationAddress': _destinationAddress,
        'estimatedDistance': distance,
      },
    );
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
            _addDestinationMarker(latlng);
          });
        }
      }
    } catch (e) {
      _logger.e("Error resolving destination address from LatLng: $e");
      if (mounted) {
        setState(() {
          _destinationAddress = 'Destination address not found.';
          _addDestinationMarker(latlng);
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
    _googleMapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
      body: _buildBodyContent(colorScheme, textTheme),
    );
  }

  Widget _buildBodyContent(ColorScheme colorScheme, TextTheme textTheme) {
    switch (_status) {
      case MapScreenStateStatus.initializing:
        return const Center(child: CircularProgressIndicator());
      case MapScreenStateStatus.serviceDisabled:
        return _buildInfoScreen(
          icon: Icons.location_off,
          message: "Location services are disabled.",
          buttonText: "Open Location Settings",
          onButtonPressed: () async {
            await Geolocator.openLocationSettings();
          },
          colorScheme: colorScheme,
        );
      case MapScreenStateStatus.permissionDenied:
        return _buildInfoScreen(
          icon: Icons.location_disabled,
          message: "Location permission denied.",
          buttonText: "Open App Settings",
          onButtonPressed: () async {
            await Geolocator.openAppSettings();
          },
          colorScheme: colorScheme,
        );
      case MapScreenStateStatus.error:
        return _buildInfoScreen(
          icon: Icons.error_outline,
          message: _currentAddress,
          buttonText: "Retry",
          onButtonPressed: _initializeMapAndLocation,
          colorScheme: colorScheme,
        );
      case MapScreenStateStatus.ready:
        if (_googleMapCurrentLocation == null) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Acquiring your location..."),
              ],
            ),
          );
        } else {
          return _buildMapInterface(colorScheme, textTheme);
        }
    }
  }

  Widget _buildMapInterface(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
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
            ),
          ),
        ),
        if (_destinationLocation != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: Text(
              'Destination Address: $_destinationAddress',
              style: TextStyle(
                color: colorScheme.onSurface.withAlpha((0.7 * 255).round()),
              ),
            ),
          ),
        Expanded(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _googleMapCurrentLocation!,
              zoom: 15.0,
            ),
            onMapCreated: (controller) {
              if (!mounted) return;
              _googleMapController = controller;
              _updateCurrentLocationMarker();
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _markers,
            onTap: (latlng) async {
              if (mounted) {
                setState(() {
                  _destinationLocation = latlng;
                  _addDestinationMarker(latlng);
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
                      _destinationController.text = _destinationAddress;
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
                    _addDestinationMarker(latlng);
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
                    _speechService.speak("Centered on your current location.");
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
                onPressed: () {
                  if (_currentLocation == null) {
                    _speechService.speak(
                      "Current location not available. Please wait for GPS signal.",
                    );
                  } else if (_destinationLocation == null) {
                    _speechService.speak("Please select a destination first.");
                  } else {
                    _startActiveNavigation();
                  }
                },
                color: colorScheme.primary,
              ),
              _buildAccessibleButton(
                icon: Icons.cancel_rounded,
                label: 'Clear Destination',
                onPressed: () {
                  if (mounted) {
                    setState(() {
                      _destinationLocation = null;
                      _clearDestinationMarker();
                      _destinationController.clear();
                      _destinationAddress = '';
                    });
                  }
                  _speechService.speak("Destination cleared.");
                },
                color: Theme.of(
                  context,
                ).colorScheme.error.withAlpha((0.7 * 255).round()),
              ),
            ],
          ),
        ),
      ],
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
            backgroundColor: color,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 10),
            textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            minimumSize: const Size.fromHeight(60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Column(
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

  Widget _buildInfoScreen({
    required IconData icon,
    required String message,
    required String buttonText,
    required VoidCallback onButtonPressed,
    required ColorScheme colorScheme,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: colorScheme.error),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: const Icon(Icons.settings),
              label: Text(buttonText),
              onPressed: onButtonPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
