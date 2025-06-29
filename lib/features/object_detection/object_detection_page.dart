import 'dart:async';
import 'package:assist_lens/core/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; // For CameraImage and CameraLensDirection
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart'; // For DetectedObject
import 'package:logger/logger.dart'; // Import logger
import 'package:provider/provider.dart';
import 'package:assist_lens/core/services/camera_service.dart';
import 'package:assist_lens/features/aniwa_chat/state/chat_state.dart';
import 'package:assist_lens/main.dart'; // For global logger
import 'package:assist_lens/features/object_detection/object_detection_state.dart'; // Import the new state

/// Custom painter to draw bounding boxes and labels for detected objects.
/// This class remains largely the same, as it's a UI rendering component.
class ObjectDetectorPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize; // Size of the image frame from the camera
  final CameraLensDirection cameraLensDirection; // Direction of the camera lens

  ObjectDetectorPainter(this.objects, this.imageSize, this.cameraLensDirection);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..color = Colors.red; // Color for bounding boxes

    final TextPainter textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    const TextStyle textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14.0,
      fontWeight: FontWeight.bold,
    );

    // Calculate scaling factors to map image coordinates to canvas coordinates.
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    for (DetectedObject object in objects) {
      // Adjust bounding box coordinates based on camera lens direction (mirroring for front camera).
      final Rect scaledRect = Rect.fromLTRB(
        cameraLensDirection == CameraLensDirection.front
            ? size.width - (object.boundingBox.right * scaleX)
            : object.boundingBox.left * scaleX,
        object.boundingBox.top * scaleY,
        cameraLensDirection == CameraLensDirection.front
            ? size.width - (object.boundingBox.left * scaleX)
            : object.boundingBox.right * scaleX,
        object.boundingBox.bottom * scaleY,
      );

      canvas.drawRect(scaledRect, paint); // Draw the bounding box

      // Prepare the label text for the detected object.
      final label =
          object.labels.isNotEmpty
              ? "${object.labels.first.text} (${(object.labels.first.confidence * 100).toStringAsFixed(1)}%)"
              : "Unknown";

      textPainter.text = TextSpan(text: label, style: textStyle);
      textPainter.layout(); // Layout the text to get its size

      // Draw a black background for the text for better readability.
      final backgroundPaint = Paint()..color = Colors.black54;
      final textRect = Rect.fromLTWH(
        scaledRect.left,
        scaledRect.top -
            textPainter.height -
            5, // Position above the bounding box
        textPainter.width + 10, // Add padding to text width
        textPainter.height + 5, // Add padding to text height
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(textRect, const Radius.circular(5)),
        backgroundPaint,
      );

      // Paint the text label.
      textPainter.paint(
        canvas,
        Offset(scaledRect.left + 5, scaledRect.top - textPainter.height - 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// A page dedicated to live object detection using the device's camera.
/// It leverages CameraService for managing camera resources and ML Kit for detection.
class ObjectDetectionPage extends StatefulWidget {
  final bool autoStartLive;

  const ObjectDetectionPage({super.key, this.autoStartLive = false});

  @override
  State<ObjectDetectionPage> createState() => _ObjectDetectionPageState();
}

class _ObjectDetectionPageState extends State<ObjectDetectionPage>
    with WidgetsBindingObserver, RouteAware {
  final Logger _logger = logger; // Using global logger
  late CameraService _cameraService; // Reference to the singleton CameraService
  late ObjectDetectionState
  _objectDetectionState; // Reference to the state manager
  bool _isPageActive =
      false; // To track if the page is currently visible and active
  late ChatState _chatState;
  bool _isDisposing = false; // To prevent operations during disposal

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Observe app lifecycle changes
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isDisposing) return;

    // Get instances of CameraService and ObjectDetectionState via Provider
    _cameraService = Provider.of<CameraService>(context, listen: false);
    _chatState = Provider.of<ChatState>(context, listen: false);
    _objectDetectionState = Provider.of<ObjectDetectionState>(
      context,
      listen: false,
    );

    // Listen to changes in ObjectDetectionState to trigger UI rebuilds
    _objectDetectionState.addListener(_onObjectDetectionStateChanged);

    final ModalRoute? route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }

    // Initial camera setup when the page becomes active
    if (_isPageActive) {
      _logger.i(
        "ObjectDetectionPage: didChangeDependencies - Page active. Initializing camera and stream if needed.",
      );
      _initializeCameraAndStartStream();
    }
  }

  /// Handles application lifecycle state changes.
  /// Stops camera when app goes to background and re-initializes when it resumes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposing || !mounted) return;
    _logger.i("ObjectDetectionPage: App lifecycle state changed: $state");

    switch (state) {
      case AppLifecycleState.resumed:
        if (_isPageActive) {
          _logger.i(
            "ObjectDetectionPage: App resumed and page is active. Initializing camera.",
          );
          _initializeCameraAndStartStream();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (_isPageActive) {
          _logger.i(
            "ObjectDetectionPage: App inactive/paused/detached/hidden. Stopping camera.",
          );
          _stopCameraAndStream();
        }
        break;
    }
  }

  /// Called when the current route has been pushed.
  @override
  void didPush() {
    _chatState.updateCurrentRoute(AppRouter.objectDetector);
    _chatState.setChatPageActive(true);
    _chatState.resume();
    _isPageActive = true;
    _logger.i("ObjectDetectionPage: Page pushed and is now active.");
    // If autoStartLive is true, ensure stream starts if camera is already initialized
    if (widget.autoStartLive &&
        _cameraService.isCameraInitialized &&
        !_cameraService.isStreamingImages) {
      _objectDetectionState.startImageStream();
    }
    super.didPush();
  }

  /// Called when this route is popped and the user returns to the previous route.
  @override
  void didPopNext() {
    if (_isDisposing) return;
    _isPageActive = true;
    _logger.i(
      "ObjectDetectionPage: didPopNext - Resuming from background or next route. Re-initializing camera.",
    );
    _chatState.updateCurrentRoute(AppRouter.objectDetector);
    "ObjectDetectionPage: Resuming from background or next route. Re-initializing camera.";

    _initializeCameraAndStartStream();
    super.didPopNext();
  }

  /// Called when the current route has been pushed.
  /// Stops camera and stream when navigating away from this screen to free resources.
  @override
  void didPushNext() {
    if (_isDisposing) return;
    _isPageActive = false;
    _chatState.setChatPageActive(false);
    _chatState.pause();
    _logger.i(
      "ObjectDetectionPage: Navigating to next route. Stopping camera.",
    );
    _stopCameraAndStream();
    super.didPushNext();
  }

  @override
  void didPop() {
    _chatState.setChatPageActive(false);
    _chatState.pause();
    _isPageActive = false;
    _logger.i("ObjectDetectionPage: Page popped. Stopping camera.");
    _stopCameraAndStream();
    super.didPop();
  }

  /// Initializes the camera via CameraService and starts the image stream for object detection.
  Future<void> _initializeCameraAndStartStream() async {
    if (_isDisposing || !mounted || !_isPageActive) return;
    _logger.i(
      "ObjectDetectionPage: Attempting to initialize camera and start stream...",
    );

    await _cameraService
        .initializeCamera(); // Initialize camera via CameraService

    if (mounted && _cameraService.isCameraInitialized && widget.autoStartLive) {
      // If camera initialized and autoStartLive is true, start the image stream
      _objectDetectionState.startImageStream();
    } else if (mounted && !_cameraService.isCameraInitialized) {
      _logger.e(
        "ObjectDetectionPage: CameraService failed to initialize. Error: ${_cameraService.cameraErrorMessage}",
      );
    }
  }

  /// Stops the camera image stream and disposes of the CameraController via CameraService.
  Future<void> _stopCameraAndStream() async {
    if (_isDisposing) return;
    _logger.i(
      "ObjectDetectionPage: Stopping camera stream and disposing controller via ObjectDetectionState.",
    );
    // Request ObjectDetectionState to stop image stream and dispose camera.
    await _objectDetectionState.disposeCamera();
    _logger.i(
      "ObjectDetectionPage: Camera stream stopped and controller disposed via ObjectDetectionState.",
    );
  }

  /// Callback for ObjectDetectionState status changes. Triggers a UI rebuild if mounted.
  void _onObjectDetectionStateChanged() {
    _logger.d(
      "ObjectDetectionPage: ObjectDetectionState status changed. Initialized: ${_cameraService.isCameraInitialized}, Streaming: ${_cameraService.isStreamingImages}, Error: ${_cameraService.cameraErrorMessage}",
    );
    if (!mounted) return;
    setState(() {
      // The UI will now react to changes notified by ObjectDetectionState.
      // _imageSize and _detectedObjects are retrieved directly from _objectDetectionState in build.
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Use Consumer to react to changes in ObjectDetectionState and rebuild UI.
    return Consumer<ObjectDetectionState>(
      builder: (context, objectDetectionState, child) {
        // Show loading/error state if camera is not initialized.
        if (!objectDetectionState.isCameraInitialized) {
          return Scaffold(
            appBar: AppBar(title: const Text('Object Detection')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    objectDetectionState.cameraErrorMessage ??
                        "Initializing camera...",
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (objectDetectionState.cameraErrorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: ElevatedButton(
                        onPressed: _initializeCameraAndStartStream,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'Retry Camera',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        // Main UI when camera is initialized.
        return Scaffold(
          appBar: AppBar(
            title: const Text('Object Detection'),
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            actions: [
              IconButton(
                icon: const Icon(Icons.cameraswitch), // Icon for camera switch
                onPressed:
                    objectDetectionState.isCameraInitialized
                        ? () async {
                          if (_isDisposing || !mounted) return;
                          // Stop current stream before toggling camera
                          await _objectDetectionState.stopImageStream();
                          // Toggle camera via CameraService
                          await _cameraService.toggleCamera();
                          if (mounted &&
                              _cameraService.isCameraInitialized &&
                              widget.autoStartLive) {
                            // Restart stream if conditions met after toggling
                            _objectDetectionState.startImageStream();
                          }
                        }
                        : null,
              ),
            ],
          ),
          body: Stack(
            children: [
              // Display the camera preview filling the entire available space.
              Positioned.fill(
                child: CameraPreview(_cameraService.cameraController!),
              ),
              // Overlay for detected objects.
              CustomPaint(
                painter: ObjectDetectorPainter(
                  objectDetectionState
                      .detectedObjects, // Get objects from state
                  objectDetectionState.imageSize, // Get image size from state
                  _cameraService.cameraController?.description.lensDirection ??
                      CameraLensDirection.back,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Disposes of resources when the widget is removed from the tree.
  @override
  void dispose() {
    _logger.i("ObjectDetectionPage: Disposing widget.");
    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this); // Stop observing lifecycle
    _objectDetectionState.removeListener(_onObjectDetectionStateChanged);
    routeObserver.unsubscribe(this);

    // Stop camera and stream, and dispose camera resources via ObjectDetectionState
    _stopCameraAndStream();

    super.dispose();
  }
}
