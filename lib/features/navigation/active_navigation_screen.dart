// lib/features/navigation/active_navigation_screen.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:logger/Logger.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:assist_lens/core/services/speech_service.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/routing/app_router.dart';
import '../aniwa_chat/state/chat_state.dart';
import '../../main.dart';

class ActiveNavigationScreen extends StatefulWidget {
  const ActiveNavigationScreen({super.key});

  @override
  State<ActiveNavigationScreen> createState() => _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState extends State<ActiveNavigationScreen>
    with WidgetsBindingObserver, RouteAware {
  final Logger _logger = Logger();
  late SpeechService _speechService;

  // Navigation data
  Position? _currentPosition;
  latlong2.LatLng? _destination;
  String _currentAddress = '';
  String _destinationAddress = '';

  // Location tracking
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<MagnetometerEvent>? _magnetometerStream;

  // Navigation state
  double _distanceToDestination = 0.0;
  double _bearingToDestination = 0.0;
  double _currentHeading = 0.0;
  double _speed = 0.0;
  String _navigationStatus = 'Initializing...';

  // Audio guidance
  Timer? _guidanceTimer;
  Timer? _proximityTimer;

  // Haptic feedback
  bool _isVibrationAvailable = false;

  // Navigation settings
  double _guidanceIntervalSeconds = 10.0;
  final double _proximityAlertDistance = 50.0;
  bool _isNavigationActive = true;

  // Gesture detection
  late ChatState _chatState;
  final GlobalKey _screenKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVibrationSupport();
    });
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _speechService = context.read<SpeechService>();
    _chatState = context.read<ChatState>();
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
    _initializeNavigation();
    _checkVibrationSupport();
  }

  @override
  void didPush() {
    _logger.i("ActiveNavigationScreen: didPush - Page is active.");
    _chatState.updateCurrentRoute(AppRouter.activeNavigation);
    _chatState.setChatPageActive(true);
    _chatState.resume();
    super.didPush();
  }

  @override
  void didPopNext() {
    _logger.i("ActiveNavigationScreen: didPopNext - Returning to page.");
    _chatState.updateCurrentRoute(AppRouter.activeNavigation);
    _chatState.setChatPageActive(true);
    _chatState.resume();
    super.didPopNext();
  }

  @override
  void didPushNext() {
    _logger.i(
      "ActiveNavigationScreen: didPushNext - Navigating away from page.",
    );
    _chatState.setChatPageActive(false);
    _chatState.pause();
    super.didPushNext();
  }

  @override
  void didPop() {
    _logger.i("ActiveNavigationScreen: didPop - Page is being popped.");
    _chatState.setChatPageActive(false);
    _chatState.pause();
    super.didPop();
  }

  Future<void> _checkVibrationSupport() async {
    _isVibrationAvailable = await Vibration.hasVibrator() ?? false;
  }

  void _initializeNavigation() {
    // Attempt to retrieve arguments
    final Map<String, dynamic>? args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    if (args == null) {
      _logger.e('ActiveNavigationScreen: Navigation arguments are NULL!');
      _speakAndFinish('Navigation data not found. Returning to map.');
      return;
    }

    _logger.i(
      'ActiveNavigationScreen: Arguments received: $args',
    ); // Log received arguments

    try {
      // Cast with null-aware operators and provide default values
      _currentPosition = args['initialPosition'] as Position?;
      _destination = args['destination'] as latlong2.LatLng?;
      _currentAddress = args['currentAddress'] as String? ?? '';
      _destinationAddress = args['destinationAddress'] as String? ?? '';

      // Perform more explicit checks for null data
      if (_currentPosition == null) {
        _logger.e(
          'ActiveNavigationScreen: "initialPosition" is null in arguments.',
        );
        _speakAndFinish('Invalid starting location. Returning to map.');
        return;
      }
      if (_destination == null) {
        _logger.e(
          'ActiveNavigationScreen: "destination" is null in arguments.',
        );
        _speakAndFinish('Invalid destination. Returning to map.');
        return;
      }
      if (_currentAddress.isEmpty) {
        _logger.w('ActiveNavigationScreen: "currentAddress" is empty or null.');
      }
      if (_destinationAddress.isEmpty) {
        _logger.w(
          'ActiveNavigationScreen: "destinationAddress" is empty or null.',
        );
      }

      _logger.i(
        'ActiveNavigationScreen: Navigation data parsed successfully. '
        'Current Pos: (${_currentPosition!.latitude}, ${_currentPosition!.longitude}) '
        'Destination: (${_destination!.latitude}, ${_destination!.longitude}) '
        'Current Address: $_currentAddress '
        'Destination Address: $_destinationAddress',
      );

      _startNavigationGuidance();
    } catch (e, st) {
      _logger.e(
        'ActiveNavigationScreen: Error parsing specific navigation arguments: $e',
        error: e,
        stackTrace: st,
      );
      _speakAndFinish('Failed to process navigation data. Returning to map.');
    }
  }

  void _startNavigationGuidance() {
    _calculateNavigationData();
    _startLocationTracking();
    _startCompassTracking();
    _startGuidanceTimer();

    _speakInitialGuidance();
  }

  void _speakInitialGuidance() {
    final distance = _formatDistance(_distanceToDestination);
    final direction = _getCardinalDirection(_bearingToDestination);

    _speechService.speak(
      'Navigation started to $_destinationAddress. '
      'Distance: $distance. '
      'Direction: $direction. '
      'Tap screen for current status. '
      'Swipe up for settings. '
      'Swipe down to end navigation.',
    );
  }

  void _startLocationTracking() {
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen(
      (Position position) {
        if (!_isNavigationActive) return;

        _currentPosition = position;
        _speed = position.speed;
        _calculateNavigationData();
        _checkProximityAlerts();

        setState(() {
          _navigationStatus = _getNavigationStatus();
        });
      },
      onError: (error) {
        _logger.e('Location tracking error: $error');
        _speechService.speak('Location tracking error. Please check your GPS.');
      },
    );
  }

  void _startCompassTracking() {
    _magnetometerStream = magnetometerEvents.listen((MagnetometerEvent event) {
      if (!_isNavigationActive) return;

      double heading = math.atan2(event.y, event.x) * (180 / math.pi);
      if (heading < 0) heading += 360;

      _currentHeading = heading;
      setState(() {});
    });
  }

  void _calculateNavigationData() {
    if (_currentPosition == null || _destination == null) return;

    _distanceToDestination = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );

    _bearingToDestination = Geolocator.bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      _destination!.latitude,
      _destination!.longitude,
    );

    if (_bearingToDestination < 0) {
      _bearingToDestination += 360;
    }
  }

  void _startGuidanceTimer() {
    _guidanceTimer = Timer.periodic(
      Duration(seconds: _guidanceIntervalSeconds.round()),
      (timer) {
        if (!_isNavigationActive) return;
        _provideNavigationGuidance();
      },
    );
  }

  void _provideNavigationGuidance() {
    if (_distanceToDestination < 5) {
      _arrivedAtDestination();
      return;
    }

    final distance = _formatDistance(_distanceToDestination);
    final direction = _getDetailedDirection();
    final speedInfo = _getSpeedInfo();

    String guidance = '$distance to destination. $direction. $speedInfo';

    _speechService.speak(guidance);
    _provideHapticFeedback();
  }

  String _getDetailedDirection() {
    double relativeBearing = _bearingToDestination - _currentHeading;
    if (relativeBearing > 180) relativeBearing -= 360;
    if (relativeBearing < -180) relativeBearing += 360;

    if (relativeBearing.abs() < 15) {
      return 'Continue straight ahead';
    } else if (relativeBearing > 0) {
      if (relativeBearing < 45) {
        return 'Turn slightly right';
      } else if (relativeBearing < 135) {
        return 'Turn right';
      } else {
        return 'Turn sharp right';
      }
    } else {
      if (relativeBearing > -45) {
        return 'Turn slightly left';
      } else if (relativeBearing > -135) {
        return 'Turn left';
      } else {
        return 'Turn sharp left';
      }
    }
  }

  String _getCardinalDirection(double bearing) {
    const directions = [
      'North',
      'Northeast',
      'East',
      'Southeast',
      'South',
      'Southwest',
      'West',
      'Northwest',
    ];
    int index = ((bearing + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} meters';
    } else {
      double km = meters / 1000;
      return '${km.toStringAsFixed(1)} kilometers';
    }
  }

  String _getSpeedInfo() {
    if (_speed < 0.5) {
      return 'You are stationary';
    } else {
      double kmh = _speed * 3.6;
      return 'Speed: ${kmh.toStringAsFixed(1)} km/h';
    }
  }

  String _getNavigationStatus() {
    final distance = _formatDistance(_distanceToDestination);
    final direction = _getCardinalDirection(_bearingToDestination);
    return '$distance $direction';
  }

  void _checkProximityAlerts() {
    if (_proximityTimer?.isActive == true) return;

    if (_distanceToDestination <= _proximityAlertDistance &&
        _distanceToDestination > 5) {
      _speechService.speak(
        'Approaching destination. ${_formatDistance(_distanceToDestination)} remaining.',
      );
      _provideHapticFeedback(pattern: [0, 500, 200, 500]);

      _proximityTimer = Timer(const Duration(seconds: 30), () {});
    }
  }

  void _arrivedAtDestination() {
    _isNavigationActive = false;
    _speechService.speak(
      'You have arrived at your destination: $_destinationAddress. Navigation complete.',
    );
    _provideHapticFeedback(pattern: [0, 200, 100, 200, 100, 200]);

    Timer(const Duration(seconds: 5), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _provideHapticFeedback({List<int>? pattern}) {
    if (!_isVibrationAvailable) return;

    if (pattern != null) {
      Vibration.vibrate(pattern: pattern);
    } else {
      Vibration.vibrate(duration: 200);
    }
  }

  Future<void> _handleScreenTap() async {
    await _speechService.stopSpeaking(); // Interrupt any ongoing speech
    final status = _getNavigationStatus();
    final direction = _getDetailedDirection();
    _speechService.speak('Current status: $status. $direction.');

    HapticFeedback.lightImpact();
  }

  Future<void> _handleSwipeUp() async {
    await _speechService
        .stopSpeaking(); // Interrupt speech before showing settings
    _showNavigationSettings();
  }

  Future<void> _handleSwipeDown() async {
    await _speechService
        .stopSpeaking(); // Interrupt speech before asking to confirm end
    _confirmEndNavigation();
  }

  void _showNavigationSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _buildSettingsSheet(),
    );
  }

  Widget _buildSettingsSheet() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.surface.withOpacity(0.98),
            colorScheme.surface.withOpacity(0.95),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 5,
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withOpacity(0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Text(
              'Navigation Settings',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 20),

            ListTile(
              title: Text('Guidance Frequency', style: GoogleFonts.poppins()),
              subtitle: Text(
                'Every ${_guidanceIntervalSeconds.round()} seconds',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () {
                      if (_guidanceIntervalSeconds > 5) {
                        setState(() {
                          _guidanceIntervalSeconds -= 5;
                        });
                        _restartGuidanceTimer();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (_guidanceIntervalSeconds < 60) {
                        setState(() {
                          _guidanceIntervalSeconds += 5;
                        });
                        _restartGuidanceTimer();
                      }
                    },
                  ),
                ],
              ),
            ),

            const Divider(height: 20),

            ListTile(
              leading: Icon(Icons.repeat, color: colorScheme.primary),
              title: Text(
                'Repeat Current Guidance',
                style: GoogleFonts.poppins(),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _speechService.stopSpeaking(); // Interrupt
                _provideNavigationGuidance();
              },
            ),

            ListTile(
              leading: Icon(Icons.stop, color: colorScheme.error),
              title: Text('End Navigation', style: GoogleFonts.poppins()),
              onTap: () async {
                Navigator.pop(context);
                await _speechService.stopSpeaking(); // Interrupt
                _confirmEndNavigation();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _restartGuidanceTimer() {
    _guidanceTimer?.cancel();
    _startGuidanceTimer();
  }

  void _confirmEndNavigation() {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('End Navigation', style: GoogleFonts.poppins()),
            content: Text(
              'Are you sure you want to end navigation?',
              style: GoogleFonts.poppins(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(color: colorScheme.primary),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _endNavigation();
                },
                child: Text(
                  'End Navigation',
                  style: GoogleFonts.poppins(color: colorScheme.error),
                ),
              ),
            ],
          ),
    );
  }

  void _endNavigation() {
    _speechService.speak('Navigation ended. Returning to map.');
    _isNavigationActive = false;
    Navigator.of(context).pop();
  }

  void _speakAndFinish(String message) {
    _speechService.speak(message);
    Timer(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _guidanceIntervalSeconds = math.max(_guidanceIntervalSeconds * 2, 30);
      _restartGuidanceTimer();
    } else if (state == AppLifecycleState.resumed) {
      _guidanceIntervalSeconds = math.min(_guidanceIntervalSeconds / 2, 10);
      _restartGuidanceTimer();
    }
  }

  @override
  void dispose() {
    _logger.i("ActiveNavigationScreen disposed, releasing resources.");
    WidgetsBinding.instance.removeObserver(this); // Explicitly remove observer
    routeObserver.unsubscribe(this);
    _positionStream?.cancel();
    _magnetometerStream?.cancel();
    _guidanceTimer?.cancel();
    _proximityTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: colorScheme.primary.withAlpha(180),
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary.withAlpha(180),
                colorScheme.secondary.withAlpha(150),
                colorScheme.tertiary.withAlpha(120),
              ],
            ),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withAlpha((0.2 * 255).round()),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Active Navigation',
                  style: GoogleFonts.sourceCodePro(
                    color: colorScheme.onPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        toolbarHeight: 120,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colorScheme.onPrimary,
          ),
          onPressed: _confirmEndNavigation,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            color: colorScheme.onPrimary,
            onPressed: _showNavigationSettings,
          ),
        ],
      ),
      body: GestureDetector(
        key: _screenKey,
        onTap: _handleScreenTap,
        onPanUpdate: (details) {
          if (details.delta.dy < -10) {
            _handleSwipeUp();
          } else if (details.delta.dy > 10) {
            _handleSwipeDown();
          }
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _formatDistance(_distanceToDestination),
                          style: GoogleFonts.sourceCodePro(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _getDetailedDirection(),
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 24,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'To: $_destinationAddress',
                          style: GoogleFonts.poppins(
                            color: Colors.white60,
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Tap screen: Current status',
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Swipe up: Settings',
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Swipe down: End navigation',
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
