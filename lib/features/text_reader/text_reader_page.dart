// lib/features/text_reader/text_reader_page.dart
import 'dart:io'; // Required for File
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:assist_lens/features/text_reader/text_reader_state.dart'; // Import TextReaderState
import 'package:assist_lens/core/services/camera_service.dart'; // NEW: Import CameraService to get its controller
import 'package:assist_lens/main.dart'; // For global logger and routeObserver
// import 'package:assist_lens/core/routing/app_router.dart'; // Removed unused import

class TextReaderPage extends StatefulWidget {
  const TextReaderPage({super.key});

  @override
  State<TextReaderPage> createState() => _TextReaderPageState();
}

class _TextReaderPageState extends State<TextReaderPage>
    with WidgetsBindingObserver, RouteAware, TickerProviderStateMixin {
  late TextReaderState _textReaderState; // Reference to TextReaderState
  
  // Track page visibility and initialization state
  bool _isPageActive = false;
  bool _isInitialized = false;
  bool _isDisposing = false;

  // Animation controller for the "Text in View" indicator
  late AnimationController _textInViewPulseController;
  late Animation<double> _textInViewPulseAnimation;

  // List of common languages for translation dropdown
  final List<String> _languages = [
    'English',
    'Spanish',
    'French',
    'German',
    'Chinese',
    'Japanese',
    'Korean',
    'Arabic',
    'Russian',
    'Italian',
    'Portuguese',
    'Hindi',
    'Bengali',
    'Urdu',
    'Turkish',
    'Vietnamese',
    'Thai',
    'Indonesian',
    'Malay',
    'Swahili',
    'Zulu',
    'Hausa',
    // Add more languages as needed
  ];
  String? _selectedTargetLanguage; // Default to null for initial hint

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _textInViewPulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true); // Make it pulse in and out

    _textInViewPulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _textInViewPulseController, curve: Curves.easeIn),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isDisposing) return;
    
    _textReaderState = Provider.of<TextReaderState>(context, listen: false);

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
    
    // Initialize camera with a small delay to ensure proper context
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_isDisposing && _isPageActive && mounted) {
        _textReaderState.initCamera();
      }
    });
  }

  /// Clean up all page resources
  void _cleanupPageResources({bool keepProcessingFlags = false}) {
    if (_isDisposing) return;
    
    // Stop all ongoing processes
    _textReaderState.clearResults(keepProcessingFlags: keepProcessingFlags);
    
    // Stop any ongoing speech
    if (_textReaderState.isSpeaking) {
      _textReaderState.stopSpeaking();
    }
    
    // Dispose camera resources
    _textReaderState.disposeCamera();
    
    // Clear any temporary files or cached data if needed
    // This could include clearing captured image paths, etc.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isDisposing) return;
    
    switch (state) {
      case AppLifecycleState.resumed:
        if (_isPageActive) {
          // Add a delay to allow proper resource initialization
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!_isDisposing && _isPageActive && mounted) {
              _textReaderState.initCamera();
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
    
    _isPageActive = true;
    
    // Add delay to ensure previous page resources are fully released
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_isDisposing && _isPageActive && mounted) {
        _textReaderState.initCamera();
      }
    });
  }

  @override
  void didPushNext() {
    // Called when navigating away from this page
    _isPageActive = false;
    _cleanupPageResources(keepProcessingFlags: false);
  }

  @override
  void didPush() {
    // Called when this page is pushed onto the navigation stack
    _isPageActive = true;
  }

  @override
  void didPop() {
    // Called when this page is popped from the navigation stack
    _isPageActive = false;
    _cleanupPageResources(keepProcessingFlags: false);
  }

  @override
  void deactivate() {
    // Called when the page is being deactivated
    _isPageActive = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _isPageActive = false;
    
    // Stop animation controller
    _textInViewPulseController.dispose();
    
    // Remove observers
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    
    // Final cleanup of all resources
    _cleanupPageResources(keepProcessingFlags: false);
    
    super.dispose();
  }

  // Helper method to build a text display section (Now a Card)
  Widget _buildTextCard({
    required String title,
    required String content,
    required TextStyle titleStyle,
    required TextStyle contentStyle,
    bool isLoading = false,
    IconData? icon,
    required ColorScheme colorScheme,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Icon(icon, color: colorScheme.primary, size: 20),
                  ),
                Text(title, style: titleStyle),
                const Spacer(),
                if (isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                      strokeWidth: 2,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              content,
              style: contentStyle,
              maxLines: isLoading ? 1 : 5,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer2<TextReaderState, CameraService>(
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
                      'Text Reader',
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
              // Auto-Capture Toggle
              IconButton(
                icon: Icon(
                  state.isAutoCaptureEnabled
                      ? Icons.auto_mode_rounded
                      : Icons.auto_mode_outlined,
                  color: state.isAutoCaptureEnabled
                      ? colorScheme.tertiary
                      : colorScheme.onPrimary,
                ),
                onPressed: _isPageActive && !_isDisposing
                    ? () => state.setAutoCapture(!state.isAutoCaptureEnabled)
                    : null,
                tooltip: state.isAutoCaptureEnabled
                    ? 'Auto Capture ON'
                    : 'Auto Capture OFF',
              ),
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
                    ? state.toggleFlash
                    : null,
                tooltip: 'Toggle Flash',
              ),
              // Clear All/New Scan
              IconButton(
                icon: Icon(
                  Icons.clear_all_rounded,
                  color: colorScheme.onPrimary,
                ),
                onPressed: _isPageActive && 
                          !_isDisposing && 
                          !state.isAnyProcessingActive
                    ? state.clearResults
                    : null,
                tooltip: 'Start New Scan / Clear Results',
              ),
            ],
          ),
          body: Stack(
            children: [
              // Camera Preview OR Captured Image Preview (Background)
              if (state.capturedImagePath == null)
                if (cameraService.cameraController != null &&
                    cameraService.cameraController!.value.isInitialized &&
                    _isPageActive)
                  Positioned.fill(
                    child: CameraPreview(cameraService.cameraController!),
                  )
                else
                  Center(
                    child: cameraService.cameraErrorMessage != null &&
                            cameraService.cameraErrorMessage!.isNotEmpty
                        ? Text(
                            cameraService.cameraErrorMessage!,
                            style: textTheme.headlineSmall?.copyWith(
                              color: colorScheme.error,
                            ),
                            textAlign: TextAlign.center,
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
                  )
              else
                Positioned.fill(
                  child: Image.file(
                    File(state.capturedImagePath!),
                    fit: BoxFit.cover,
                  ),
                ),

              // "Text in View" indicator (only when camera is live and page is active)
              if (state.textInView &&
                  state.capturedImagePath == null &&
                  !state.isAnyProcessingActive &&
                  _isPageActive)
                Positioned(
                  top: MediaQuery.of(context).padding.top +
                      AppBar().preferredSize.height +
                      16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ScaleTransition(
                      scale: _textInViewPulseAnimation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha((0.85 * 255).round()),
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withAlpha((0.4 * 255).round()),
                              blurRadius: 10,
                              spreadRadius: 3,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Text in View',
                              style: textTheme.labelLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // DraggableScrollableSheet for Results
              DraggableScrollableSheet(
                initialChildSize: 0.3,
                minChildSize: 0.15,
                maxChildSize: 0.9,
                expand: true,
                builder: (BuildContext context, ScrollController scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withAlpha((0.98 * 255).round()),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha((0.15 * 255).round()),
                          blurRadius: 20,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Drag Handle
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Container(
                            width: 60,
                            height: 5,
                            decoration: BoxDecoration(
                              color: colorScheme.onSurface.withAlpha((0.3 * 255).round()),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: scrollController,
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                // Error message display
                                if (state.errorMessage != null &&
                                    state.errorMessage!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                                    child: Center(
                                      child: Text(
                                        state.errorMessage!,
                                        style: textTheme.bodyMedium?.copyWith(
                                          color: colorScheme.error,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),

                                // Captured Image Preview (Thumbnail in bottom sheet)
                                if (state.capturedImagePath != null)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 16.0),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.file(
                                          File(state.capturedImagePath!),
                                          height: 150,
                                          width: 150,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),

                                // Section Title: Processing Results
                                Text(
                                  'Processing Results',
                                  style: textTheme.headlineSmall!.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Recognized Text Card
                                _buildTextCard(
                                  title: 'Raw OCR Text',
                                  content: state.recognizedText.isNotEmpty
                                      ? state.recognizedText
                                      : (state.isProcessingImage
                                          ? 'Recognizing...'
                                          : 'No text captured.'),
                                  titleStyle: textTheme.titleMedium!.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                  contentStyle: textTheme.bodyLarge!.copyWith(
                                    color: colorScheme.onSurface.withAlpha((0.9 * 255).round()),
                                  ),
                                  isLoading: state.isProcessingImage,
                                  icon: Icons.text_snippet_rounded,
                                  colorScheme: colorScheme,
                                ),

                                // Corrected Text Card (only if different or processing)
                                if (state.correctedText.isNotEmpty || state.isProcessingAI)
                                  _buildTextCard(
                                    title: 'AI Corrected Text',
                                    content: state.correctedText.isNotEmpty
                                        ? state.correctedText
                                        : (state.isProcessingAI
                                            ? 'Correcting...'
                                            : 'No AI correction yet.'),
                                    titleStyle: textTheme.titleMedium!.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                    contentStyle: textTheme.bodyLarge!.copyWith(
                                      color: colorScheme.onSurface.withAlpha((0.9 * 255).round()),
                                    ),
                                    isLoading: state.isProcessingAI,
                                    icon: Icons.auto_fix_high_rounded,
                                    colorScheme: colorScheme,
                                  ),

                                // Translated Text Card (only if different or translating)
                                if (state.translatedText.isNotEmpty || state.isTranslating)
                                  _buildTextCard(
                                    title: 'Translated Text',
                                    content: state.translatedText.isNotEmpty
                                        ? state.translatedText
                                        : (state.isTranslating
                                            ? 'Translating...'
                                            : 'Select language below.'),
                                    titleStyle: textTheme.titleMedium!.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                    contentStyle: textTheme.bodyLarge!.copyWith(
                                      color: colorScheme.onSurface.withAlpha((0.9 * 255).round()),
                                    ),
                                    isLoading: state.isTranslating,
                                    icon: Icons.translate_rounded,
                                    colorScheme: colorScheme,
                                  ),
                                const SizedBox(height: 16),

                                // Detected Language
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0,
                                    vertical: 4.0,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.language_rounded,
                                        color: colorScheme.onSurface.withAlpha((0.7 * 255).round()),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Detected Language:',
                                        style: textTheme.titleSmall!.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onSurface.withAlpha((0.8 * 255).round()),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        state.detectedLanguage.isNotEmpty
                                            ? state.detectedLanguage
                                            : (state.isProcessingAI
                                                ? 'Detecting...'
                                                : 'N/A'),
                                        style: textTheme.bodyMedium!.copyWith(
                                          color: colorScheme.onSurface.withAlpha((0.7 * 255).round()),
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Speak Current Text Button (Unified)
                                if (state.hasText &&
                                    !state.isAnyProcessingActive &&
                                    !state.isSpeaking &&
                                    _isPageActive)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 20.0),
                                      child: ElevatedButton.icon(
                                        onPressed: state.speakCurrentText,
                                        icon: Icon(
                                          Icons.volume_up_rounded,
                                          color: colorScheme.onPrimary,
                                        ),
                                        label: Text(
                                          'Speak Current Text',
                                          style: textTheme.labelLarge?.copyWith(
                                            color: colorScheme.onPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colorScheme.primary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 14,
                                          ),
                                          elevation: 5,
                                          shadowColor: colorScheme.primary.withAlpha((0.3 * 255).round()),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (state.isSpeaking && _isPageActive)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 20.0),
                                      child: ElevatedButton.icon(
                                        onPressed: state.stopSpeaking,
                                        icon: Icon(
                                          Icons.volume_off_rounded,
                                          color: colorScheme.onPrimary,
                                        ),
                                        label: Text(
                                          'Stop Speaking',
                                          style: textTheme.labelLarge?.copyWith(
                                            color: colorScheme.onPrimary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colorScheme.primary.withAlpha((0.7 * 255).round()),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 14,
                                          ),
                                          elevation: 5,
                                          shadowColor: colorScheme.primary.withAlpha((0.3 * 255).round()),
                                        ),
                                      ),
                                    ),
                                  ),

                                // Translate Actions
                                if (state.correctedText.isNotEmpty &&
                                    !state.isAnyProcessingActive &&
                                    _isPageActive)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0,
                                          vertical: 4.0,
                                        ),
                                        child: Text(
                                          'Translate to:',
                                          style: textTheme.titleSmall!.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurface.withAlpha((0.8 * 255).round()),
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: DropdownButtonFormField<String>(
                                                value: _selectedTargetLanguage,
                                                decoration: InputDecoration(
                                                  labelText: 'Select Language',
                                                  labelStyle: textTheme.bodyMedium?.copyWith(
                                                    color: colorScheme.onSurface.withAlpha((0.7 * 255).round()),
                                                  ),
                                                  border: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                    borderSide: BorderSide(
                                                      color: colorScheme.outline.withAlpha((0.5 * 255).round()),
                                                    ),
                                                  ),
                                                  focusedBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                    borderSide: BorderSide(
                                                      color: colorScheme.primary,
                                                      width: 2,
                                                    ),
                                                  ),
                                                  enabledBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                    borderSide: BorderSide(
                                                      color: colorScheme.outline.withAlpha((0.3 * 255).round()),
                                                    ),
                                                  ),
                                                  contentPadding: const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                  ),
                                                ),
                                                items: _languages.map((String lang) {
                                                  return DropdownMenuItem<String>(
                                                    value: lang,
                                                    child: Text(
                                                      lang,
                                                      style: textTheme.bodyMedium?.copyWith(
                                                        color: colorScheme.onSurface,
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                                onChanged: state.isTranslating
                                                    ? null
                                                    : (String? newValue) {
                                                        setState(() {
                                                          _selectedTargetLanguage = newValue;
                                                        });
                                                      },
                                                dropdownColor: colorScheme.surfaceContainerHigh,
                                                style: textTheme.bodyMedium?.copyWith(
                                                  color: colorScheme.onSurface,
                                                ),
                                                iconEnabledColor: colorScheme.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            ElevatedButton(
                                              onPressed: state.isTranslating ||
                                                      _selectedTargetLanguage == null ||
                                                      state.correctedText.isEmpty ||
                                                      !_isPageActive
                                                  ? null
                                                  : () => state.translateText(_selectedTargetLanguage!),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: colorScheme.primary,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 20,
                                                  vertical: 12,
                                                ),
                                                elevation: 3,
                                              ),
                                              child: state.isTranslating
                                                  ? SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(
                                                        color: colorScheme.onPrimary,
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : Icon(
                                                      Icons.translate_rounded,
                                                      color: colorScheme.onPrimary,
                                                      size: 20,
                                                    ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                const SizedBox(height: 40), // Extra space at bottom
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
          
          // Floating Action Button for Manual Capture
          floatingActionButton: _isPageActive &&
                  !_isDisposing &&
                  state.capturedImagePath == null &&
                  cameraService.isCameraInitialized &&
                  !state.isAnyProcessingActive
              ? FloatingActionButton.extended(
                  onPressed: state.takePictureAndProcessText,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  elevation: 8,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: Text(
                    'Capture',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                )
              : null,
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }
}