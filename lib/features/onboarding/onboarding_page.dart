// lib/features/onboarding/onboarding_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../state/app_state.dart';

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
    await context.read<AppState>().completeOnboarding();
    // 2. Navigate to Home, replacing this screen
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
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
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            slides[i]['title']!,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            slides[i]['description']!,
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
                                      _currentIndex == idx
                                          ? Colors.blueAccent
                                          : Colors.grey.shade300,
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
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _currentIndex == slides.length - 1
                                    ? 'Get Started'
                                    : 'Next',
                                style: const TextStyle(fontSize: 16),
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
