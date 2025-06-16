import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../state/app_state.dart';
import '../../core/routing/app_router.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

  final List<Map<String, String>> slides = [
    {
      "animation": "assets/animations/slide1.json",
      "title": "Welcome to AssistLens",
      "description": "A smart assistant designed for visually impaired users.",
    },
    {
      "animation": "assets/animations/slide2.json",
      "title": "Real-Time Guidance",
      "description": "Reads text, identifies faces, and describes surroundings.",
    },
    {
      "animation": "assets/animations/slide3.json",
      "title": "Emergency Features",
      "description": "Call your caregiver instantly with a double tap.",
    },
  ];

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingComplete', true);
    context.read<AppState>().onboardingComplete;
    Navigator.pushReplacementNamed(context, AppRouter.home);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colorScheme.primary, colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          PageView.builder(
            controller: _controller,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) {
              return Column(
                children: [
                  const SizedBox(height: 60),
                  Expanded(
                    flex: 6,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.4,
                        child: Lottie.asset(
                          slides[i]['animation']!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          AnimatedOpacity(
                            duration: Duration(milliseconds: 500),
                            opacity: 1,
                            child: Text(
                              slides[i]['title']!,
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedOpacity(
                            duration: Duration(milliseconds: 500),
                            opacity: 1,
                            child: Text(
                              slides[i]['description']!,
                              style: textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.75),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const Spacer(),
                          LinearProgressIndicator(
                            value: (_currentIndex + 1) / slides.length,
                            backgroundColor: colorScheme.onSurface.withOpacity(0.2),
                            color: colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _currentIndex == slides.length - 1
                                  ? _finishOnboarding
                                  : () => _controller.nextPage(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                      ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _currentIndex == slides.length - 1 ? 'Get Started' : 'Next',
                                style: textTheme.labelLarge?.copyWith(fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          Positioned(
            top: 40,
            right: 20,
            child: TextButton(
              onPressed: _finishOnboarding,
              child: const Text(
                "Skip",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}