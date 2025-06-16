// lib/features/scene_description/scene_description_page.dart
// Required for File
import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; // For CameraPreview
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import 'package:assist_lens/features/scene_description/scene_description_state.dart'; // Import SceneDescriptionState
import 'package:assist_lens/core/services/camera_service.dart'; // NEW: Import CameraService
import 'package:assist_lens/main.dart'; // For global logger and routeObserver
// Import AppRouter

class SceneDescriptionPage extends StatefulWidget {
  final bool autoDescribe;

  const SceneDescriptionPage({super.key, this.autoDescribe = false});

  @override
  State<SceneDescriptionPage> createState() => _SceneDescriptionPageState();
}

class _SceneDescriptionPageState extends State<SceneDescriptionPage>
    with WidgetsBindingObserver, RouteAware {
  final Logger _logger = logger; // Using global logger
  SceneDescriptionState? _sceneDescriptionState; // Now nullable
  late CameraService _cameraService; // Reference to CameraService

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Observe app lifecycle
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get CameraService instance via Provider
    _cameraService = Provider.of<CameraService>(context, listen: false);
    // Add listener to CameraService for status changes
    _cameraService.addListener(_onCameraServiceStatusChanged);

    // Get SceneDescriptionState instance (now initialized here)
    _sceneDescriptionState = Provider.of<SceneDescriptionState>(context, listen: false);

    // Register this route with RouteObserver
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);

    // Initial camera setup when the screen is first becoming active
    _initializeCameraForScreen();
  }

  /// This method is called when the current route is popped off, and the user returns to this route.
  @override
  void didPopNext() {
    _logger.i("SceneDescriptionPage: didPopNext - Resuming from next route.");
    // Re-initialize camera when returning to this screen
    _initializeCameraForScreen();
    super.didPopNext();
  }

  /// This method is called when the current route is pushed onto, and is no longer the top-most route.
  @override
  void didPushNext() {
    _logger.i("SceneDescriptionPage: didPushNext - Navigating to next route. Stopping camera.");
    // Stop camera and stream when navigating away from this screen
    _stopCameraForScreen();
    super.didPushNext();
  }

  /// Handles application lifecycle state changes.
  /// Stops camera when app goes to background and re-initializes when it resumes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _logger.i("SceneDescriptionPage: App lifecycle state changed: $state");
    if (state == AppLifecycleState.inactive) {
      _stopCameraForScreen(); // Stop camera when app is inactive
    } else if (state == AppLifecycleState.resumed) {
      _initializeCameraForScreen(); // Re-initialize camera when app resumes
    }
  }

  /// Centralized method to initialize the camera for this screen's use.
  Future<void> _initializeCameraForScreen() async {
    _logger.i("SceneDescriptionPage: _initializeCameraForScreen called.");
    // Only initialize camera if it's not already initialized by the service
    // for this screen's needs. CameraService is now smart about idempotency.
    await _cameraService.initializeCamera();
    // Pass controller to state AFTER CameraService has potentially initialized it
    _sceneDescriptionState?.setCameraController(_cameraService.cameraController);
    if (widget.autoDescribe && _cameraService.isCameraInitialized) {
      _sceneDescriptionState?.startAutoDescription(); // Use null-aware access
    }
  }

  /// Centralized method to stop and dispose the camera for this screen's use.
  Future<void> _stopCameraForScreen() async {
    _logger.i("SceneDescriptionPage: _stopCameraForScreen called.");
    // Stop any live description first
    _sceneDescriptionState?.stopAutoDescription(); // Use null-aware access
    // Dispose the camera controller via the service
    await _cameraService.disposeCamera();
  }

  /// Callback for CameraService status changes. Triggers a UI rebuild if mounted.
  void _onCameraServiceStatusChanged() {
    _logger.d("SceneDescriptionPage: CameraService status changed. Initialized: ${_cameraService.isCameraInitialized}, Streaming: ${_cameraService.isStreamingImages}, Error: ${_cameraService.cameraErrorMessage}");
    if (!mounted) return;
    // Notify the SceneDescriptionState that the camera controller might have changed
    _sceneDescriptionState?.setCameraController(_cameraService.cameraController); // Use null-aware access
    setState(() {}); // Rebuild to reflect camera status changes in UI
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Use Consumer to react to SceneDescriptionState changes
    // The 'state' provided here is guaranteed to be non-nullable if provider is set up correctly.
    return Consumer<SceneDescriptionState>(
      builder: (context, state, child) {
        // Show loading/error state if camera is not initialized by the CameraService
        // We use _cameraService.isCameraInitialized directly here as it's the source of truth
        if (!_cameraService.isCameraInitialized) {
          return Scaffold(
            appBar: AppBar(
              title: Text('Scene Description', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text(
                    _cameraService.cameraErrorMessage ?? "Initializing camera...",
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (_cameraService.cameraErrorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: ElevatedButton(
                        onPressed: _initializeCameraForScreen, // Retry initialization
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.secondary,
                          foregroundColor: colorScheme.onSecondary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        child: Text('Retry Camera', style: GoogleFonts.poppins(fontSize: 16)),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        // Main UI when camera is initialized
        return Scaffold(
          appBar: AppBar(
            title: Text('Scene Description', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            actions: [
              IconButton(
                icon: Icon(_cameraService.isFlashOn ? Icons.flash_on : Icons.flash_off),
                onPressed: () async {
                  await _cameraService.toggleFlash();
                },
              ),
              IconButton(
                icon: Icon(Icons.cameraswitch),
                onPressed: () async {
                  await _cameraService.toggleCamera();
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              // Camera Preview fills the background
              Positioned.fill(
                child: CameraPreview(_cameraService.cameraController!), // ! is safe here due to the _cameraService.isCameraInitialized check above
              ),
              // Dim overlay when processing
              if (state.isProcessing) // Access isProcessing directly from the non-nullable 'state'
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.5), // Deprecated withOpacity, will fix below
                    child: Center(
                      child: CircularProgressIndicator(color: colorScheme.secondary),
                    ),
                  ),
                ),
              // Draggable scrollable sheet for results and controls
              DraggableScrollableSheet(
                initialChildSize: 0.25,
                minChildSize: 0.1,
                maxChildSize: 0.7,
                expand: false,
                builder: (BuildContext context, ScrollController scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withAlpha((0.95 * 255).round()), // Slight transparency
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2), // Deprecated withOpacity
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Handle for dragging the sheet
                        Container(
                          height: 40,
                          alignment: Alignment.center,
                          child: Container(
                            width: 60,
                            height: 5,
                            decoration: BoxDecoration(
                              color: colorScheme.onSurface.withOpacity(0.3), // Deprecated withOpacity
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Scene Description',
                                  style: GoogleFonts.poppins(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Display description
                                if (state.sceneDescription != null)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      state.sceneDescription!, // ! is safe due to null check
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        color: colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                if (state.sceneDescription == null && !state.isProcessing)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest, // Use surfaceContainerHighest
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'Tap "Describe" to get a description of the scene.',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontStyle: FontStyle.italic,
                                        color: colorScheme.onSurfaceVariant.withAlpha((0.7 * 255).round()), // Use .withAlpha
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 20),
                                // Error message display
                                if (state.errorMessage != null)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'Error: ${state.errorMessage!}', // ! is safe due to null check
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 20),
                                // Action Buttons
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: Icon(Icons.description, color: colorScheme.onSecondary),
                                        label: Text(
                                          'Describe',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        onPressed: state.isProcessing || !state.isInitialized // Access directly
                                            ? null
                                            : () => state.takePictureAndDescribeScene(), // Access directly
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colorScheme.secondary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          elevation: 5,
                                          shadowColor: colorScheme.secondary.withAlpha((0.3 * 255).round()),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: Icon(Icons.mic, color: colorScheme.onPrimary),
                                        label: Text(
                                          'Speak',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        onPressed: state.isProcessing || state.sceneDescription == null // Access directly
                                            ? null
                                            : () => state.speakDescription(), // Access directly
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colorScheme.primary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          elevation: 5,
                                          shadowColor: colorScheme.primary.withAlpha((0.3 * 255).round()),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: Icon(Icons.send, color: colorScheme.onTertiary),
                                        label: Text(
                                          'Send to Chat',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        onPressed: state.isProcessing || state.sceneDescription == null // Access directly
                                            ? null
                                            : () => state.sendDescriptionToChat(), // Access directly
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colorScheme.tertiary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          elevation: 5,
                                          shadowColor: colorScheme.tertiary.withAlpha((0.3 * 255).round()),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        icon: Icon(Icons.clear, color: colorScheme.onError),
                                        label: Text(
                                          'Clear',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        onPressed: state.isProcessing || (state.sceneDescription == null && state.errorMessage == null) // Access directly
                                            ? null
                                            : () => state.clearResults(), // Access directly
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colorScheme.error,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          elevation: 5,
                                          shadowColor: colorScheme.error.withAlpha((0.3 * 255).round()),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                if (state.isAutoDescribing)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10.0),
                                    child: Center(
                                      child: Text(
                                        "Auto-describing...",
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontStyle: FontStyle.italic,
                                          color: colorScheme.onSurface.withAlpha((0.8 * 255).round()), // Use .withAlpha
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _logger.i("SceneDescriptionPage: Disposing widget.");
    WidgetsBinding.instance.removeObserver(this); // Stop observing lifecycle
    routeObserver.unsubscribe(this); // Unsubscribe from route observer
    // Remove listener from CameraService to prevent memory leaks
    _cameraService.removeListener(_onCameraServiceStatusChanged);
    _stopCameraForScreen(); // Ensure camera resources are properly released
    super.dispose();
  }
}
