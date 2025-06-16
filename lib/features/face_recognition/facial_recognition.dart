// lib/features/face_recognition/facial_recognition.dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:assist_lens/main.dart'; // For routeObserver
import 'package:assist_lens/features/face_recognition/facial_recognition_state.dart';
import 'package:assist_lens/core/services/camera_service.dart';
// Import Database Helper

class FacialRecognition extends StatefulWidget {
  final bool autoStartLive;

  const FacialRecognition({super.key, this.autoStartLive = false});

  @override
  State<FacialRecognition> createState() => _FacialRecognitionState();
}

class _FacialRecognitionState extends State<FacialRecognition>
    with WidgetsBindingObserver, RouteAware {
  final Logger _logger = logger;
  late FacialRecognitionState _facialRecognitionState;
  
  // Track page visibility and initialization state
  bool _isPageActive = false;
  bool _isInitialized = false;
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isDisposing) return;
    
    _facialRecognitionState = Provider.of<FacialRecognitionState>(context, listen: false);

    // Subscribe to RouteObserver
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }

    // Initialize only if not already initialized and page is becoming active
    if (!_isInitialized) {
      _isInitialized = true;
      _isPageActive = true;
      _initializePageResources();
    }
  }

  /// Initialize all page resources
  void _initializePageResources() {
    if (_isDisposing || !_isPageActive) return;
    
    _logger.d('FacialRecognition: Initializing page resources');
    
    // Initialize camera and start live feed with a small delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_isDisposing && _isPageActive && mounted) {
        _facialRecognitionState.initCamera().then((_) {
          if (!_isDisposing && _isPageActive && mounted && widget.autoStartLive) {
            _facialRecognitionState.startLiveFeed();
          }
        }).catchError((error) {
          _logger.e('FacialRecognition: Error initializing camera: $error');
        });
      }
    });
  }

  /// Clean up all page resources
  void _cleanupPageResources({bool keepProcessingFlags = false}) {
    if (_isDisposing) return;
    
    _logger.d('FacialRecognition: Cleaning up page resources');
    
    // Stop live feed first
    _facialRecognitionState.stopLiveFeed();
    
    // Stop any ongoing detection or registration
    if (!keepProcessingFlags) {
      _facialRecognitionState.clearDetectedFaceName();
    }
    
    // Dispose camera resources
    _facialRecognitionState.disposeCamera();
    
    _logger.d('FacialRecognition: Page resources cleaned up');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isDisposing) return;
    
    _logger.d('FacialRecognition: App lifecycle state changed to: $state');
    
    switch (state) {
      case AppLifecycleState.resumed:
        if (_isPageActive) {
          // Add delay to allow proper resource initialization
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!_isDisposing && _isPageActive && mounted) {
              _initializePageResources();
            }
          });
        }
        break;
        
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Immediately clean up resources when app goes to background
        _cleanupPageResources(keepProcessingFlags: false);
        break;
    }
  }

  @override
  void didPopNext() {
    // Called when returning to this page from another page
    if (_isDisposing) return;
    
    _logger.d('FacialRecognition: Returning to page (didPopNext)');
    _isPageActive = true;
    
    // Add delay to ensure previous page resources are fully released
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_isDisposing && _isPageActive && mounted) {
        _initializePageResources();
      }
    });
  }

  @override
  void didPushNext() {
    // Called when navigating away from this page
    _logger.d('FacialRecognition: Navigating away from page (didPushNext)');
    _isPageActive = false;
    _cleanupPageResources(keepProcessingFlags: false);
  }

  @override
  void didPush() {
    // Called when this page is pushed onto the navigation stack
    _logger.d('FacialRecognition: Page pushed (didPush)');
    _isPageActive = true;
  }

  @override
  void didPop() {
    // Called when this page is popped from the navigation stack
    _logger.d('FacialRecognition: Page popped (didPop)');
    _isPageActive = false;
    _cleanupPageResources(keepProcessingFlags: false);
  }

  @override
  void deactivate() {
    // Called when the page is being deactivated
    _logger.d('FacialRecognition: Page deactivated');
    _isPageActive = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _logger.d('FacialRecognition: Disposing widget');
    _isDisposing = true;
    _isPageActive = false;
    
    // Remove observers
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    
    // Final cleanup of all resources
    _cleanupPageResources(keepProcessingFlags: false);
    
    _logger.d('FacialRecognition: Widget disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer2<FacialRecognitionState, CameraService>(
      builder: (context, state, cameraService, child) {
        return Scaffold(
          backgroundColor: colorScheme.surface,
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
                      'Face Recognition',
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
              onPressed: () {
                // Ensure cleanup before navigation
                _isPageActive = false;
                _cleanupPageResources(keepProcessingFlags: false);
                Navigator.pop(context);
              },
            ),
            actions: [
              // Flash Toggle
              IconButton(
                icon: Icon(
                  cameraService.isFlashOn
                      ? Icons.flash_on_rounded
                      : Icons.flash_off_rounded,
                  color: colorScheme.onPrimary,
                ),
                onPressed: _isPageActive && 
                          !_isDisposing && 
                          cameraService.isCameraInitialized
                    ? cameraService.toggleFlash
                    : null,
                tooltip: 'Toggle Flash',
              ),
              // Camera Switch
              IconButton(
                icon: Icon(
                  Icons.cameraswitch_rounded,
                  color: colorScheme.onPrimary,
                ),
                onPressed: _isPageActive && 
                          !_isDisposing && 
                          cameraService.isCameraInitialized &&
                          !state.isDetecting &&
                          !state.registrationInProgress
                    ? () async {
                        // Stop live feed before switching camera
                        state.stopLiveFeed();
                        await cameraService.toggleCamera();
                        // Restart live feed after switching
                        if (_isPageActive && !_isDisposing) {
                          Future.delayed(const Duration(milliseconds: 300), () {
                            if (_isPageActive && !_isDisposing && mounted) {
                              state.startLiveFeed();
                            }
                          });
                        }
                      }
                    : null,
                tooltip: 'Switch Camera',
              ),
              // Start/Stop Live Feed Toggle
              IconButton(
                icon: Icon(
                  state.isDetecting
                      ? Icons.pause_circle_outline_rounded
                      : Icons.play_circle_outline_rounded,
                  color: colorScheme.onPrimary,
                ),
                onPressed: _isPageActive && 
                          !_isDisposing && 
                          cameraService.isCameraInitialized &&
                          !state.registrationInProgress
                    ? () {
                        if (state.isDetecting) {
                          state.stopLiveFeed();
                        } else {
                          state.startLiveFeed();
                        }
                      }
                    : null,
                tooltip: state.isDetecting ? 'Pause Detection' : 'Start Detection',
              ),
            ],
          ),
          body: Stack(
            children: [
              // Camera Preview
              if (cameraService.cameraController != null &&
                  cameraService.cameraController!.value.isInitialized &&
                  _isPageActive)
                Positioned.fill(
                  child: AspectRatio(
                    aspectRatio: cameraService.cameraController!.value.aspectRatio,
                    child: CameraPreview(cameraService.cameraController!),
                  ),
                )
              else
                Center(
                  child: state.cameraInitializationError != null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 64,
                              color: colorScheme.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Camera Error',
                              style: textTheme.headlineSmall?.copyWith(
                                color: colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32.0),
                              child: Text(
                                state.cameraInitializationError!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _isPageActive && !_isDisposing
                                  ? _initializePageResources
                                  : null,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _isPageActive
                                  ? 'Initializing camera...'
                                  : 'Camera paused',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                ),

              // Face Bounding Boxes (only when page is active)
              if (_isPageActive &&
                  state.isCameraReady &&
                  state.faces.isNotEmpty &&
                  cameraService.cameraController != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: FaceDetectorPainter(
                      state.faces,
                      cameraService.cameraController!.value.previewSize!,
                      cameraService.cameraController!.description.lensDirection,
                    ),
                  ),
                ),

              // Processing Overlay and Messages
              if ((state.isDetecting || state.registrationInProgress) && _isPageActive)
                Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: colorScheme.onPrimary),
                      const SizedBox(height: 20),
                      Text(
                        state.processingMessage ?? 'Processing...',
                        style: textTheme.titleMedium?.copyWith(
                          color: colorScheme.onPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

              // Detected Face Name / Instruction
              if (_isPageActive)
                Positioned(
                  bottom: 100,
                  left: 20,
                  right: 20,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: state.detectedFaceName != null
                            ? Colors.green.withOpacity(0.8)
                            : colorScheme.surfaceContainerHighest.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha((0.2 * 255).round()),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Text(
                        state.detectedFaceName != null
                            ? 'Recognized: ${state.detectedFaceName}'
                            : state.isDetecting
                                ? 'Looking for faces...'
                                : 'Tap play to start detection',
                        style: textTheme.titleMedium?.copyWith(
                          color: state.detectedFaceName != null
                              ? Colors.white
                              : colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          floatingActionButton: _isPageActive &&
                  !_isDisposing &&
                  state.isCameraReady &&
                  !state.isDetecting
              ? FloatingActionButton.extended(
                  onPressed: !state.registrationInProgress
                      ? () => state.captureAndRegisterFace(context)
                      : null,
                  label: Text(
                    state.registrationInProgress
                        ? 'Registering...'
                        : (state.detectedFaceName != null
                            ? 'Register Another'
                            : 'Register Face'),
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  icon: state.registrationInProgress
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: colorScheme.onPrimary,
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          Icons.person_add_alt_1_rounded,
                          color: colorScheme.onPrimary,
                        ),
                  backgroundColor: !state.registrationInProgress
                      ? colorScheme.primary
                      : colorScheme.primary.withOpacity(0.7),
                  tooltip: 'Register a new face',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                )
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }
}

class FaceDetectorPainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final CameraLensDirection cameraLensDirection;

  FaceDetectorPainter(this.faces, this.imageSize, this.cameraLensDirection);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.green;

    // Draw face confidence indicator
    final Paint confidencePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.green.withOpacity(0.3);

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    for (Face face in faces) {
      // Adjust bounding box for front camera mirror effect
      final left = cameraLensDirection == CameraLensDirection.front
          ? size.width - (face.boundingBox.right * scaleX)
          : face.boundingBox.left * scaleX;
      final top = face.boundingBox.top * scaleY;
      final right = cameraLensDirection == CameraLensDirection.front
          ? size.width - (face.boundingBox.left * scaleX)
          : face.boundingBox.right * scaleX;
      final bottom = face.boundingBox.bottom * scaleY;

      final rect = Rect.fromLTRB(left, top, right, bottom);
      
      // Draw face bounding box
      canvas.drawRect(rect, paint);
      
      // Draw confidence indicator (optional)
      if (face.headEulerAngleY != null) {
        final confidenceHeight = (rect.height * 0.1) * (face.headEulerAngleY!.abs() / 90.0);
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top - confidenceHeight - 5, rect.width, confidenceHeight),
          confidencePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is FaceDetectorPainter && oldDelegate.faces != faces;
  }
}