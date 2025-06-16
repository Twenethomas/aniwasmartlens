// lib/features/profile/profile_page.dart
import 'package:assist_lens/core/routing/app_router.dart';
import 'package:assist_lens/main.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart'; // Import AppState

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appState = context.watch<AppState>();

    return Column(
      children: [
        AppBar(
          title: Text(
            'Profile',
            style: GoogleFonts.sourceCodePro(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: colorScheme.surface,
          centerTitle: true,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: colorScheme.primary.withOpacity(0.2),
                  child: Icon(
                    Icons.person_rounded,
                    size: 60,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  appState.userName,
                  style: textTheme.headlineMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'User since: ${DateTime.now().year}', // Placeholder for user since date
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 30),
                ListTile(
                  leading: Icon(
                    Icons.settings_rounded,
                    color: colorScheme.onSurface,
                  ),
                  title: Text(
                    'Settings',
                    style: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Settings page coming soon!')),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    Icons.info_rounded,
                    color: colorScheme.onSurface,
                  ),
                  title: Text(
                    'About App',
                    style: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'Assist Lens',
                      applicationVersion: '1.0.0',
                      applicationLegalese:
                          '© 2024 Assist Lens. All rights reserved.',
                      children: [
                        Text(
                          'Assist Lens is your personal AI companion designed to enhance independence.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    Icons.brightness_6_rounded,
                    color: colorScheme.onSurface,
                  ),
                  title: Text(
                    'Toggle Theme',
                    style: textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  trailing: Switch(
                    value: Theme.of(context).brightness == Brightness.dark,
                    onChanged: (value) {
                      ThemeProvider.of(context).toggleTheme();
                    },
                    activeColor: colorScheme.primary,
                  ),
                  onTap: () {
                    ThemeProvider.of(context).toggleTheme();
                  },
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () {
                    // Implement logout or reset app state
                    appState.resetAppState(); // Resets onboarding and user name
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      AppRouter.onboarding,
                      (route) => false,
                    ); // Navigate to onboarding and remove all routes
                  },
                  icon: Icon(Icons.logout_rounded, color: colorScheme.onError),
                  label: Text(
                    'Reset App / Logout',
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onError,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
