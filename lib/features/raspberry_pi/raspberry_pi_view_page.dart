// lib/features/raspberry_pi/raspberry_pi_view_page.dart
import 'dart:async';
import 'package:assist_lens/core/routing/app_router.dart';
import 'package:assist_lens/features/aniwa_chat/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/services/raspberry_pi_service.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import '../../core/services/speech_service.dart';

class Command {
  final String name;
  final String label;
  final IconData icon;
  final bool isDestructive;
  final Color? color;

  const Command({
    required this.name,
    required this.label,
    required this.icon,
    this.isDestructive = false,
    this.color,
  });
}

final List<Command> piCommands = [
  const Command(
    name: 'describe_scene',
    label: 'Describe Scene',
    icon: Icons.visibility,
    color: Colors.blue,
  ),
  const Command(
    name: 'read_text',
    label: 'Read Text',
    icon: Icons.text_fields,
    color: Colors.green,
  ),
  const Command(
    name: 'detect_objects',
    label: 'Detect Objects',
    icon: Icons.category,
    color: Colors.orange,
  ),
  const Command(
    name: 'recognize_face',
    label: 'Recognize Face',
    icon: Icons.face,
    color: Colors.purple,
  ),
  const Command(
    name: 'check_obstacle',
    label: 'Check Obstacle',
    icon: Icons.warning_amber_rounded,
    color: Colors.amber,
  ),
  const Command(
    name: 'toggle_led',
    label: 'Toggle LED',
    icon: Icons.lightbulb_outline,
    color: Colors.yellow,
  ),
  const Command(
    name: 'trigger_buzzer',
    label: 'Buzzer',
    icon: Icons.volume_up,
    color: Colors.indigo,
  ),
  const Command(
    name: 'announce_location',
    label: 'Location',
    icon: Icons.location_on,
    color: Colors.red,
  ),
  const Command(
    name: 'announce_weather',
    label: 'Weather',
    icon: Icons.wb_sunny,
    color: Colors.cyan,
  ),
  const Command(
    name: 'toggle_voice_input',
    label: 'Voice Command',
    icon: Icons.mic,
    color: Colors.teal,
  ),
  const Command(
    name: 'repeat_last',
    label: 'Repeat',
    icon: Icons.repeat,
    color: Colors.grey,
  ),
  const Command(
    name: 'emergency_alert',
    label: 'Emergency',
    icon: Icons.emergency,
    isDestructive: true,
    color: Colors.red,
  ),
];

class RaspberryPiViewPage extends StatefulWidget {
  const RaspberryPiViewPage({super.key});

  @override
  State<RaspberryPiViewPage> createState() => _RaspberryPiViewPageState();
}

class _RaspberryPiViewPageState extends State<RaspberryPiViewPage>
    with TickerProviderStateMixin {
  late RaspberryPiService _piService;
  late SpeechService _speechService;
  late TabController _tabController;
  final List<Map<String, dynamic>> _logs = [];
  final List<Map<String, dynamic>> _userMessages = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  
  StreamSubscription? _logSubscription;
  StreamSubscription? _userMessageSubscription;
  StreamSubscription? _speechOutputSubscription;
  StreamSubscription? _statusSubscription;

  String _currentPiStatus = "Connected";
  bool _isVideoExpanded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _piService = Provider.of<RaspberryPiService>(context, listen: false);
    _speechService = Provider.of<SpeechService>(context, listen: false);

    _setupListeners();
    _checkConnectionStatus();
  }

  void _setupListeners() {
    _logSubscription = _piService.logStream.listen((logEntry) {
      if (mounted) {
        setState(() => _logs.insert(0, logEntry));
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    });

    _userMessageSubscription = _piService.userMessageStream.listen((message) {
      if (mounted) {
        setState(() => _userMessages.insert(0, message));
      }
    });

    _speechOutputSubscription = _piService.speechOutputStream.listen((message) {
      if (mounted) {
        _speechService.speak(message);
      }
    });

    _statusSubscription = _piService.statusUpdateStream.listen((statusUpdate) {
      if (mounted) {
        final type = statusUpdate['type'] as String?;
        if (type == 'system_status' || type == 'obstacle_alert') {
          setState(() {
            _currentPiStatus = statusUpdate['data']?['message'] ?? "Status update received";
          });
        } else if (type == 'emergency_alert') {
          setState(() {
            _currentPiStatus = "EMERGENCY: ${statusUpdate['data']?['message'] ?? "Alert!"}";
          });
        }
      }
    });
  }

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  context.read<ChatState>().updateCurrentRoute(AppRouter.aniwaChat); // or the correct route
}
  void _checkConnectionStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_piService.connectionStatus != RaspberryPiConnectionStatus.connected) {
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lost connection to Raspberry Pi.')),
        );
      }
    });
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isNotEmpty) {
      _piService.sendCommand('caretaker_message', params: {'message': message});
      _messageController.clear();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _logSubscription?.cancel();
    _speechOutputSubscription?.cancel();
    _userMessageSubscription?.cancel();
    _statusSubscription?.cancel();
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'AssistLens Control',
          style: GoogleFonts.orbitron(fontWeight: FontWeight.bold),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _isVideoExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
              color: colorScheme.onPrimary,
            ),
            onPressed: () => setState(() => _isVideoExpanded = !_isVideoExpanded),
            tooltip: 'Toggle video size',
          ),
          IconButton(
            icon: Icon(Icons.logout_rounded, color: colorScheme.onPrimary),
            onPressed: () async {
              await _piService.disconnect();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            tooltip: 'Disconnect from Glasses',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.onPrimary,
          unselectedLabelColor: colorScheme.onPrimary.withOpacity(0.7),
          indicatorColor: colorScheme.onPrimary,
          tabs: const [
            Tab(icon: Icon(Icons.control_camera), text: 'Control'),
            Tab(icon: Icon(Icons.message), text: 'Messages'),
            Tab(icon: Icon(Icons.description), text: 'Logs'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Video Feed Section
          _buildVideoSection(colorScheme, textTheme),
          
          // Status Bar
          _buildStatusBar(colorScheme, textTheme),
          
          // Tabbed Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildControlTab(colorScheme),
                _buildMessagesTab(colorScheme, textTheme),
                _buildLogsTab(colorScheme, textTheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSection(ColorScheme colorScheme, TextTheme textTheme) {
    final videoUrl = _piService.videoFeedUrl;
    final aspectRatio = _isVideoExpanded ? 16 / 9 : 4 / 3;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: videoUrl != null
              ? Mjpeg(
                  isLive: true,
                  stream: videoUrl,
                  fit: BoxFit.cover,
                  loading: (context) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Loading video feed...',
                          style: textTheme.bodyMedium?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  error: (context, error, stackTrace) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.videocam_off,
                          color: colorScheme.error,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Video feed unavailable',
                          style: textTheme.titleMedium?.copyWith(color: Colors.white),
                        ),
                        Text(
                          'Check camera connection',
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.videocam_off,
                      color: Colors.white.withOpacity(0.5),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No video feed available',
                      style: textTheme.bodyLarge?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(ColorScheme colorScheme, TextTheme textTheme) {
    final isEmergency = _currentPiStatus.contains('EMERGENCY');
    final isWarning = _currentPiStatus.contains('OBSTACLE') || _currentPiStatus.contains('WARN');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isEmergency
            ? colorScheme.errorContainer
            : isWarning
                ? Colors.orange.withOpacity(0.1)
                : colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEmergency
              ? colorScheme.error
              : isWarning
                  ? Colors.orange
                  : colorScheme.primary,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isEmergency
                ? Icons.emergency
                : isWarning
                    ? Icons.warning
                    : Icons.check_circle,
            color: isEmergency
                ? colorScheme.error
                : isWarning
                    ? Colors.orange
                    : colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _currentPiStatus,
              style: textTheme.bodyMedium?.copyWith(
                color: isEmergency
                    ? colorScheme.onErrorContainer
                    : isWarning
                        ? Colors.orange.shade800
                        : colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlTab(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        itemCount: piCommands.length,
        itemBuilder: (context, index) {
          final command = piCommands[index];
          return _buildCommandButton(command, colorScheme);
        },
      ),
    );
  }

  Widget _buildCommandButton(Command command, ColorScheme colorScheme) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      color: command.isDestructive
          ? colorScheme.errorContainer
          : command.color?.withOpacity(0.1) ?? colorScheme.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _piService.sendCommand(command.name),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: command.isDestructive
                      ? colorScheme.error.withOpacity(0.1)
                      : command.color?.withOpacity(0.2) ?? colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  command.icon,
                  size: 28,
                  color: command.isDestructive
                      ? colorScheme.error
                      : command.color ?? colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                command.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: command.isDestructive
                      ? colorScheme.onErrorContainer
                      : colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesTab(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      children: [
        // Send Message Section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send Message to Glasses',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: colorScheme.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        prefixIcon: Icon(Icons.message, color: colorScheme.primary),
                      ),
                      maxLines: 2,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(12),
                    color: colorScheme.primary,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _sendMessage,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          Icons.send,
                          color: colorScheme.onPrimary,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Messages from Glasses
        Expanded(
          child: Container(
            color: colorScheme.surfaceContainerLowest.withOpacity(0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.message_outlined, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Messages from Glasses',
                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_userMessages.length}',
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _userMessages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 64,
                                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No messages yet',
                                style: textTheme.bodyLarge?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              Text(
                                'Messages from the glasses will appear here',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _userMessages.length,
                          itemBuilder: (context, index) {
                            final msg = _userMessages[index];
                            final timestamp = DateTime.tryParse(msg['timestamp'] ?? '') ?? DateTime.now();
                            final formattedTime = DateFormat('HH:mm:ss').format(timestamp);
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: colorScheme.primary.withOpacity(0.1),
                                    child: Icon(
                                      Icons.smart_display,
                                      color: colorScheme.primary,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    msg['message'] as String,
                                    style: textTheme.bodyMedium,
                                  ),
                                  subtitle: Text(
                                    formattedTime,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(
                                      Icons.volume_up,
                                      color: colorScheme.primary,
                                      size: 20,
                                    ),
                                    onPressed: () => _speechService.speak(msg['message'] as String),
                                    tooltip: 'Read aloud',
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogsTab(ColorScheme colorScheme, TextTheme textTheme) {
    return Container(
      color: colorScheme.surfaceContainerLowest.withOpacity(0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.description_outlined, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'System Logs',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_logs.length}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.clear_all, color: colorScheme.onSurfaceVariant),
                  onPressed: () {
                    setState(() => _logs.clear());
                  },
                  tooltip: 'Clear logs',
                ),
              ],
            ),
          ),
          Expanded(
            child: _logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.assignment_outlined,
                          size: 64,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No logs yet',
                          style: textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        Text(
                          'System activity will be logged here',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final timestamp = DateTime.parse(log['timestamp']);
                      final formattedTime = DateFormat('HH:mm:ss').format(timestamp);
                      final message = log['message'] as String;
                      final isError = message.contains('ERROR') || message.contains('EMERGENCY');
                      final isWarning = message.contains('WARN') || message.contains('OBSTACLE');
                      final isInfo = message.contains('INFO') || message.contains('Connected');

                      IconData logIcon;
                      Color logColor;
                      
                      if (isError) {
                        logIcon = Icons.error;
                        logColor = colorScheme.error;
                      } else if (isWarning) {
                        logIcon = Icons.warning;
                        logColor = Colors.orange;
                      } else if (isInfo) {
                        logIcon = Icons.info;
                        logColor = colorScheme.primary;
                      } else {
                        logIcon = Icons.circle;
                        logColor = colorScheme.onSurfaceVariant;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: Card(
                          elevation: 1,
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: SizedBox(
                              width: 40,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    logIcon,
                                    color: logColor,
                                    size: 16,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    formattedTime,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            title: Text(
                              message,
                              style: textTheme.bodySmall?.copyWith(
                                color: logColor,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}