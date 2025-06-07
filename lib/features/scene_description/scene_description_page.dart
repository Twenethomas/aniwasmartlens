// lib/features/scene_description/scene_description_page.dart
import 'package:assist_lens/main.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'scene_description_state.dart'; // Import SceneDescriptionState
import '../../core/services/speech_service.dart'; // Import SpeechService to directly call speak/stopSpeaking

class SceneDescriptionPage extends StatefulWidget {
  final bool autoDescribe;

  const SceneDescriptionPage({super.key, this.autoDescribe = false});

  @override
  State<SceneDescriptionPage> createState() => _SceneDescriptionPageState();
}

class _SceneDescriptionPageState extends State<SceneDescriptionPage> with RouteAware {
  late SceneDescriptionState _sceneDescriptionState;
  late SpeechService _speechService; // To manage speech directly
  bool _initialCameraSetupComplete = false; // Flag for initial camera init

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sceneDescriptionState = Provider.of<SceneDescriptionState>(context, listen: false);
    _speechService = Provider.of<SpeechService>(context, listen: false); // Get SpeechService

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) { // Ensure it's a PageRoute before subscribing
        routeObserver.subscribe(this, route);
      } else {
        logger.w("AniwaChatPage: Cannot subscribe to RouteObserver, current route is not a PageRoute.");
      }
    });

    if (!_initialCameraSetupComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _sceneDescriptionState.initCamera().then((_) {
            if (widget.autoDescribe && _sceneDescriptionState.isCameraReady) {
              _sceneDescriptionState.takePictureAndDescribe();
            }
          });
          _initialCameraSetupComplete = true;
        }
      });
    }
  }

  @override
  void didPush() {
    logger.i("SceneDescriptionPage: didPush - Page is active. Resuming camera.");
    // Only attempt to resume if the controller exists and isn't already streaming.
    // Initial camera setup handled by postFrameCallback in didChangeDependencies.
    // Ensure `initCamera` is called to resume stream or re-initialize if needed.
    if (_initialCameraSetupComplete && _sceneDescriptionState.cameraController != null && !_sceneDescriptionState.cameraController!.value.isStreamingImages) {
        _sceneDescriptionState.initCamera(); // This will resume stream or re-initialize as needed
    }
    super.didPush();
  }

  @override
  void didPopNext() {
    logger.i("SceneDescriptionPage: didPopNext - Returning to page. Resuming camera.");
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _sceneDescriptionState.initCamera(); // This will resume stream or re-initialize as needed
      }
    });
    super.didPopNext();
  }

  @override
  void didPushNext() {
    logger.i("SceneDescriptionPage: didPushNext - Navigating away from page. Disposing camera.");
    _speechService.stopSpeaking(); // Stop speaking if navigating away
    _sceneDescriptionState.disposeCamera(); // Dispose camera when leaving
    super.didPushNext();
  }

  @override
  void didPop() {
    logger.i("SceneDescriptionPage: didPop - Page is being popped. Disposing camera.");
    _speechService.stopSpeaking(); // Stop speaking if page is popped
    _sceneDescriptionState.disposeCamera(); // Dispose camera when popped
    super.didPop();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    // State disposal handled by Provider
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer<SceneDescriptionState>(
      builder: (context, state, child) {
        return Scaffold(
          backgroundColor: colorScheme.background,
          appBar: AppBar(
            title: Text(
              'Scene Description',
              style: GoogleFonts.sourceCodePro(
                color: colorScheme.onPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: colorScheme.primary,
            centerTitle: true,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: colorScheme.onPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.photo_library_rounded, color: colorScheme.onPrimary),
                onPressed: !state.isProcessingAI && !state.isCameraCapturing
                    ? state.pickImageAndDescribe
                    : null,
                tooltip: 'Pick from Gallery',
              ),
              IconButton(
                icon: Icon(Icons.clear_all_rounded, color: colorScheme.onPrimary),
                onPressed: !state.isProcessingAI && !state.isCameraCapturing
                    ? state.clearDescription
                    : null,
                tooltip: 'Clear Description',
              ),
            ],
          ),
          body: Stack(
            children: [
              if (state.isCameraReady && state.cameraController != null && state.cameraController!.value.isInitialized)
                Positioned.fill(
                  child: CameraPreview(state.cameraController!),
                )
              else
                Center(
                  child: state.errorMessage.isNotEmpty
                      ? Text(
                          state.errorMessage,
                          style: textTheme.headlineSmall?.copyWith(color: colorScheme.error),
                          textAlign: TextAlign.center,
                        )
                      : CircularProgressIndicator(color: colorScheme.primary),
                ),
              // Overlay for image description and controls
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withAlpha((0.9 * 255).round()), // Corrected deprecated `withOpacity`
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state.isProcessingAI || state.isCameraCapturing) // Corrected getter from isProcessing
                        LinearProgressIndicator(color: colorScheme.primary)
                      else
                        const SizedBox(height: 4),
                      const SizedBox(height: 8),
                      Text(
                        'Scene Description:',
                        style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.imageDescription.isNotEmpty // Corrected getter from sceneDescription
                            ? state.imageDescription
                            : (state.isProcessingAI // Corrected getter from isProcessing
                                ? 'Processing...'
                                : 'Take a picture or select one from gallery to get a description.'),
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          ElevatedButton.icon(
                            onPressed: !state.isProcessingAI && state.imageDescription.isNotEmpty
                                ? () => _speechService.speak(state.imageDescription) // Corrected getter from isProcessing
                                : null,
                            icon: Icon(Icons.volume_up_rounded, color: colorScheme.onPrimary),
                            label: Text('Speak', style: textTheme.labelLarge?.copyWith(color: colorScheme.onPrimary)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                          if (_speechService.isSpeaking) // Check global speaking status
                            ElevatedButton.icon(
                              onPressed: _speechService.stopSpeaking, // Corrected call from state.stopSpeaking
                              icon: Icon(Icons.stop_rounded, color: colorScheme.onError),
                              label: Text('Stop', style: textTheme.labelLarge?.copyWith(color: colorScheme.onError)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.error,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: !state.isProcessingAI && !state.isCameraCapturing && state.isCameraReady // Corrected getter from isProcessing
                ? state.takePictureAndDescribe // Corrected method name
                : null,
            tooltip: 'Take Picture',
            backgroundColor: !state.isProcessingAI && !state.isCameraCapturing && state.isCameraReady
                ? colorScheme.primary
                : colorScheme.primary.withAlpha((0.5 * 255).round()), // Corrected deprecated `withOpacity`
            child: state.isCameraCapturing || state.isProcessingAI
                ? CircularProgressIndicator(color: colorScheme.onPrimary)
                : Icon(Icons.camera_alt_rounded, color: colorScheme.onPrimary),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }
}
