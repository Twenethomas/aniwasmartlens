// lib/features/settings/settings_page.dart
import 'package:assist_lens/core/services/chat_service.dart';
import 'package:assist_lens/core/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:assist_lens/features/settings/state/settings_state.dart';
import 'package:assist_lens/main.dart'; // For ThemeProvider
import 'package:assist_lens/core/routing/app_router.dart';
import 'package:assist_lens/features/aniwa_chat/state/chat_state.dart'; // For voice commands

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with RouteAware {
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
    super.dispose();
  }

  bool _isBlindModeEnabled =
      false; // Add this as a state variable in your State class

  @override
  void initState() {
    super.initState();
    // Optionally, load initial value from app state or provider
    _isBlindModeEnabled = context.read<ChatState>().isBlindModeEnabled;
  }

  // --- RouteAware Methods for Voice Command Lifecycle ---
  @override
  void didPush() {
    _chatState.updateCurrentRoute(AppRouter.settings);
    _chatState.resume();
  }

  @override
  void didPopNext() {
    _chatState.updateCurrentRoute(AppRouter.settings);
    _chatState.resume();
  }

  @override
  void didPushNext() => _chatState.pause();
  @override
  void didPop() => _chatState.pause();
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.orbitron(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Consumer<SettingsState>(
        builder: (context, settingsState, child) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildSectionHeader(context, 'Appearance'),
              _buildThemeSelector(context),
              const Divider(height: 32),

              _buildSectionHeader(context, 'Speech Output'),
              _buildSliderTile(
                context: context,
                label: 'Volume',
                value: settingsState.speechVolume,
                icon: Icons.volume_up_rounded,
                onChanged: (value) => settingsState.setSpeechVolume(value),
                min: 0.0,
                max: 1.0,
                divisions: 10,
              ),
              _buildSliderTile(
                context: context,
                label: 'Speech Rate',
                value: settingsState.speechRate,
                icon: Icons.speed_rounded,
                onChanged: (value) => settingsState.setSpeechRate(value),
                min: 0.1,
                max: 1.0,
                divisions: 9,
              ),
              _buildSliderTile(
                context: context,
                label: 'Pitch',
                value: settingsState.speechPitch,
                icon: Icons.music_note_rounded,
                onChanged: (value) => settingsState.setSpeechPitch(value),
                min: 0.5,
                max: 2.0,
                divisions: 15,
              ),
              const Divider(height: 32),
              _buildBlindModeTile(context),
              _buildSectionHeader(context, 'Data Management'),
              _buildActionTile(
                context: context,
                title: 'Clear Chat History',
                subtitle: 'Deletes all saved conversations.',
                icon: Icons.delete_sweep_rounded,
                onTap:
                    () => _showConfirmationDialog(
                      context,
                      title: 'Clear History?',
                      content: 'This will permanently delete all chat history.',
                      onConfirm: () {
                        settingsState.clearChatHistory();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Chat history cleared.'),
                          ),
                        );
                      },
                    ),
              ),
              ElevatedButton(
                child: Text('Check for Updates'),
                onPressed: () async {
                  try {
                    final updateService = UpdateService();
                    await updateService.checkAndInstallUpdate();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Checking for updates...')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Update failed: $e')),
                    );
                  }
                },
              ),
              _buildActionTile(
                context: context,
                title: 'Reset App',
                subtitle: 'Resets all settings and logs you out.',
                icon: Icons.restart_alt_rounded,
                onTap:
                    () => _showConfirmationDialog(
                      context,
                      title: 'Reset App?',
                      content:
                          'This will clear all data and return to the onboarding screen. This action cannot be undone.',
                      onConfirm: () async {
                        await settingsState.resetApp();
                        // Navigate to onboarding and remove all previous routes
                        if (context.mounted) {
                          Navigator.of(
                            context,
                            rootNavigator: true,
                          ).pushNamedAndRemoveUntil(
                            AppRouter.onboarding,
                            (route) => false,
                          );
                        }
                      },
                    ),
                isDestructive: true,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBlindModeTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      child: SwitchListTile(
        title: Text('Blind Mode'),
        subtitle: Text(
          'Enable voice-only mode and enhanced accessibility features.',
        ),
        value: _isBlindModeEnabled,
        activeColor: colorScheme.primary,
        onChanged: (value) {
          setState(() {
            _isBlindModeEnabled = value;
            // Update ChatState and ChatService
            final chatState = context.read<ChatState>();
            if (value) {
              chatState.enableBlindMode();
            } else {
              chatState.disableBlindMode();
            }
            context.read<ChatService>().updateUserInfo(isBlindMode: value);
          });
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildThemeSelector(BuildContext context) {
    final themeProvider = ThemeProvider.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.light,
              label: Text('Light'),
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode),
            ),
            ButtonSegment(
              value: ThemeMode.system,
              label: Text('System'),
              icon: Icon(Icons.settings_system_daydream),
            ),
          ],
          selected: {themeProvider.themeMode},
          onSelectionChanged: (Set<ThemeMode> newSelection) {
            themeProvider.toggleTheme();
          },
          style: SegmentedButton.styleFrom(
            backgroundColor: colorScheme.surfaceContainer,
            foregroundColor: colorScheme.onSurfaceVariant,
            selectedBackgroundColor: colorScheme.primary,
            selectedForegroundColor: colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildSliderTile({
    required BuildContext context,
    required String label,
    required double value,
    required IconData icon,
    required ValueChanged<double> onChanged,
    double min = 0.0,
    double max = 1.0,
    int? divisions,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          children: [
            Icon(icon, color: colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleMedium),
                  Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: divisions,
                    label: value.toStringAsFixed(2),
                    onChanged: onChanged,
                    activeColor: colorScheme.primary,
                    inactiveColor: colorScheme.primary.withOpacity(0.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleColor =
        isDestructive ? colorScheme.error : colorScheme.onSurface;
    final iconColor = isDestructive ? colorScheme.error : colorScheme.primary;

    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: TextStyle(color: titleColor, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: titleColor.withOpacity(0.7)),
        ),
        onTap: onTap,
      ),
    );
  }

  void _showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: Text(
                'Confirm',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onConfirm();
              },
            ),
          ],
        );
      },
    );
  }
}
