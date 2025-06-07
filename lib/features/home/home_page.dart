// lib/features/home/home_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../state/app_state.dart'; // Ensure this import is correct
import '../../core/services/network_service.dart'; // Import NetworkService
import '../../features/aniwa_chat/state/chat_state.dart'; // CORRECTED IMPORT: was chat_state.h.dart
import '../../main.dart'; // Import for ThemeProvider

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final networkService = context.watch<NetworkService>();
    final chatState = context.watch<ChatState>(); // Watch ChatState

    return Scaffold(
      backgroundColor: colorScheme.background, // Uses background from theme
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor:
                colorScheme
                    .surface, // AppBar background matches surface from main.dart
            elevation: 0,
            floating: true,
            pinned: false,
            snap: true,
            expandedHeight: 200, // Adjust as needed
            flexibleSpace: FlexibleSpaceBar(
              background: Padding(
                padding: const EdgeInsets.only(
                  top: 50.0,
                  left: 20,
                  right: 20,
                  bottom: 0,
                ), // Adjust padding to position elements
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor:
                              colorScheme
                                  .primary, // Solid primary blue from image
                          child: Icon(
                            Icons.person_rounded,
                            color: colorScheme.onPrimary,
                            size: 28,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.notifications_rounded,
                                color: colorScheme.onSurface,
                              ),
                              onPressed: () {
                                // Handle notifications
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.nightlight_round,
                                color: colorScheme.onSurface,
                              ), // Sun/Moon icon for theme toggle
                              onPressed: () {
                                // Access ThemeProvider to toggle theme
                                final themeProvider = ThemeProvider.of(context);
                                themeProvider.toggleTheme();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Good morning,',
                      style: textTheme.headlineSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Text(
                      '${appState.userName}!', // Correctly uses appState.userName
                      style: textTheme.headlineMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 10.0,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 16),
                // "Ask me anything" search/mic bar
                Container(
                  decoration: BoxDecoration(
                    color:
                        colorScheme
                            .surface, // Background for the search bar (lighter surface)
                    borderRadius: BorderRadius.circular(30.0),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(
                          0.1,
                        ), // Using theme's shadow color
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    readOnly: true, // Make it read-only to act as a button
                    onTap: () {
                      Navigator.pushNamed(context, AppRouter.aniwaChat);
                    },
                    decoration: InputDecoration(
                      hintText: 'Ask me anything',
                      hintStyle: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.6),
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                      suffixIcon: Icon(
                        Icons.mic_rounded,
                        color: colorScheme.primary,
                      ),
                      border: InputBorder.none, // Remove default border
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16.0,
                        horizontal: 20.0,
                      ),
                    ),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Quick Actions Section
                Text(
                  'Quick Actions',
                  style: textTheme.headlineSmall?.copyWith(
                    // Use headlineSmall as per image
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics:
                      const NeverScrollableScrollPhysics(), // Disable scrolling of grid
                  crossAxisCount: 2,
                  crossAxisSpacing: 16.0,
                  mainAxisSpacing: 16.0,
                  children: [
                    _buildQuickActionCard(
                      context: context,
                      title: 'Scheduling',
                      description: 'Set tasks and reminders',
                      icon: Icons.calendar_month_rounded,
                      color: colorScheme.secondary.withOpacity(
                        0.1,
                      ), // Light green from secondary
                      iconColor: colorScheme.secondary, // Green icon
                      onTap: () {
                        // Navigator.pushNamed(context, AppRouter.scheduling); // Placeholder
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Scheduling feature coming soon!'),
                          ),
                        );
                      },
                    ),
                    _buildQuickActionCard(
                      context: context,
                      title: 'Search by image',
                      description: 'Get AI insights from Images',
                      icon: Icons.image_search_rounded,
                      color: colorScheme.tertiary.withOpacity(
                        0.1,
                      ), // Light purple from tertiary
                      iconColor: colorScheme.tertiary, // Purple icon
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          AppRouter.sceneDescription,
                        ); // Use scene description for image search
                      },
                    ),
                    _buildQuickActionCard(
                      context: context,
                      title: 'Text Reader',
                      description: 'Extract text from images',
                      icon: Icons.text_snippet_rounded,
                      color: colorScheme.primary.withOpacity(
                        0.1,
                      ), // Light blue from primary
                      iconColor: colorScheme.primary, // Blue icon
                      onTap: () {
                        Navigator.pushNamed(context, AppRouter.textReader);
                      },
                    ),
                    _buildQuickActionCard(
                      context: context,
                      title: 'Scene Description',
                      description: 'Understand your surroundings',
                      icon: Icons.camera_alt_rounded,
                      color:
                          Colors
                              .orange
                              .shade100, // Custom light orange to match image
                      iconColor:
                          Colors
                              .orange
                              .shade800, // Custom dark orange to match image
                      onTap: () {
                        Navigator.pushNamed(
                          context,
                          AppRouter.sceneDescription,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Recent Chat Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Chat',
                      style: textTheme.headlineSmall?.copyWith(
                        // Use headlineSmall as per image
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, AppRouter.aniwaChat);
                      },
                      icon: Icon(Icons.add_rounded, color: colorScheme.primary),
                      label: Text(
                        'Start New Chat',
                        style: textTheme.labelLarge?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                chatState.conversationHistory.isEmpty
                    ? Center(
                      child: Text(
                        'No recent chats. Start a new conversation!',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                    : Container(
                      height: 150, // Fixed height for recent chat preview
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            colorScheme
                                .surface, // Matches surface from main.dart
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListView.builder(
                        itemCount:
                            chatState.conversationHistory.length > 3
                                ? 3 // Show max 3 recent messages
                                : chatState.conversationHistory.length,
                        itemBuilder: (context, index) {
                          final message =
                              chatState.conversationHistory[chatState
                                      .conversationHistory
                                      .length -
                                  1 -
                                  index]; // Get most recent first
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Text(
                              '${message['role'] == 'user' ? 'You' : 'Aniwa'}: ${message['content']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                const SizedBox(height: 80), // Space for FAB
              ]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, AppRouter.aniwaChat);
        },
        backgroundColor: colorScheme.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(50.0),
        ),
        child: Icon(Icons.add_rounded, color: colorScheme.onPrimary, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildQuickActionCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required Color
    color, // This is now the background color for the icon circle
    required Color iconColor, // This is now the main icon color
    required VoidCallback onTap,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      color:
          colorScheme
              .surface, // Card background should match the image's white/light grey
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.max,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:
                      color, // Use the passed 'color' for the background of the icon circle
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 30,
                  color: iconColor,
                ), // Use the passed 'iconColor' for the icon
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600, // Use w600 for boldness
                      color: colorScheme.onSurface, // Adjusted to use onSurface
                    ),
                    maxLines: 2, // Limit title to 2 lines
                    overflow: TextOverflow.ellipsis, // Add ellipsis if overflow
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withOpacity(
                        0.7,
                      ), // Adjusted to use onSurface
                    ),
                    maxLines: 2, // Limit description to 2 lines
                    overflow: TextOverflow.ellipsis, // Add ellipsis if overflow
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
