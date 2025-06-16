// lib/features/home/home_page.dart
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'dart:async'; // Import for Timer

import '../../core/routing/app_router.dart';
import '../../state/app_state.dart';
import '../../core/services/network_service.dart';
import '../../features/aniwa_chat/state/chat_state.dart';
import '../../main.dart'; // Import main.dart to access ThemeProvider

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, RouteAware {
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late AnimationController _cardAnimationController;
  late AnimationController _heroAnimationController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _cardStaggerAnimation;
  late Animation<double> _heroScaleAnimation;
  late Animation<double> _heroOpacityAnimation;

  // For animated quick tips
  int _currentTipIndex = 0;
  Timer? _tipTimer;
  late AnimationController _tipTextAnimationController;
  late Animation<double> _tipTextAnimation;

  // For sequential quick actions icon animation
  late AnimationController _quickActionsIconController;

  final List<String> _tips = [
    'Try saying "Hey Assistant" to wake me up, then ask me anything! I can help with reading text, identifying objects, navigation, and much more.',
    'You can switch between voice and text input modes using the toggle in the system status section.',
    'Explore the quick actions grid to directly jump into features like Text Reader or Emergency SOS.',
    'Remember to check your network status for full online capabilities. I also work offline for basic tasks!',
    'Your chat history is saved automatically. You can review past conversations at any time.',
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 21),
      vsync: this,
    )..repeat();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _heroAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.8),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.elasticOut),
    );

    _cardStaggerAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _cardAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _heroScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _heroAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    _heroOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _heroAnimationController, curve: Curves.easeIn),
    );

    // Initialize and start tip animation
    _tipTextAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500), // Fade duration
      vsync: this,
    );
    _tipTextAnimation = CurvedAnimation(
      parent: _tipTextAnimationController,
      curve: Curves.easeIn,
    );

    _startTipCycling();

    // Define properties for sequential icon animation
    const int iconAnimationDurationMs =
        400; // Duration for each icon's animation
    const int iconAnimationDelayMs =
        100; // Delay between starting each icon's animation
    // Calculate total duration for all 8 cards to animate sequentially
    final int totalIconAnimationTimeMs =
        (8 * iconAnimationDurationMs) +
        (7 * iconAnimationDelayMs); // 8 cards, 7 delays

    _quickActionsIconController = AnimationController(
      duration: Duration(milliseconds: totalIconAnimationTimeMs),
      vsync: this,
    );

    // Start other animations with staggered delays
    _heroAnimationController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _slideController.forward();
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      _cardAnimationController.forward();
      // Start quick actions icon animation after cards start appearing
      _quickActionsIconController
          .repeat(); // This ensures the animation loops indefinitely
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route events for lifecycle management
    // Only subscribe if the route is valid (not null)
    final ModalRoute<dynamic>? currentRoute = ModalRoute.of(context);
    if (currentRoute != null && currentRoute is PageRoute) {
      routeObserver.subscribe(this, currentRoute);
    } else {
      Logger().w(
        "HomePage: ModalRoute is null or not a PageRoute, skipping RouteAware subscription.",
      );
    }
  }

  void _startTipCycling() {
    _tipTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      // Change tip every 8 seconds
      setState(() {
        _tipTextAnimationController.reset(); // Reset animation
        _currentTipIndex = (_currentTipIndex + 1) % _tips.length;
        _tipTextAnimationController.forward(); // Start new animation
      });
    });
    _tipTextAnimationController.forward(); // Start initial fade-in
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _slideController.dispose();
    _cardAnimationController.dispose();
    _heroAnimationController.dispose();
    _tipTextAnimationController.dispose(); // Dispose tip animation controller
    _quickActionsIconController.dispose(); // Dispose icon animation controller
    _tipTimer?.cancel(); // Cancel tip timer
    routeObserver.unsubscribe(this); // Unsubscribe from route events
    super.dispose();
  }

  // --- RouteAware methods for lifecycle management ---
  @override
  void didPush() {
    // This page has been pushed onto the stack and is now fully visible.
    Logger().i('HomePage: didPush - Resuming chat state.');
    // Resume chat state, which will enable wake word if in voice mode
    Provider.of<ChatState>(context, listen: false).resume();
  }

  @override
  void didPopNext() {
    // This page is re-emerging as the top-most route after another route was popped.
    Logger().i('HomePage: didPopNext - Resuming chat state.');
    // Resume chat state, which will enable wake word if in voice mode
    Provider.of<ChatState>(context, listen: false).resume();
  }

  @override
  void didPop() {
    // This page has been popped off the stack and is no longer visible.
    Logger().i('HomePage: didPop - Pausing chat state.');
    // Pause chat state to stop microphone use when not on this screen
    Provider.of<ChatState>(context, listen: false).pause();
  }

  @override
  void didPushNext() {
    // Another page has been pushed on top of this one, making this page inactive.
    Logger().i('HomePage: didPushNext - Pausing chat state.');
    // Pause chat state to stop microphone use when not on this screen
    Provider.of<ChatState>(context, listen: false).pause();
  }
  // --- End RouteAware methods ---

  void _toggleListening(ChatState chatState) {
    if (chatState.isListening) {
      chatState.stopVoiceInput();
    } else {
      chatState.startVoiceInput();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = Provider.of<ChatState>(context);
    final appState = Provider.of<AppState>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final networkService = Provider.of<NetworkService>(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildModernAppBar(
            context,
            appState,
            chatState,
            colorScheme,
            networkService,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildWelcomeCard(appState, colorScheme),
                const SizedBox(height: 32),
                _buildQuickActionsGrid(context, chatState, colorScheme),
                const SizedBox(height: 32),
                _buildStatusSection(
                  context,
                  chatState,
                  networkService,
                  colorScheme,
                ),
                const SizedBox(height: 32),
                _buildInsightsCard(colorScheme),
              ]),
            ),
          ),
        ],
      ),
      // FAB remains for direct voice input on home screen
      floatingActionButton: _buildSmartFAB(chatState, colorScheme),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerFloat, // Changed from centerDocked
      // bottomNavigationBar is removed as requested
    );
  }

  Widget _buildModernAppBar(
    BuildContext context,
    AppState appState,
    ChatState chatState,
    ColorScheme colorScheme,
    NetworkService networkService,
  ) {
    // Access the current theme mode to determine the icon for the theme toggler
    final themeMode = ThemeProvider.of(context).themeMode;
    final isDarkMode =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);
    final themeIcon =
        isDarkMode
            ? Icons.light_mode
            : Icons
                .dark_mode; // Show light mode icon if dark, dark mode icon if light

    return SliverAppBar(
      expandedHeight: 280,
      floating: false,
      pinned: true,
      stretch: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
        ],
        background: Container(
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
          ),
          child: Stack(
            children: [
              // Animated background particles - now with random movement
              // The `index` is passed to the _buildFloatingParticle function,
              // where a local Random instance is created with this index as a seed.
              // This ensures each particle has unique, but consistent, random-like properties.
              ...List.generate(
                20,
                (index) => _buildFloatingParticle(index, colorScheme),
              ),
              // Main content
              Positioned(
                left: 24,
                right: 24,
                bottom: 40,
                child: FadeTransition(
                  opacity: _heroOpacityAnimation,
                  child: ScaleTransition(
                    scale: _heroScaleAnimation,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getGreeting(),
                          style: GoogleFonts.inter(
                            fontSize: 28,
                            fontWeight: FontWeight.w300,
                            color: Colors.white.withAlpha(200),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          appState.userName.isNotEmpty
                              ? appState.userName
                              : 'Ready to assist',
                          style: GoogleFonts.inter(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(50),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withAlpha(80),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color:
                                      networkService.isOnline
                                          ? Colors.green
                                          : Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                networkService.isOnline
                                    ? 'Online & Ready'
                                    : 'Offline Mode',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        SlideTransition(
          position: _slideAnimation,
          child: _buildProfileButton(context, appState, colorScheme),
        ),
        const SizedBox(width: 16),
        // Theme Toggler Button
        SlideTransition(
          position: _slideAnimation,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(50),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withAlpha(80), width: 2),
            ),
            child: ScaleTransition(
              scale: _pulseAnimation,
              child: IconButton(
                icon: Icon(
                  themeIcon, // Dynamically set icon based on theme mode
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () {
                  ThemeProvider.of(
                    context,
                  ).toggleTheme(); // Call the theme toggler
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildFloatingParticle(int index, ColorScheme colorScheme) {
    // Create a reproducible random generator for this specific particle
    // The seed `index` ensures that each particle has consistent "random" properties
    // across rebuilds of the CustomScrollView, but is different from other particles.
    final math.Random localRandom = math.Random(index);

    // Generate unique parameters for this particle's initial position and movement
    // These will be constant for the lifetime of this specific particle widget
    final double initialSpawnX =
        localRandom.nextDouble() * MediaQuery.of(context).size.width;
    final double initialSpawnY =
        localRandom.nextDouble() *
        280; // Height of FlexibleSpaceBar (280 pixels)

    // Larger amplitudes for more noticeable wandering movement
    final double xMoveAmplitude =
        20 + localRandom.nextDouble() * 50; // 20 to 70
    final double yMoveAmplitude =
        20 + localRandom.nextDouble() * 50; // 20 to 70

    // Varying speeds and phase offsets for distinct movements
    final double speedFactor =
        0.5 + localRandom.nextDouble() * 1.5; // 0.5 to 2.0
    final double phaseOffset =
        localRandom.nextDouble() * math.pi * 2; // 0 to 2*PI

    // Fixed opacity and size for each particle, but randomly determined once
    final double particleOpacity =
        0.3 + localRandom.nextDouble() * 0.4; // 0.3 to 0.7
    final double particleSize = 4 + localRandom.nextDouble() * 8; // 4 to 12

    return Positioned(
      left:
          initialSpawnX, // Start from a random X position within the app bar's width
      top:
          initialSpawnY, // Start from a random Y position within the app bar's height
      child: AnimatedBuilder(
        animation:
            _pulseController, // Use _pulseController for continuous animation (0.0 to 1.0 repeating)
        builder: (context, child) {
          final double animationValue = _pulseController.value;

          // Calculate time-varying offset for this particle
          // The particle's current position is its initial spawn point plus an oscillating offset
          final double currentTranslateX =
              math.sin(
                animationValue * speedFactor * 2 * math.pi + phaseOffset,
              ) *
              xMoveAmplitude;
          final double currentTranslateY =
              math.cos(
                animationValue * speedFactor * 2 * math.pi + phaseOffset,
              ) *
              yMoveAmplitude;

          return Transform.translate(
            offset: Offset(currentTranslateX, currentTranslateY),
            child: Opacity(
              opacity: particleOpacity,
              child: Container(
                width: particleSize,
                height: particleSize,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(100),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileButton(
    BuildContext context,
    AppState appState,
    ColorScheme colorScheme,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(50),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withAlpha(80), width: 2),
      ),
      child: ScaleTransition(
        scale: _pulseAnimation,
        child: IconButton(
          onPressed: () => Navigator.pushNamed(context, AppRouter.profile),
          icon: CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white,
            child: Text(
              appState.userName.isNotEmpty
                  ? appState.userName[0].toUpperCase()
                  : 'U',
              style: GoogleFonts.inter(
                color: colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(AppState appState, ColorScheme colorScheme) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primaryContainer,
              colorScheme.secondaryContainer,
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withAlpha(50),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your AI Assistant',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the voice button to start a conversation, or explore the features below.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: colorScheme.onPrimaryContainer.withAlpha(180),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome,
                color: colorScheme.onPrimaryContainer,
                size: 32,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsGrid(
    BuildContext context,
    ChatState chatState,
    ColorScheme colorScheme,
  ) {
    final actions = [
      // Changed 'Voice Chat' to navigate to AniwaChat page
      {
        'title': 'Voice Chat',
        'icon': Icons.mic,
        'color': Colors.blue,
        'action': () => Navigator.pushNamed(context, AppRouter.aniwaChat),
      },
      {
        'title': 'Text Reader',
        'icon': Icons.chrome_reader_mode,
        'color': Colors.green,
        'action': () => Navigator.pushNamed(context, AppRouter.textReader),
      },
      {
        'title': 'Emergency SOS',
        'icon': Icons.sos,
        'color': Colors.red,
        'action': () => Navigator.pushNamed(context, AppRouter.emergency),
      },
      {
        'title': 'Object Detection',
        'icon': Icons.camera_alt,
        'color': Colors.orange,
        'action':
            () => Navigator.pushNamed(
              context,
              AppRouter.objectDetector,
              arguments: {'autoStartLive': true},
            ),
      },
      {
        'title': 'Face Recognition',
        'icon': Icons.face,
        'color': Colors.purple,
        'action':
            () => Navigator.pushNamed(
              context,
              AppRouter.facialRecognition,
              arguments: {'autoStartLive': true},
            ),
      },
      {
        'title': 'Navigation',
        'icon': Icons.map,
        'color': Colors.teal,
        'action': () => Navigator.pushNamed(context, AppRouter.navigation),
      },
      {
        'title': 'Chat History',
        'icon': Icons.history,
        'color': Colors.indigo,
        'action': () => Navigator.pushNamed(context, AppRouter.history),
      },
      {
        'title': 'Explore More',
        'icon': Icons.explore,
        'color': Colors.amber,
        'action': () => Navigator.pushNamed(context, AppRouter.exploreFeatures),
      },
    ];

    const int iconAnimationDurationMs =
        400; // Duration for each icon's scale-up/down
    const int iconAnimationDelayMs =
        100; // Delay before starting next icon's animation

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 20),
        AnimatedBuilder(
          animation: _cardStaggerAnimation,
          builder: (context, child) {
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
              ),
              itemCount: actions.length,
              itemBuilder: (context, index) {
                final delay = index * 0.1;
                final animationValue = Curves.easeOutCubic.transform(
                  math.max(0, math.min(1, _cardStaggerAnimation.value - delay)),
                );

                // Calculate the start and end of the interval for the current icon's animation within the controller's full duration
                final double intervalStart =
                    index *
                    (iconAnimationDurationMs + iconAnimationDelayMs) /
                    _quickActionsIconController.duration!.inMilliseconds;
                final double intervalEnd =
                    (index * (iconAnimationDurationMs + iconAnimationDelayMs) +
                        iconAnimationDurationMs) /
                    _quickActionsIconController.duration!.inMilliseconds;

                // Ensure intervals are clamped between 0.0 and 1.0
                final double clampedIntervalStart = math.max(
                  0.0,
                  math.min(1.0, intervalStart),
                );
                final double clampedIntervalEnd = math.max(
                  0.0,
                  math.min(1.0, intervalEnd),
                );

                // This CurvedAnimation defines the time slice when this specific icon animates
                final Animation<double> iconAnimationProgress = CurvedAnimation(
                  parent: _quickActionsIconController,
                  curve: Interval(
                    clampedIntervalStart,
                    clampedIntervalEnd,
                    curve: Curves.linear,
                  ), // Use linear for precise control by TweenSequence
                );

                return Transform.translate(
                  offset: Offset(0, 50 * (1 - animationValue)),
                  child: Opacity(
                    opacity: animationValue,
                    child: _buildActionCard(
                      context,
                      actions[index]['title'] as String,
                      actions[index]['icon'] as IconData,
                      actions[index]['color'] as Color,
                      actions[index]['action'] as VoidCallback,
                      colorScheme,
                      iconAnimationProgress, // Pass the new icon animation progress
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    IconData icon,
    Color accentColor,
    VoidCallback onTap,
    ColorScheme colorScheme,
    Animation<double>
    iconAnimationProgress, // Represents the progress of the icon's allocated time
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accentColor.withAlpha(80), width: 1),
            boxShadow: [
              BoxShadow(
                color: accentColor.withAlpha(30),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor.withAlpha(40),
                      accentColor.withAlpha(20),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: AnimatedBuilder(
                  animation:
                      iconAnimationProgress, // Drive the animation with this specific progress
                  builder: (context, child) {
                    return ScaleTransition(
                      // Define the pulse animation within the icon's interval
                      scale: TweenSequence<double>([
                        TweenSequenceItem(
                          tween: Tween(
                            begin: 0.8,
                            end: 1.1,
                          ).chain(CurveTween(curve: Curves.easeOutCubic)),
                          weight: 0.5,
                        ), // Scale up
                        TweenSequenceItem(
                          tween: Tween(
                            begin: 1.1,
                            end: 0.8,
                          ).chain(CurveTween(curve: Curves.easeInCubic)),
                          weight: 0.5,
                        ), // Scale down
                      ]).animate(iconAnimationProgress),
                      child: Icon(icon, size: 32, color: accentColor),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSection(
    BuildContext context,
    ChatState chatState,
    NetworkService networkService,
    ColorScheme colorScheme,
  ) {
    return SlideTransition(
      position: _slideAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Status',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withAlpha(20),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildInputModeToggle(chatState, colorScheme),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatusIndicator(
                        'Connection',
                        networkService.isOnline ? 'Online' : 'Offline',
                        networkService.isOnline ? Icons.wifi : Icons.wifi_off,
                        networkService.isOnline ? Colors.green : Colors.orange,
                        colorScheme,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatusIndicator(
                        'Voice',
                        // Display 'Listening' if ChatState is actively listening
                        // Display 'Wake Word' if ChatState is wake word listening
                        // Otherwise, 'Ready'
                        chatState.isListening
                            ? 'Listening'
                            : chatState.isWakeWordListening
                            ? 'Wake Word'
                            : 'Ready',
                        chatState.isListening
                            ? Icons.mic
                            : chatState.isWakeWordListening
                            ? Icons
                                .volume_up // Represents active listening for wake word
                            : Icons.mic_none,
                        chatState.isListening
                            ? Colors.red
                            : chatState.isWakeWordListening
                            ? Colors
                                .purple // Distinct color for wake word
                            : Colors.blue,
                        colorScheme,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputModeToggle(ChatState chatState, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => chatState.setInputMode(InputMode.voice),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color:
                      chatState.currentInputMode == InputMode.voice
                          ? colorScheme.primary
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.mic,
                      color:
                          chatState.currentInputMode == InputMode.voice
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Voice',
                      style: GoogleFonts.inter(
                        color:
                            chatState.currentInputMode == InputMode.voice
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => chatState.setInputMode(InputMode.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color:
                      chatState.currentInputMode == InputMode.text
                          ? colorScheme.primary
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.keyboard,
                      color:
                          chatState.currentInputMode == InputMode.text
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Text',
                      style: GoogleFonts.inter(
                        color:
                            chatState.currentInputMode == InputMode.text
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildStatusIndicator(
    String label,
    String status,
    IconData icon,
    Color color,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: colorScheme.onSurface.withAlpha(180),
            ),
          ),
          Text(
            status,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsCard(ColorScheme colorScheme) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.tertiaryContainer,
              colorScheme.tertiary.withAlpha(150),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primaryContainer.withAlpha(12),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: colorScheme.tertiary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Quick Tip',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // AnimatedSwitcher for cycling through tips
            AnimatedSwitcher(
              duration: _tipTextAnimationController.duration!,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: Text(
                _tips[_currentTipIndex],
                key: ValueKey<int>(
                  _currentTipIndex,
                ), // Key is crucial for AnimatedSwitcher
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: colorScheme.onTertiaryContainer.withAlpha(200),
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartFAB(ChatState chatState, ColorScheme colorScheme) {
    return ScaleTransition(
      scale:
          chatState.isListening
              ? _pulseAnimation
              : const AlwaysStoppedAnimation(1.0),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              chatState.isListening ? Colors.red : colorScheme.primary,
              chatState.isListening ? Colors.redAccent : colorScheme.secondary,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: (chatState.isListening ? Colors.red : colorScheme.primary)
                  .withAlpha(100),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton.large(
          onPressed: () => _toggleListening(chatState),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Icon(
            chatState.isListening ? Icons.mic_off : Icons.mic,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
