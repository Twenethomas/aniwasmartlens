// lib/features/onboarding/onboarding_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/app_state.dart';
import '../../core/routing/app_router.dart'; // Import AppRouter

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  _OnboardingPageState createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

  final List<Map<String, String>> slides = [
    {
      "image": "assets/images/onboarding/slide1.png",
      "title": "Welcome to AssistLens",
      "description": "A smart assistant designed for visually impaired users.",
    },
    {
      "image": "assets/images/onboarding/slide2.png",
      "title": "Real-Time Guidance",
      "description":
          "Reads text, identifies faces, and describes surroundings.",
    },
    {
      "image": "assets/images/onboarding/slide3.png",
      "title": "Emergency Features",
      "description": "Call your caregiver instantly with a double tap.",
    },
  ];

  Future<void> _finishOnboarding() async {
    // 1. Mark onboarding complete
    await context.read<AppState>().onboardingComplete;
    // 2. Navigate to Home, replacing this screen
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
          // Full-screen PageView
          PageView.builder(
            controller: _controller,
            itemCount: slides.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) {
              return Column(
                children: [
                  Expanded(
                    flex: 7,
                    child: Image.asset(
                      slides[i]['image']!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colorScheme.surface, // Use themed surface color
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            slides[i]['title']!,
                            style: textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            slides[i]['description']!,
                            style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface.withOpacity(0.8)),
                            textAlign: TextAlign.center,
                          ),
                          const Spacer(),
                          // Pager indicators
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(slides.length, (idx) {
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                width: _currentIndex == idx ? 20 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color:
                                      _currentIndex == idx // Themed indicator colors
                                          ? colorScheme.primary
                                          : colorScheme.onSurface.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 16),
                          // Next / Get Started button
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed:
                                  _currentIndex == slides.length - 1
                                      ? _finishOnboarding
                                      : () => _controller.nextPage(
                                        duration: const Duration(
                                          milliseconds: 300,
                                        ),
                                        curve: Curves.easeInOut,
                                      ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary, // Themed button color
                                foregroundColor: colorScheme.onPrimary, // Themed text color on button
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _currentIndex == slides.length - 1
                                    ? 'Get Started' // Themed button text
                                    : 'Next', // Themed button text
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
        ],
      ),
    );
  }
}
