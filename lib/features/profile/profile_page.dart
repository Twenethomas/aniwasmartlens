// lib/features/profile/profile_page.dart
import 'package:assist_lens/core/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../state/app_state.dart';
import '../aniwa_chat/state/chat_state.dart';
import '../../main.dart'; // For ThemeProvider

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState(); 
}

class _ProfilePageState extends State<ProfilePage> with RouteAware {
  final TextEditingController _nameController = TextEditingController();
  late ChatState _chatState;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.userImagePath = image.path;
    }
  }

  Widget _buildProfileImage(AppState appState, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _pickImage,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: colorScheme.primary.withOpacity(0.2),
            backgroundImage: appState.userImagePath != null
                ? FileImage(File(appState.userImagePath!))
                : null,
            child: appState.userImagePath == null
                ? Icon(
                    Icons.person_rounded,
                    size: 60,
                    color: colorScheme.primary,
                  )
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.camera_alt,
                size: 20,
                color: colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatState = Provider.of<ChatState>(context, listen: false);
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    _chatState.updateCurrentRoute(AppRouter.profile);
    _chatState.setChatPageActive(true);
    _chatState.resume();
  }

  @override
  void didPopNext() {
    _chatState.updateCurrentRoute(AppRouter.profile);
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
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appState = context.watch<AppState>();

    return Scaffold(
      // Wrap with Scaffold
      appBar: AppBar(
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
        automaticallyImplyLeading:
            true, // Add back button if part of navigation stack
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildProfileImage(appState, colorScheme),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => _showEditNameDialog(context, appState),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    appState.userName,
                    style: textTheme.headlineMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.edit_rounded,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'User since: ${DateTime.now().year}', // Placeholder
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
                // Navigate to the settings page
                Navigator.pushNamed(context, AppRouter.settings);
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(Icons.info_rounded, color: colorScheme.onSurface),
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
                  applicationVersion: '1.0.0', // Consider making this dynamic
                  applicationLegalese:
                      '© ${DateTime.now().year} Assist Lens. All rights reserved.',
                  children: [
                    Text(
                      'Assist Lens is your personal AI companion designed to enhance independence for visually impaired users.',
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
                value:
                    ThemeProvider.of(context).themeMode == ThemeMode.dark ||
                    (ThemeProvider.of(context).themeMode == ThemeMode.system &&
                        MediaQuery.of(context).platformBrightness ==
                            Brightness.dark),
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
    );
  }

  Future<void> _showEditNameDialog(
    BuildContext context,
    AppState appState,
  ) async {
    _nameController.text = appState.userName;
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Edit Your Name'),
          content: TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: "Enter your name"),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                if (_nameController.text.trim().isNotEmpty) {
                  appState.userName = _nameController.text.trim();
                  Navigator.of(dialogContext).pop();
                } else {
                  // Optionally show an error if the name is empty
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name cannot be empty.')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }
}
