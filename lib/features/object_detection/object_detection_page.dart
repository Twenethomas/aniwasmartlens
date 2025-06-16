import 'dart:async';
import 'dart:io'; // Required for Platform check
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:logger/logger.dart'; // Import logger
// Import for camera permission
import 'package:provider/provider.dart'; // NEW: Import Provider
import 'package:assist_lens/core/services/camera_service.dart'; // NEW: Import CameraService
import 'package:assist_lens/main.dart'; // For global logger

/// A page dedicated to live object detection using the device's camera.
class ObjectDetectionPage extends StatefulWidget {
  final bool autoStartLive; // NEW: Added autoStartLive parameter

  const ObjectDetectionPage({
    super.key,
    this.autoStartLive = false,
  }); // NEW: Constructor updated

  @override
  State<ObjectDetectionPage> createState() => _ObjectDetectionPageState();
}

class _ObjectDetectionPageState extends State<ObjectDetectionPage> with WidgetsBindingObserver, RouteAware {
  // CameraController is now managed by CameraService, no longer declared here.
  ObjectDetector? _objectDetector;
  List<DetectedObject> _detectedObjects = [];
  // _isCameraInitialized is now managed by CameraService
  bool _isDisposed = false; // Flag to track if the widget has been disposed
  Size _imageSize = Size.zero; // Size of the image frames from the camera
  final _throttler = _Throttler(milliseconds: 300); // Throttler for image processing
  final Logger _logger = logger; // Using global logger
  StreamSubscription<CameraImage>? _imageStreamSubscription; // Manages the camera image stream subscription
  bool _isDetectorProcessing = false; // Flag to prevent concurrent image processing by ML Kit

  // Camera switching is now handled by CameraService
  // No need for _availableCameras or _currentCameraIndex here anymore.

  late CameraService _cameraService; // Reference to the singleton CameraService

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Observe app lifecycle changes
    _initializeObjectDetector(); // Initialize the ML Kit detector
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Obtain the CameraService instance from the nearest Provider ancestor.
    // listen: false as we only need to access methods and add/remove listener,
    // not rebuild the entire widget when CameraService's state changes.
    _cameraService = Provider.of<CameraService>(context, listen: false);
    // Add a listener to CameraService to react to its internal state changes (e.g., initialization, errors).
    _cameraService.addListener(_onCameraServiceStatusChanged);

    // Initial camera setup when the screen is first becoming active.
    // We check !isCameraInitialized to avoid re-initializing if it's already done.
    if (!_cameraService.isCameraInitialized && !_isDisposed) {
      _initializeCameraAndStartStream();
    }
  }

  /// Called when this route is popped and the user returns to the previous route.
  /// Ensures the camera is re-initialized and streaming when returning to this screen.
  @override
  void didPopNext() {
    _logger.i("ObjectDetectionPage: Resuming from background or next route. Re-initializing camera.");
    _initializeCameraAndStartStream();
    super.didPopNext();
  }

  /// Called when the current route has been pushed.
  /// Stops camera and stream when navigating away from this screen to free resources.
  @override
  void didPushNext() {
    _logger.i("ObjectDetectionPage: Navigating to next route. Stopping camera.");
    _stopCameraAndStream();
    super.didPushNext();
  }

  /// Handles application lifecycle state changes.
  /// Stops camera when app goes to background and re-initializes when it resumes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.i("ObjectDetectionPage: App lifecycle state changed: $state");
    if (state == AppLifecycleState.inactive) {
      _stopCameraAndStream(); // Stop camera when app is inactive
    } else if (state == AppLifecycleState.resumed) {
      _initializeCameraAndStartStream(); // Re-initialize camera when app resumes
    }
  }

  /// Initializes the camera via CameraService and starts the image stream for object detection.
  Future<void> _initializeCameraAndStartStream() async {
    _logger.i("ObjectDetectionPage: Attempting to initialize camera and start stream...");
    // Only initialize camera if it's not already initialized.
    if (!_cameraService.isCameraInitialized) {
      await _cameraService.initializeCamera(); // Specify desired camera
    }

    // Only start image stream if camera is initialized and not already streaming.
    if (_cameraService.isCameraInitialized && !_cameraService.isStreamingImages) {
      // Ensure the object detector is initialized before starting the stream.
      if (_objectDetector == null) {
        _initializeObjectDetector(); // Re-initialize if for some reason it got null
      }
      // Start streaming images and subscribe to the stream.
      _imageStreamSubscription = _cameraService.startImageStream(_processCameraImage) as StreamSubscription<CameraImage>?;
      _logger.i("ObjectDetectionPage: Camera image stream started.");
    } else {
      _logger.d("ObjectDetectionPage: Camera not ready for stream or already streaming.");
    }
  }

  /// Stops the camera image stream and disposes of the CameraController via CameraService.
  Future<void> _stopCameraAndStream() async {
    _logger.i("ObjectDetectionPage: Stopping camera stream and disposing controller.");
    _imageStreamSubscription?.cancel(); // Cancel the local subscription first
    _imageStreamSubscription = null; // Clear the subscription reference
    await _cameraService.stopImageStream(); // Instruct CameraService to stop the stream
    await _cameraService.disposeCamera(); // Instruct CameraService to dispose the controller
    _logger.i("ObjectDetectionPage: Camera stream stopped and controller disposed.");
  }

  /// Callback for CameraService status changes. Triggers a UI rebuild if mounted.
  void _onCameraServiceStatusChanged() {
    _logger.d("ObjectDetectionPage: CameraService status changed. Initialized: ${_cameraService.isCameraInitialized}, Streaming: ${_cameraService.isStreamingImages}, Error: ${_cameraService.cameraErrorMessage}");
    if (!mounted) return;
    // Rebuild the UI to reflect changes in camera initialization or streaming status.
    setState(() {});
  }

  /// Initializes the Google ML Kit ObjectDetector.
  void _initializeObjectDetector() {
    _logger.i("ObjectDetectionPage: Initializing object detector.");
    // Define options for object detection.
    final modelPath = 'flutter_assets/ml/lite_model.tflite'; // Path to your TFLite model
    final options = ObjectDetectorOptions(
      mode: DetectionMode.stream, // Stream mode for live camera feed
      //modelPath: modelPath,
      classifyObjects: true, // Whether to classify detected objects
      multipleObjects: true, // Whether to detect multiple objects
      // confidenceThreshold: 0.5, // Optional: Adjust confidence threshold
    );
    _objectDetector = ObjectDetector(options: options);
    _logger.i("ObjectDetectionPage: Object detector initialized.");
  }

  /// Processes each camera image frame for object detection.
  Future<void> _processCameraImage(CameraImage cameraImage) async {
    // Prevent concurrent processing of images.
    if (_isDetectorProcessing) return;
    _isDetectorProcessing = true;

    // Use a throttler to limit the rate of image processing, improving performance.
    _throttler.run(() async {
      if (!mounted) return; // Ensure widget is still active

      final inputImage = _inputImageFromCameraImage(cameraImage);
      if (inputImage == null) {
        _logger.w("ObjectDetectionPage: Failed to create InputImage from CameraImage. Skipping frame.");
        _isDetectorProcessing = false;
        return;
      }

      try {
        // Process the image with the object detector.
        final List<DetectedObject> objects = await _objectDetector!.processImage(inputImage);
        if (mounted) {
          setState(() {
            _detectedObjects = objects; // Update detected objects for UI rendering
            _imageSize = Size(cameraImage.width.toDouble(), cameraImage.height.toDouble()); // Store actual image size
          });
        }
      } catch (e, stack) {
        _logger.e("ObjectDetectionPage: Error processing image for object detection: $e", error: e, stackTrace: stack);
      } finally {
        _isDetectorProcessing = false; // Allow next frame to be processed
      }
    });
  }

  /// Converts a CameraImage to an ML Kit InputImage format.
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    // Ensure CameraController is available to get essential metadata.
    final cameraController = _cameraService.cameraController;
    if (cameraController == null) {
      _logger.e("ObjectDetectionPage: CameraController is null when creating InputImage.");
      return null;
    }

    // Get the first plane of the image (Y plane for NV21, or BGRA plane for BGRA8888).
    final plane = image.planes.first;
    final bytes = plane.bytes;

    // Determine the image format based on the platform.
    final imageFormat = Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;

    // Determine the image rotation based on the camera orientation and device orientation.
    // Ensure you use the correct rotation for ML Kit processing.
    final InputImageMetadata inputImageData = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()), // Use the actual image size
      rotation: InputImageRotation.rotation0deg, // Adjust based on your camera setup
      format: imageFormat, // Use the determined format
      bytesPerRow: plane.bytesPerRow, // Required for NV21 format
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Consume CameraService changes to rebuild the UI when camera state changes.
    final cameraService = Provider.of<CameraService>(context);

    // Show loading/error state if camera is not initialized.
    if (!cameraService.isCameraInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text('Object Detection')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                cameraService.cameraErrorMessage ?? "Initializing camera...",
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (cameraService.cameraErrorMessage != null) // Show a retry button if there's an error
                Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: ElevatedButton(
                    onPressed: _initializeCameraAndStartStream, // Retry initialization
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Retry Camera', style: TextStyle(fontSize: 16)),
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
            icon: Icon(Icons.cameraswitch), // Icon for camera switch
            onPressed: () async {
              // Use CameraService's switchCamera method
              await cameraService.toggleCamera();
              // No need for setState here, _onCameraServiceStatusChanged will handle rebuilding
              // if relevant camera properties change, or rebuild will occur if controller changes.
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Display the camera preview filling the entire available space.
          Positioned.fill(
            child: CameraPreview(cameraService.cameraController!), // Use CameraService's controller
          ),
          // Overlay for detected objects.
          CustomPaint(
            painter: ObjectDetectorPainter(
              _detectedObjects,
              _imageSize, // Use the actual image size obtained from the camera image
              cameraService.cameraController!.description.lensDirection, // Pass camera lens direction for mirroring
            ),
          ),
        ],
      ),
    );
  }

  /// Disposes of resources when the widget is removed from the tree.
  @override
  void dispose() {
    _logger.i("ObjectDetectionPage: Disposing widget.");
    _isDisposed = true; // Set a flag to indicate disposal
    WidgetsBinding.instance.removeObserver(this); // Stop observing lifecycle
    // Remove listener from CameraService to prevent memory leaks.
    _cameraService.removeListener(_onCameraServiceStatusChanged);
    _stopCameraAndStream(); // Ensure camera resources are properly released.
    _objectDetector?.close(); // Close the ML Kit object detector.
    _throttler.dispose(); // Dispose the throttler's timer.
    _imageStreamSubscription?.cancel(); // Cancel any lingering image stream subscription.
    super.dispose();
  }
}

/// Custom painter to draw bounding boxes and labels for detected objects.
class ObjectDetectorPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize; // Size of the image frame from the camera
  final CameraLensDirection cameraLensDirection; // Direction of the camera lens

  ObjectDetectorPainter(this.objects, this.imageSize, this.cameraLensDirection);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
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
      final label = object.labels.isNotEmpty
          ? "${object.labels.first.text} (${(object.labels.first.confidence * 100).toStringAsFixed(1)}%)"
          : "Unknown";

      textPainter.text = TextSpan(text: label, style: textStyle);
      textPainter.layout(); // Layout the text to get its size

      // Draw a black background for the text for better readability.
      final backgroundPaint = Paint()..color = Colors.black54;
      final textRect = Rect.fromLTWH(
        scaledRect.left,
        scaledRect.top - textPainter.height - 5, // Position above the bounding box
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

/// A simple throttler utility to limit the rate of function calls.
class _Throttler {
  final int milliseconds;
  DateTime? _lastRun;
  Timer? _timer;

  _Throttler({required this.milliseconds});

  /// Runs the given [action] if enough time has passed since the last run.
  /// Otherwise, it schedules the action to run after the throttle duration.
  void run(VoidCallback action) {
    if (_lastRun == null ||
        DateTime.now().difference(_lastRun!) > Duration(milliseconds: milliseconds)) {
      _lastRun = DateTime.now();
      action();
    } else {
      _timer?.cancel(); // Cancel any pending timer
      _timer = Timer(Duration(milliseconds: milliseconds), () {
        _lastRun = DateTime.now();
        action();
      });
    }
  }

  /// Disposes of the internal timer to prevent memory leaks.
  void dispose() {
    _timer?.cancel();
  }
}
