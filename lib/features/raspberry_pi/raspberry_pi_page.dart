// lib/features/raspberry_pi/raspberry_pi_connect_page.dart
import 'package:assist_lens/core/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/services/raspberry_pi_service.dart';
import '../aniwa_chat/state/chat_state.dart';
import '../../main.dart';

class RaspberryPiConnectPage extends StatefulWidget {
  const RaspberryPiConnectPage({super.key});

  @override
  State<RaspberryPiConnectPage> createState() => _RaspberryPiConnectPageState();
}

class _RaspberryPiConnectPageState extends State<RaspberryPiConnectPage> with TickerProviderStateMixin, RouteAware {
  final TextEditingController _ipController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  late ChatState _chatState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatState = Provider.of<ChatState>(context, listen: false);
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _pulseController.dispose();
    _fadeController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  void didPush() {
    _chatState.updateCurrentRoute(AppRouter.raspberryPiConnect);
    _chatState.setChatPageActive(true);
    _chatState.resume();
  }

  @override
  void didPopNext() {
    _chatState.updateCurrentRoute(AppRouter.raspberryPiConnect);
    _chatState.setChatPageActive(true);
    _chatState.resume();
  }

  @override
  void didPushNext() {
    _chatState.setChatPageActive(false);
    _chatState.pause();
  }

  @override
  void didPop() {
    _chatState.setChatPageActive(false);
    _chatState.pause();
  }

  @override
  void initState() {
    super.initState();
    
    // Animation controllers
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    
    _fadeController.forward();
  }

  // @override
  // void dispose() {
  //   _pulseController.dispose();
  //   _fadeController.dispose();
  //   _ipController.dispose();
  //   super.dispose();
  // }

  Future<void> _connectToPi() async {
    if (_formKey.currentState!.validate()) {
      final ipAddress = _ipController.text.trim();
      final service = Provider.of<RaspberryPiService>(context, listen: false);

      await service.connect(ipAddress);

      void statusListener() {
        if (!mounted) return;

        if (service.connectionStatus == RaspberryPiConnectionStatus.connected) {
          service.removeListener(statusListener);
          Navigator.of(context).pushReplacementNamed(AppRouter.raspberryPiView);
        } else if (service.connectionStatus == RaspberryPiConnectionStatus.error) {
          service.removeListener(statusListener);
          _showErrorSnackBar(ipAddress);
        }
      }

      service.addListener(statusListener);
    }
  }

  void _showErrorSnackBar(String ipAddress) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Failed to connect to Glasses at $ipAddress'),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final piService = Provider.of<RaspberryPiService>(context);
    final isConnecting = piService.connectionStatus == RaspberryPiConnectionStatus.connecting;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withOpacity(0.1),
              colorScheme.secondary.withOpacity(0.05),
              colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // App Title
                      Text(
                        'AssistLens',
                        style: GoogleFonts.orbitron(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Smart Glasses Control',
                        style: textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 48),

                      // Animated Icon Container
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    colorScheme.primary,
                                    colorScheme.secondary,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.primary.withOpacity(0.3),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.smart_display_rounded,
                                size: 60,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 40),

                      // Connection Card
                      Card(
                        elevation: 8,
                        shadowColor: colorScheme.shadow.withOpacity(0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Connect to Your Glasses',
                                textAlign: TextAlign.center,
                                style: textTheme.headlineSmall?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 24),

                              // IP Input Field
                              TextFormField(
                                controller: _ipController,
                                enabled: !isConnecting,
                                decoration: InputDecoration(
                                  labelText: 'Raspberry Pi IP Address',
                                  hintText: '192.168.1.100',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest,
                                  prefixIcon: Container(
                                    margin: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.router_rounded,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  suffixIcon: _ipController.text.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(
                                            Icons.clear,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          onPressed: () {
                                            _ipController.clear();
                                            setState(() {});
                                          },
                                        )
                                      : null,
                                ),
                                keyboardType: TextInputType.numberWithOptions(decimal: true),
                                style: textTheme.bodyLarge,
                                onChanged: (value) => setState(() {}),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter an IP address';
                                  }
                                  final ipPattern = RegExp(r"^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$");
                                  if (!ipPattern.hasMatch(value)) {
                                    return 'Enter a valid IP address format';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 32),

                              // Connect Button
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: isConnecting ? null : _connectToPi,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                    disabledBackgroundColor: colorScheme.surfaceContainerHighest,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: isConnecting ? 0 : 4,
                                  ),
                                  child: isConnecting
                                      ? Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  colorScheme.primary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Text(
                                              'Connecting...',
                                              style: textTheme.labelLarge?.copyWith(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.link_rounded,
                                              size: 24,
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              'Connect to Glasses',
                                              style: textTheme.labelLarge?.copyWith(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Help Text
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.outline.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Make sure your device and Raspberry Pi are on the same network',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
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
          ),
        ),
      ),
    );
  }
}