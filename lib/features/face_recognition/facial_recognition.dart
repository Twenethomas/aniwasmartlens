// lib/features/face_recognition/facial_recognition.dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import 'package:assist_lens/main.dart'; // For routeObserver
import 'package:assist_lens/features/face_recognition/facial_recognition_state.dart'; // Ensure this is correct

class FacialRecognition extends StatefulWidget {
  final bool autoStartLive;

  const FacialRecognition({super.key, this.autoStartLive = false});

  @override
  State<FacialRecognition> createState() => _FacialRecognitionState();
}

class _FacialRecognitionState extends State<FacialRecognition>
    with WidgetsBindingObserver, RouteAware {
  final Logger _logger = logger; // Using global logger
  late FacialRecognitionState _facialRecognitionState; // Declared as late

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // IMPORTANT: _facialRecognitionState initialization and RouteObserver subscription
    // are intentionally handled in didChangeDependencies for safer access to context and providers.
    // DO NOT initialize _facialRecognitionState here.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize the state here. This is guaranteed to be called after initState
    // and when the BuildContext is fully available and providers are ready.
    if (!mounted) return; // Ensure widget is still in the tree

    // Assign the provider instance to _facialRecognitionState
    _facialRecognitionState = Provider.of<FacialRecognitionState>(context);

    // Subscribe to RouteObserver now that _facialRecognitionState is initialized.
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    } else {
      _logger.w(
        "FacialRecognition: Current route is not a PageRoute. Cannot subscribe to RouteObserver.",
      );
    }

    // Initialize camera if autoStartLive is true and camera is not already initialized.
    // This handles the initial load of the page.
    if (widget.autoStartLive && !_facialRecognitionState.isCameraInitialized) {
      _logger.i(
        "FacialRecognition: didChangeDependencies - Initializing camera (autoStartLive).",
      );
      _facialRecognitionState.initCamera(
        autoStartLive: true,
      ); // Pass true directly as per usage
    }
  }

  @override
  void didPush() {
    _logger.i(
      "FacialRecognition: didPush - Page is active. Attempting to initialize camera.",
    );
    // This is called when this route is pushed onto the navigator.
    // Ensure _facialRecognitionState is ready before using.
    if (mounted && !_facialRecognitionState.isCameraInitialized) {
      _facialRecognitionState.initCamera(autoStartLive: true);
    }
    super.didPush();
  }

  @override
  void didPopNext() {
    _logger.i(
      "FacialRecognition: didPopNext - Returning to page. Resuming camera.",
    );
    // This is called when the top route has been popped off, and this route is now the top route.
    if (mounted && !_facialRecognitionState.isCameraInitialized) {
      _facialRecognitionState.initCamera(autoStartLive: true);
    }
    super.didPopNext();
  }

  @override
  void didPushNext() {
    _logger.i(
      "FacialRecognition: didPushNext - Navigating away from page. Disposing camera.",
    );
    // This is called when this route has been pushed off the navigator.
    if (mounted) {
      _facialRecognitionState.disposeCamera();
    }
    super.didPushNext();
  }

  @override
  void didPop() {
    _logger.i(
      "FacialRecognition: didPop - Page is being popped. Disposing camera.",
    );
    // This is called when this route has been popped off the navigator.
    if (mounted) {
      _facialRecognitionState.disposeCamera();
    }
    super.didPop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.i("AppLifecycleState changed to: $state for FacialRecognition.");
    // Ensure _facialRecognitionState is ready before using it in lifecycle changes.
    // The `_facialRecognitionState` is guaranteed to be initialized by `didChangeDependencies`
    // before `didChangeAppLifecycleState` is likely to be called with `inactive` or `resumed`.
    if (state == AppLifecycleState.inactive) {
      _logger.i("App inactive, disposing camera.");
      _facialRecognitionState.disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _logger.i("App resumed, re-initializing camera.");
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted && !_facialRecognitionState.isCameraInitialized) {
          _facialRecognitionState.initCamera(autoStartLive: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _logger.i("FacialRecognition disposed, unsubscribing from route observer.");
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    // FacialRecognitionState is provided at the root, so its dispose is handled by the provider.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch the FacialRecognitionState to rebuild UI on changes
    // This will trigger a rebuild when _facialRecognitionState's properties change.
    final state = context.watch<FacialRecognitionState>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Show loading indicator or error if camera is not initialized
    if (!state.isCameraInitialized ||
        state.cameraController == null ||
        !state.cameraController!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Facial Recognition',
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          backgroundColor: colorScheme.surface,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: colorScheme.onSurface,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                state.cameraInitializationError ?? 'Initializing camera...',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              if (state.cameraInitializationError != null)
                ElevatedButton(
                  onPressed: () {
                    // Call initCamera directly when button is pressed
                    state.initCamera(autoStartLive: true);
                  },
                  child: const Text('Try Again'),
                ),
            ],
          ),
        ),
      );
    }

    // Once camera is initialized, show the camera preview and controls
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Facial Recognition',
          style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface),
        ),
        backgroundColor: colorScheme.surface,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.flip_camera_ios_rounded,
              color: colorScheme.onSurface,
            ),
            onPressed: state.switchCamera,
            tooltip: 'Switch Camera',
          ),
          IconButton(
            icon: Icon(
              state.isLiveFeedActive
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_filled_rounded,
              color: colorScheme.onSurface,
            ),
            onPressed: () {
              state.toggleLiveFeed();
            },
            tooltip:
                state.isLiveFeedActive ? 'Pause Live Feed' : 'Resume Live Feed',
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(state.cameraController!)),
          if (state.isLiveFeedActive)
            CustomPaint(
              painter: FaceDetectorPainter(
                state.detectedFaces,
                state.imageSize,
                state
                    .cameraController!
                    .description
                    .lensDirection, // FIXED: Use description.lensDirection
              ),
              child: Container(),
            ),
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Column(
              children: [
                if (state.detectedFaceName.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Detected: ${state.detectedFaceName}',
                      style: textTheme.titleMedium?.copyWith(
                        color: colorScheme.onPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed:
                          state.isLiveFeedActive
                              ? () => state.captureAndRecognize(context)
                              : null,
                      icon: const Icon(Icons.camera),
                      label: const Text('Capture & Recognize'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed:
                          state.isLiveFeedActive
                              ? () => state.registerFace(context)
                              : null,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Register Face'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.secondary,
                        foregroundColor: colorScheme.onSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (state.processingMessage != null &&
                    state.processingMessage!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      state.processingMessage!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FaceDetectorPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final CameraLensDirection
  cameraLensDirection; // Changed type to CameraLensDirection

  FaceDetectorPainter(this.faces, this.imageSize, this.cameraLensDirection);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = Colors.green;

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    for (Face face in faces) {
      // Adjust bounding box for front camera mirror effect
      final left =
          cameraLensDirection == CameraLensDirection.front
              ? size.width - (face.boundingBox.right * scaleX)
              : face.boundingBox.left * scaleX;
      final top = face.boundingBox.top * scaleY;
      final right =
          cameraLensDirection == CameraLensDirection.front
              ? size.width - (face.boundingBox.left * scaleX)
              : face.boundingBox.right * scaleX;
      final bottom = face.boundingBox.bottom * scaleY;

      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), paint);
    }
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.faces != faces || oldDelegate.imageSize != imageSize;
  }
}
