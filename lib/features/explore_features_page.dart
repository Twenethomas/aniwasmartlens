// lib/features/explore_features_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/routing/app_router.dart';

class ExploreFeaturesPage extends StatelessWidget {
  const ExploreFeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface, // Match background
        elevation: 0,
        title: Text(
          'Explore Features',
          style: GoogleFonts.sourceCodePro(
            color: colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton(
              onPressed: () {
                // Handle upgrade action
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Upgrade functionality coming soon!')),
                );
              },
              style: TextButton.styleFrom(
                backgroundColor: colorScheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Upgrade',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Try Premium Section
            Text(
              'Try Premium',
              style: textTheme.headlineSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: const EdgeInsets.only(bottom: 24.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              color:
                  colorScheme
                      .surfaceContainerHighest, // A slightly darker surface for premium card
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 40,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Try Premium',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Unlock advanced features and priority support',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Upgrade button pressed!')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        'Upgrade',
                        style: textTheme.labelLarge?.copyWith(
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Explore Features Section
            Text(
              'Explore Features',
              style: textTheme.headlineSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            _buildFeatureCard(
              context: context,
              title: 'Aniwa Chat',
              description:
                  'Your AI companion for conversations and assistance.',
              icon: Icons.chat_bubble_rounded,
              color: colorScheme.secondary,
              onTap: () {
                Navigator.pushNamed(context, AppRouter.aniwaChat);
              },
            ),
            _buildFeatureCard(
              context: context,
              title: 'Navigation Assistance',
              description: 'Get turn-by-turn directions.',
              icon: Icons.navigation_rounded, // Changed to a navigation icon
              color: colorScheme.primary.withOpacity(0.7),
              onTap: () {
                Navigator.pushNamed(context, AppRouter.navigation);
              },
            ),
            _buildFeatureCard(
              context: context,
              title: 'Emergency Help',
              description: 'Get immediate assistance.',
              icon: Icons.medical_services_rounded, // Changed to a medical icon
              color: colorScheme.error,
              onTap: () {
                Navigator.pushNamed(context, AppRouter.emergency);
              },
            ),
            _buildFeatureCard(
              context: context,
              title: 'Object Detection',
              description: 'Identify objects around you.',
              icon: Icons.search_rounded,
              color: colorScheme.tertiary,
              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppRouter.objectDetector,
                  arguments: {'autoStartLive': true},
                );
              },
            ),
            _buildFeatureCard(
              context: context,
              title: 'Facial Recognition',
              description:
                  'Identify familiar faces and get real-time feedback.',
              icon: Icons.face_rounded,
              color: colorScheme.primary.withOpacity(
                0.5,
              ), // A different shade of primary
              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppRouter.facialRecognition,
                  arguments: {'autoStartLive': true},
                );
              },
            ),
            _buildFeatureCard(
              context: context,
              title: 'Text Reader',
              description: 'Scan and listen to text from documents or signs.',
              icon: Icons.text_snippet_rounded,
              color: colorScheme.secondary.withOpacity(0.5),
              onTap: () {
                Navigator.pushNamed(context, AppRouter.textReader);
              },
            ),
            _buildFeatureCard(
              context: context,
              title: 'Scene Description',
              description: 'Get AI-powered descriptions of your surroundings.',
              icon: Icons.image_search_rounded,
              color: colorScheme.tertiary.withOpacity(0.5),
              onTap: () {
                Navigator.pushNamed(context, AppRouter.sceneDescription);
              },
            ),
            _buildFeatureCard(
              context: context,
              title: 'History',
              description: 'Review your past interactions and activities.',
              icon: Icons.history_rounded,
              color: colorScheme.onSurface.withOpacity(0.2), // Light grey
              onTap: () {
                Navigator.pushNamed(context, AppRouter.history);
              },
            ),
            _buildFeatureCard(
              context: context,
              title: 'Connect to Glasses',
              description:
                  'Connect and interact with your Assistive Lens glasses.',
              icon: Icons.bluetooth_connected_rounded, // Example icon
              color: Colors.cyan, // Example color
              onTap: () {
                Navigator.pushNamed(context, AppRouter.raspberryPiConnect);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 30, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
