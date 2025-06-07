// lib/features/text_reader/text_reader_page.dart
import 'package:assist_lens/main.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'text_reader_state.dart'; // Import TextReaderState

class TextReaderPage extends StatefulWidget {
  final bool autoCapture;
  final bool autoTranslate;
  final bool forChatIntegration;

  const TextReaderPage({
    super.key,
    this.autoCapture = false,
    this.autoTranslate = false,
    this.forChatIntegration = false,
  });

  @override
  State<TextReaderPage> createState() => _TextReaderPageState();
}

class _TextReaderPageState extends State<TextReaderPage> with RouteAware {
  late TextReaderState _textReaderState;
  bool _initialCameraSetupComplete = false; // Flag to ensure camera init runs only once

  @override
  void initState() {
    super.initState();
    // Initial camera setup will be handled in didChangeDependencies
    // to ensure Provider is available and to coordinate with RouteAware.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Obtain the TextReaderState instance. This is safe to do here.
    _textReaderState = Provider.of<TextReaderState>(context, listen: false);

    // Subscribe to route updates. This will trigger didPush/didPopNext.
    // Ensure this is called AFTER _textReaderState is initialized.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) { // Ensure it's a PageRoute before subscribing
        routeObserver.subscribe(this, route);
      } else {
        logger.w("AniwaChatPage: Cannot subscribe to RouteObserver, current route is not a PageRoute.");
      }
    });

    // Perform initial camera setup ONLY ONCE after the first frame is built.
    if (!_initialCameraSetupComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Ensure the widget is still mounted before performing operations.
        if (mounted) {
          _textReaderState.initCamera();
          _initialCameraSetupComplete = true;
        }
      });
    }
  }

  @override
  void didPush() {
    logger.i("TextReaderPage: didPush - Page is active.");
    // When the page is first pushed, `initCamera` is handled by the postFrameCallback in `didChangeDependencies`.
    // This `didPush` will be called *after* `didChangeDependencies`.
    // If the camera was already initialized and then paused (e.g., via `didPushNext`),
    // we should resume it here. Otherwise, the initial `initCamera` call handles the first activation.
    if (_initialCameraSetupComplete && _textReaderState.cameraController != null && !_textReaderState.cameraController!.value.isStreamingImages) {
      _textReaderState.resumeCamera();
    }
    super.didPush();
  }

  @override
  void didPopNext() {
    logger.i("TextReaderPage: didPopNext - Returning to page. Resuming camera.");
    // When returning to this page from another, always resume the camera.
    _textReaderState.resumeCamera();
    super.didPopNext();
  }

  @override
  void didPushNext() {
    logger.i("TextReaderPage: didPushNext - Navigating away from page. Pausing camera.");
    // When navigating away from this page, pause the camera to save resources.
    _textReaderState.pauseCamera();
    super.didPushNext();
  }

  @override
  void didPop() {
    logger.i("TextReaderPage: didPop - Page is being popped. Disposing camera.");
    // When the page is completely removed from the stack, dispose of the camera.
    _textReaderState.disposeCamera();
    super.didPop();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    // TextReaderState is disposed by Provider automatically when no longer needed.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer<TextReaderState>(
      builder: (context, state, child) {
        return Scaffold(
          backgroundColor: colorScheme.background,
          appBar: AppBar(
            title: Text(
              'Text Reader',
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
                icon: Icon(
                  state.isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: colorScheme.onPrimary,
                ),
                onPressed: state.isCameraReady ? state.toggleFlash : null,
                tooltip: 'Toggle Flash',
              ),
              IconButton(
                icon: Icon(Icons.clear_all_rounded, color: colorScheme.onPrimary),
                onPressed: state.clearResults,
                tooltip: 'Clear Results',
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

              // Overlay for detected text, corrected text, etc.
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withOpacity(0.9),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state.isProcessingImage || state.isProcessingAI)
                        LinearProgressIndicator(color: colorScheme.primary)
                      else
                        const SizedBox(height: 4),

                      const SizedBox(height: 8),

                      Text(
                        'Original Text:',
                        style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        state.recognizedText.isEmpty ? 'No text detected yet.' : state.recognizedText,
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),

                      Text(
                        'Detected Language:',
                        style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        state.detectedLanguage.isEmpty ? 'Detecting...' : state.detectedLanguage,
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),

                      Text(
                        'Corrected Text:',
                        style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        state.correctedText.isEmpty ? 'Correcting...' : state.correctedText,
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),

                      Text(
                        'Translated Text (English):',
                        style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        state.translatedText.isEmpty ? 'Translating...' : state.translatedText,
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          ElevatedButton.icon(
                            onPressed: state.recognizedText.isNotEmpty && !state.isSpeaking
                                ? state.speakRecognizedText
                                : null,
                            icon: Icon(Icons.volume_up, color: colorScheme.onPrimary),
                            label: Text('Speak Original', style: textTheme.labelLarge?.copyWith(color: colorScheme.onPrimary)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: state.translatedText.isNotEmpty && !state.isSpeaking
                                ? state.speakTranslatedText
                                : null,
                            icon: Icon(Icons.g_translate_rounded, color: colorScheme.onSecondary),
                            label: Text('Speak Translated', style: textTheme.labelLarge?.copyWith(color: colorScheme.onSecondary)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.secondary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                          if (state.isSpeaking)
                            ElevatedButton.icon(
                              onPressed: state.stopSpeaking,
                              icon: Icon(Icons.stop, color: colorScheme.onError),
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
        );
      },
    );
  }
}
