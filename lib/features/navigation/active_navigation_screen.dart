import 'dart:async'; // For StreamSubscription
import 'dart:io';
import 'package:assist_lens/main.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:logger/logger.dart';
import 'package:vibration/vibration.dart';
import 'package:latlong2/latlong.dart' as latlong2;
import 'package:assist_lens/core/services/speech_service.dart';

// Removed TtsState enum as it's not used directly here anymore.
// TtsState ttsState = TtsState.stopped; // REMOVED

class ActiveNavigationScreen extends StatefulWidget {
  final Position initialPosition;
  final latlong2.LatLng destination;

  const ActiveNavigationScreen({
    super.key,
    required this.initialPosition,
    required this.destination,
  });

  @override
  State<ActiveNavigationScreen> createState() => _ActiveNavigationScreenState();
}

class _ActiveNavigationScreenState extends State<ActiveNavigationScreen>
    with WidgetsBindingObserver, RouteAware {
  CameraController? _cameraController;
  ObjectDetector? _objectDetector;
  List<DetectedObject> _detectedObjects = [];
  Size _imageSize = Size.zero;
  final _throttler = _Throttler(milliseconds: 500);
  final Logger _logger = Logger();
  final SpeechService _speechService = SpeechService();

  late Position _currentPosition;
  StreamSubscription<Position>? _positionStreamSubscription;
  double _distanceToDestination = 0.0;
  String _currentAddress = 'Loading address...';
  String _destinationAddress = 'Loading destination...';

  bool _isCameraInitialized = false;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentPosition = widget.initialPosition;
    _initObjectDetector();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeCamera();
      }
    });
    _startLocationUpdates();
    _resolveDestinationAddress();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute? route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() {
    _logger.i(
      "ActiveNavigationScreen: didPush - Page is active. Re-initializing camera.",
    );
    _initializeCamera();
    _startLocationUpdates(); // Ensure location updates resume
    super.didPush();
  }

  @override
  void didPopNext() {
    _logger.i(
      "ActiveNavigationScreen: didPopNext - Returning to page. Re-initializing camera.",
    );
    _initializeCamera();
    _startLocationUpdates(); // Ensure location updates resume
    super.didPopNext();
  }

  @override
  void didPushNext() {
    _logger.i(
      "ActiveNavigationScreen: didPushNext - Navigating away from page. Disposing camera and stopping location.",
    );
    _disposeCamera();
    _positionStreamSubscription?.cancel();
    super.didPushNext();
  }

  @override
  void didPop() {
    _logger.i(
      "ActiveNavigationScreen: didPop - Page is being popped. Disposing camera and stopping location.",
    );
    _disposeCamera();
    _positionStreamSubscription?.cancel();
    super.didPop();
  }

  void _initObjectDetector() {
    _objectDetector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.stream,
        classifyObjects: true,
        multipleObjects: true,
      ),
    );
  }

  Future<void> _initializeCamera() async {
    if (!mounted) {
      _logger.w("Widget not mounted during camera initialization attempt.");
      return;
    }
    if (_isCameraInitialized &&
        _cameraController != null &&
        _cameraController!.value.isInitialized &&
        !_isDisposed) {
      _logger.i(
        "Camera already initialized/active, skipping re-initialization.",
      );
      return;
    }

    _logger.i("Initializing camera for ActiveNavigationScreen...");
    setState(() {
      _isCameraInitialized = false;
      _isDisposed = false;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      _logger.e("No cameras found for ActiveNavigationScreen.");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No cameras found.')));
      }
      return;
    }

    if (_cameraController != null) {
      await _disposeCamera();
      _cameraController = null;
    }

    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
        _isDisposed = false;
      });
      _logger.i("Camera initialized successfully for ActiveNavigationScreen.");

      if (!_cameraController!.value.isStreamingImages) {
        // Only start if not already streaming
        _cameraController!.startImageStream((CameraImage image) {
          _throttler.run(() {
            _processCameraImage(image);
          });
        });
      }
    } on CameraException catch (e) {
      _logger.e(
        "Camera initialization failed for ActiveNavigationScreen: ${e.code}: ${e.description}",
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: ${e.description}')),
        );
        setState(() {
          _isCameraInitialized = false;
        });
      }
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!mounted || _objectDetector == null || _isDisposed) return;

    if (_imageSize == Size.zero) {
      _imageSize = Size(image.width.toDouble(), image.height.toDouble());
    }

    final InputImageRotation rotation;
    switch (image.planes[0].bytesPerRow ~/ image.width) {
      case 1:
        rotation = InputImageRotation.rotation0deg;
        break;
      case 2:
        rotation = InputImageRotation.rotation90deg;
        break;
      case 4:
        rotation = InputImageRotation.rotation180deg;
        break;
      default:
        rotation = InputImageRotation.rotation270deg;
        break;
    }

    final InputImage inputImage = InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: _imageSize,
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );

    try {
      final List<DetectedObject> objects = await _objectDetector!.processImage(
        inputImage,
      );
      if (mounted) {
        setState(() {
          _detectedObjects = objects;
        });
      }
    } catch (e) {
      _logger.e("Object detection failed in navigation: $e");
    }
  }

  Future<void> _disposeCamera() async {
    if (_cameraController == null || _isDisposed) {
      _logger.d(
        "Camera controller is already null or disposed. Skipping disposal.",
      );
      return;
    }
    _logger.i("Disposing camera controller for ActiveNavigationScreen.");
    _isDisposed = true;

    if (_cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream().catchError(
        (e) => _logger.e("Error stopping image stream: $e"),
      );
    }
    await _cameraController!.dispose().catchError(
      (e) => _logger.e("Error disposing camera controller: $e"),
    );
    _cameraController = null;
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
      });
    }
    _logger.i(
      "Camera controller for ActiveNavigationScreen successfully disposed.",
    );
  }

  Future<void> _startLocationUpdates() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _logger.e("Location permissions denied.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions denied.')),
        );
      }
      return;
    }

    _positionStreamSubscription?.cancel(); // Cancel any existing subscription

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
            _distanceToDestination = Geolocator.distanceBetween(
              _currentPosition.latitude,
              _currentPosition.longitude,
              widget.destination.latitude,
              widget.destination.longitude,
            );
          });
          _resolveCurrentAddress(position);
          _provideNavigationGuidance();
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
      if (placemarks.isNotEmpty && mounted) {
        final placemark = placemarks.first;
        setState(() {
          _currentAddress =
              '${placemark.street}, ${placemark.locality}, ${placemark.country}';
        });
      }
    } catch (e) {
      _logger.e("Error resolving current address: $e");
      if (mounted) {
        setState(() {
          _currentAddress = 'Address not found.';
        });
      }
    }
  }

  Future<void> _resolveDestinationAddress() async {
    try {
      List<geocoding.Placemark> placemarks = await geocoding
          .placemarkFromCoordinates(
            widget.destination.latitude,
            widget.destination.longitude,
          );
      if (placemarks.isNotEmpty && mounted) {
        final placemark = placemarks.first;
        setState(() {
          _destinationAddress =
              '${placemark.street}, ${placemark.locality}, ${placemark.country}';
        });
      }
    } catch (e) {
      _logger.e("Error resolving destination address: $e");
      if (mounted) {
        setState(() {
          _destinationAddress = 'Destination address not found.';
        });
      }
    }
  }

  void _provideNavigationGuidance() {
    if (_distanceToDestination < 50) {
      _speechService.speak("You have arrived at your destination.");
      Vibration.vibrate(duration: 500);
      _stopNavigation();
    } else if (_distanceToDestination < 200 && _distanceToDestination >= 50) {
      _speechService.speak("You are close to your destination.");
    } else if (_distanceToDestination < 500 && _distanceToDestination >= 200) {
      _speechService.speak("Continue straight.");
    }
  }

  void _stopNavigation() {
    _positionStreamSubscription?.cancel();
    _speechService.speak("Navigation ended.");
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.i(
      "AppLifecycleState changed to: $state for ActiveNavigationScreen.",
    );
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isDisposed) {
      _logger.d(
        "Camera not initialized or already disposed during lifecycle change. Ignoring.",
      );
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _logger.i("App inactive, disposing camera controller.");
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _logger.i("App resumed, re-initializing camera controller.");
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          await Future.delayed(const Duration(milliseconds: 500));
          _initializeCamera();
        }
      });
    }
  }

  @override
  void dispose() {
    _logger.i("ActiveNavigationScreen disposed, releasing resources.");
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _positionStreamSubscription?.cancel();
    _disposeCamera();
    _objectDetector?.close();
    _throttler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Navigation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.stop),
            onPressed: _stopNavigation,
            tooltip: 'Stop Navigation',
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_cameraController!)),
          CustomPaint(
            painter: ObjectPainter(_detectedObjects, _imageSize),
            child: Container(),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Location:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      _currentAddress,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Destination:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      _destinationAddress,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Distance: ${_distanceToDestination.toStringAsFixed(2)} meters',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ObjectPainter extends CustomPainter {
  final List<DetectedObject> detections;
  final Size previewSize;

  ObjectPainter(this.detections, this.previewSize);

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / previewSize.width;
    final scaleY = size.height / previewSize.height;

    final Paint paint =
        Paint()
          ..color = Colors.blueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;

    final TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: 16.0,
      fontWeight: FontWeight.bold,
      shadows: [
        Shadow(
          blurRadius: 3.0,
          color: Colors.black.withOpacity(0.8),
          offset: const Offset(1.0, 1.0),
        ),
      ],
    );

    for (var object in detections) {
      final Rect scaledRect = Rect.fromLTRB(
        object.boundingBox.left * scaleX,
        object.boundingBox.top * scaleY,
        object.boundingBox.right * scaleX,
        object.boundingBox.bottom * scaleY,
      );

      canvas.drawRect(scaledRect, paint);

      final label =
          object.labels.isNotEmpty
              ? "${object.labels.first.text} (${(object.labels.first.confidence * 100).toStringAsFixed(1)}%)"
              : "Unknown";

      final textPainter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final backgroundPaint = Paint()..color = Colors.black54;
      final textRect = Rect.fromLTWH(
        scaledRect.left,
        scaledRect.top - textPainter.height - 5,
        textPainter.width + 10,
        textPainter.height + 5,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(textRect, const Radius.circular(5)),
        backgroundPaint,
      );

      textPainter.paint(
        canvas,
        Offset(scaledRect.left + 5, scaledRect.top - textPainter.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Throttler {
  final int milliseconds;
  DateTime? _lastRun;
  Timer? _timer;

  _Throttler({required this.milliseconds});

  void run(VoidCallback action) {
    if (_lastRun == null ||
        DateTime.now().difference(_lastRun!) >
            Duration(milliseconds: milliseconds)) {
      _lastRun = DateTime.now();
      action();
    } else {
      _timer?.cancel();
      _timer = Timer(Duration(milliseconds: milliseconds), () {
        _lastRun = DateTime.now();
        action();
      });
    }
  }

  void dispose() {
    _timer?.cancel();
  }
}
