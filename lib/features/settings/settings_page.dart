import 'package:assist_lens/core/services/update_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';

import '../../core/routing/app_router.dart';
import '../../state/app_state.dart';
import '../aniwa_chat/state/chat_state.dart';
import './state/settings_state.dart';
import '../../main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver, RouteAware {
  final Logger _logger = logger;
  bool _isBlindModeEnabled = false;
  late ChatState _chatState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatState = Provider.of<ChatState>(context, listen: false);
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);

    setState(() {
      _isBlindModeEnabled = _chatState.isBlindModeEnabled;
    });
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    _logger.d('SettingsPage: Page pushed');
    _chatState.updateCurrentRoute(AppRouter.settings);
    _chatState.setChatPageActive(true);
    _chatState.resume();
  }

  @override
  void didPopNext() {
    _logger.d('SettingsPage: Returning to page');
    _chatState.updateCurrentRoute(AppRouter.settings);
    _chatState.setChatPageActive(true);
    _chatState.resume();
  }

  @override
  void didPushNext() {
    _logger.d('SettingsPage: Page covered');
    _chatState.setChatPageActive(false);
    _chatState.pause();
  }

  @override
  void didPop() {
    _logger.d('SettingsPage: Page popped');
    _chatState.setChatPageActive(false);
    _chatState.pause();
  }

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
              _buildSectionHeader(context, 'App Settings'),
              _buildBlindModeTile(context),
              _buildGeminiSwitch(context),
              const Divider(height: 32),

              _buildSectionHeader(context, 'Appearance'),
              _buildThemeSelector(context),
              const Divider(height: 32),

              _buildSectionHeader(context, 'Speech Settings'),
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

              _buildSectionHeader(context, 'Updates & Data'),
              _buildUpdateTile(context),
              _buildActionTile(
                context: context,
                title: 'Clear Chat History',
                subtitle: 'Deletes all saved conversations',
                icon: Icons.delete_sweep_rounded,
                onTap:
                    () => _showConfirmationDialog(
                      context,
                      title: 'Clear History?',
                      content: 'This will permanently delete all chat history.',
                      onConfirm: () {
                        settingsState.clearChatHistory();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Chat history cleared')),
                        );
                      },
                    ),
              ),
              _buildActionTile(
                context: context,
                title: 'Reset App',
                subtitle: 'Resets all settings and logs you out',
                icon: Icons.restart_alt_rounded,
                onTap:
                    () => _showConfirmationDialog(
                      context,
                      title: 'Reset App?',
                      content:
                          'This will clear all data and return to onboarding. This cannot be undone.',
                      onConfirm: () async {
                        await settingsState.resetApp();
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

  Widget _buildGeminiSwitch(BuildContext context) {
    return Card(
      elevation: 2,
      child: SwitchListTile(
        title: const Text('Enable Gemini 2.0'),
        subtitle: const Text('Use enhanced AI model for all interactions'),
        value: Provider.of<AppState>(context).isGemini2Enabled,
        activeColor: Theme.of(context).colorScheme.primary,
        onChanged: (value) {
          final appState = Provider.of<AppState>(context, listen: false);
          appState.setGemini2Enabled(value);
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Text(
        title,
        style: textTheme.titleMedium?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildThemeSelector(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildThemeButton(
              context,
              'Light',
              ThemeMode.light,
              appState.currentThemeMode == ThemeMode.light,
            ),
            _buildThemeButton(
              context,
              'Dark',
              ThemeMode.dark,
              appState.currentThemeMode == ThemeMode.dark,
            ),
            _buildThemeButton(
              context,
              'System',
              ThemeMode.system,
              appState.currentThemeMode == ThemeMode.system,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeButton(
    BuildContext context,
    String label,
    ThemeMode themeMode,
    bool isSelected,
  ) {
    final appState = Provider.of<AppState>(context, listen: false);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => appState.setThemeMode(themeMode),
      child: Chip(
        label: Text(
          label,
          style: textTheme.bodyMedium?.copyWith(
            color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
          ),
        ),
        backgroundColor: isSelected ? colorScheme.primary : colorScheme.surface,
      ),
    );
  }

  Widget _buildSliderTile({
    required BuildContext context,
    required String label,
    required double value,
    required IconData icon,
    required ValueChanged<double> onChanged,
    required double min,
    required double max,
    int? divisions,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(icon, color: colorScheme.primary),
              title: Text(
                label,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: colorScheme.secondary,
              inactiveColor: colorScheme.onSurface.withAlpha(77),
              onChanged: onChanged,
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
    final textTheme = Theme.of(context).textTheme;
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
          style: TextStyle(color: titleColor.withAlpha(179)),
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            title,
            style: textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            content,
            style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(
                'Cancel',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                onConfirm();
                Navigator.of(dialogContext).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBlindModeTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 2,
      child: SwitchListTile(
        title: const Text('Blind Mode'),
        subtitle: const Text(
          'Enable voice-only mode and enhanced accessibility features.',
        ),
        value: _isBlindModeEnabled,
        activeColor: colorScheme.primary,
        onChanged: (value) {
          setState(() {
            _isBlindModeEnabled = value;
            if (value) {
              _chatState.enableBlindMode();
            } else {
              _chatState.disableBlindMode();
            }
          });
        },
      ),
    );
  }

  Widget _buildUpdateTile(BuildContext context) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: const Icon(Icons.system_update_rounded, color: Colors.blue),
        title: const Text(
          'Check for Updates',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('Check for new app versions and install updates.'),
        onTap: () => _checkForUpdates(context),
      ),
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => const UpdateProgressDialog(),
    );

    try {
      final updateService = UpdateService();
      final hasUpdate = await updateService.checkAndInstallUpdate();

      if (context.mounted) {
        Navigator.of(context).pop(); // Dismiss progress dialog

        if (hasUpdate) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Update downloaded. Please restart the app.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('App is up to date')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Dismiss progress dialog
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update check failed: $e')));
      }
    }
  }
}

class UpdateProgressDialog extends StatelessWidget {
  const UpdateProgressDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Checking for updates...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
