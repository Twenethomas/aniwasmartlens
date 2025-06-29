// lib/features/scene_description/scene_description_page.dart
import 'package:assist_lens/core/routing/app_router.dart';
import 'package:assist_lens/features/aniwa_chat/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:assist_lens/features/scene_description/scene_description_state.dart';
import 'package:assist_lens/core/services/camera_service.dart';
import 'package:assist_lens/main.dart';

class SceneDescriptionPage extends StatefulWidget {
  final bool autoDescribe;

  const SceneDescriptionPage({super.key, this.autoDescribe = false});

  @override
  State<SceneDescriptionPage> createState() => _SceneDescriptionPageState();
}

class _SceneDescriptionPageState extends State<SceneDescriptionPage>
    with WidgetsBindingObserver, RouteAware, TickerProviderStateMixin {
  final Logger _logger = logger;
  SceneDescriptionState? _sceneDescriptionState;
  late CameraService _cameraService;

  // Track page visibility and initialization state
  bool _isPageActive = false;
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
  ];
  String? _selectedTargetLanguage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _textInViewPulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _textInViewPulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _textInViewPulseController, curve: Curves.easeIn),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isDisposing) return;

    _cameraService = Provider.of<CameraService>(context, listen: false);
    _sceneDescriptionState = Provider.of<SceneDescriptionState>(context, listen: false);

    // Subscribe to RouteObserver
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }

    _isPageActive = true;
    _initializePageResources();
  }

  /// Initialize all page resources
  void _initializePageResources() {
    if (_isDisposing || !_isPageActive) return;
    _cameraService.initializeCamera();
    if (widget.autoDescribe && _cameraService.isCameraInitialized) {
      _sceneDescriptionState?.startAutoDescription();
    }
  }

  /// Clean up all page resources
  void _cleanupPageResources({bool keepProcessingFlags = false}) {
    if (_isDisposing) return;
    _sceneDescriptionState?.stopAutoDescription();
    _cameraService.disposeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_isDisposing) return;

    switch (state) {
      case AppLifecycleState.resumed:
        if (_isPageActive) {
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
        _cleanupPageResources(keepProcessingFlags: false);
        break;
    }
  }

  @override
  void didPopNext() {
    if (_isDisposing) return;
    _isPageActive = true;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_isDisposing && _isPageActive && mounted) {
        _initializePageResources();
      }
    });
  }

  @override
  void didPushNext() {
    _isPageActive = false;
    _cleanupPageResources(keepProcessingFlags: false);
  }

  @override
  void didPush() {
    _isPageActive = true;
    context.read<ChatState>().updateCurrentRoute(AppRouter.aniwaChat); // or the correct route
    super.didPush();
  }

  @override
  void didPop() {
    _isPageActive = false;
    _cleanupPageResources(keepProcessingFlags: false);
  }

  @override
  void deactivate() {
    _isPageActive = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _isPageActive = false;
    _textInViewPulseController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _cleanupPageResources(keepProcessingFlags: false);
    super.dispose();
  }

  // Helper method to build a text display section (Card style)
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

  // Build action buttons similar to TextReader
  Widget _buildActionButtons(SceneDescriptionState state, ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      children: [
        if (state.hasDescription && !state.isProcessing && !state.isAutoDescribing && _isPageActive)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.speakCurrentText,
                icon: Icon(
                  Icons.volume_up_rounded,
                  color: colorScheme.onPrimary,
                ),
                label: Text(
                  'Speak Description',
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
                ),
              ),
            ),
          ),
        if (state.isAutoDescribing && _isPageActive)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.speakCurrentText,
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
                ),
              ),
            ),
          ),
        if (state.hasDescription && !state.isProcessing && _isPageActive)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Wrap(
              spacing: 12.0,
              runSpacing: 12.0,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: state.sendDescriptionToChat,
                  icon: Icon(
                    Icons.send_rounded,
                    color: colorScheme.onTertiary,
                  ),
                  label: Text(
                    'Send to Chat',
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onTertiary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.tertiary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    elevation: 5,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Consumer2<SceneDescriptionState, CameraService>(
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
                      'Scene Description',
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
                _isPageActive = false;
                _cleanupPageResources(keepProcessingFlags: false);
                Navigator.pop(context);
              },
            ),
            actions: [
              IconButton(
                icon: Icon(
                  state.isAutoDescribing
                      ? Icons.auto_mode_rounded
                      : Icons.auto_mode_outlined,
                  color: state.isAutoDescribing
                      ? colorScheme.tertiary
                      : colorScheme.onPrimary,
                ),
                onPressed: _isPageActive && !_isDisposing
                    ? () => state.startAutoDescription()
                    : null,
                tooltip: state.isAutoDescribing
                    ? 'Auto Describe ON'
                    : 'Auto Describe OFF',
              ),
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
              IconButton(
                icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
                onPressed: _isPageActive &&
                        !_isDisposing &&
                        cameraService.isCameraInitialized
                    ? cameraService.toggleCamera
                    : null,
                tooltip: 'Switch Camera',
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
                ),

              // DraggableScrollableSheet for Results
              DraggableScrollableSheet(
                initialChildSize: 0.3,
                minChildSize: 0.15,
                maxChildSize: 0.9,
                expand: true,
                builder: (
                  BuildContext context,
                  ScrollController scrollController,
                ) {
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

                                // Section Title: Processing Results
                                Text(
                                  'Scene Analysis',
                                  style: textTheme.headlineSmall!.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Scene Description Card
                                if (state.sceneDescription != null)
                                  _buildTextCard(
                                    title: 'Scene Description',
                                    content: state.sceneDescription!,
                                    titleStyle: textTheme.titleMedium!.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                    contentStyle: textTheme.bodyLarge!.copyWith(
                                      color: colorScheme.onSurface.withAlpha((0.9 * 255).round()),
                                    ),
                                    icon: Icons.description_rounded,
                                    colorScheme: colorScheme,
                                  ),

                                // Translated Text Card
                                if (state.translatedText.isNotEmpty)
                                  _buildTextCard(
                                    title: 'Translated Description',
                                    content: state.translatedText,
                                    titleStyle: textTheme.titleMedium!.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                    contentStyle: textTheme.bodyLarge!.copyWith(
                                      color: colorScheme.onSurface.withAlpha((0.9 * 255).round()),
                                    ),
                                    icon: Icons.translate_rounded,
                                    colorScheme: colorScheme,
                                  ),
                                const SizedBox(height: 16),

                                // Detected Language
                                if (state.detectedLanguage.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
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
                                          state.detectedLanguage,
                                          style: textTheme.bodyMedium!.copyWith(
                                            color: colorScheme.onSurface.withAlpha((0.7 * 255).round()),
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 24),

                                // Action Buttons (Speak, Send to Chat)
                                _buildActionButtons(state, colorScheme, textTheme),

                                // Translate Actions
                                if (state.sceneDescription != null)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
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
                                                      state.sceneDescription == null ||
                                                      !_isPageActive
                                                  ? null
                                                  : () => state.translateDescription(_selectedTargetLanguage!),
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
                                const SizedBox(height: 40),
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
          floatingActionButton: _isPageActive &&
                  !_isDisposing &&
                  cameraService.isCameraInitialized &&
                  !state.isProcessing
              ? FloatingActionButton.extended(
                  onPressed: state.takePictureAndDescribeScene,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  elevation: 8,
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: Text(
                    'Describe Scene',
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