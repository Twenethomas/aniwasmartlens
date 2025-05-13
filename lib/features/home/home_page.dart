import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/network_service.dart';
import 'widgets/feature_card.dart';
import 'widgets/quick_action_carousel.dart';
import 'widgets/recent_activity_list.dart';
import 'widgets/weather_widget.dart';
import 'widgets/pairing_status_widget.dart';
import 'widgets/context_tips_widget.dart';
import 'widgets/voice_launcher.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    // Use NetworkService rather than raw ConnectivityResult
    final isOnline = context.watch<NetworkService>().isOnline;
    final userName = 'John Doe'; // TODO: pull actual user name

    // Define your core features and their navigation routes
    final features = [
      {
        'title': 'Text Reader',
        'icon': Icons.text_fields,
        'route': '/textReader',
      },
      {
        'title': 'Scene Description',
        'icon': Icons.image_search,
        'route': '/sceneDescription',
      },
      {'title': 'Navigation', 'icon': Icons.navigation, 'route': '/navigation'},
      {
        'title': 'Emergency',
        'icon': Icons.warning_amber,
        'route': '/emergency',
      },
      {'title': 'Video Call', 'icon': Icons.video_call, 'route': '/videoCall'},
      {'title': 'Webcam', 'icon': Icons.camera_alt, 'route': '/pcCam'},
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Greeting & user
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_greeting()},',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Connectivity indicator
                  Icon(
                    isOnline ? Icons.wifi : Icons.wifi_off,
                    color: isOnline ? Colors.green : Colors.red,
                  ),

                  const SizedBox(width: 12),

                  // Weather snapshot
                  const WeatherWidget(),
                ],
              ),
            ),

            // ─── Quick-Action Carousel ─────────────────────────────
            QuickActionCarousel(
              items: [
                {
                  'icon': Icons.text_fields,
                  'label': 'Read Text',
                  'onTap': () {
                    Navigator.pushNamed(context, '/textReader');
                  },
                },
                {
                  'icon': Icons.warning_amber,
                  'label': 'SOS',
                  'onTap': () {
                    Navigator.pushNamed(context, '/emergency');
                  },
                },
                {
                  'icon': Icons.video_call,
                  'label': 'Call Caretaker',
                  'onTap': () {
                    Navigator.pushNamed(context, '/videoCall');
                  },
                },
                {
                  'icon': Icons.image_search,
                  'label': 'Describe Scene',
                  'onTap': () {
                    Navigator.pushNamed(context, '/sceneDescription');
                  },
                },
                {
                  'icon': Icons.camera_alt,
                  'label': 'Webcam',
                  'onTap': () {
                    Navigator.pushNamed(context, '/pcCam');
                  },
                },
                {
                  'icon': Icons.navigation,
                  'label': 'Navigation',
                  'onTap': () {
                    Navigator.pushNamed(context, '/navigation');
                  },
                },
                
              ],
            ),

            const SizedBox(height: 16),

            // ─── Recent Activity Feed ──────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const Text(
                    'Recent Activity',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  RecentActivityList(
                    activities: [
                      'Read “Menu” at 10:21 AM',
                      'Called caregiver at 9:45 AM',
                      'Described scene at 9:10 AM',
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ─── Feature Grid ────────────────────────────────
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth > 600 ? 3 : 2;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: features.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.9,
                        ),
                        itemBuilder: (_, i) {
                          final f = features[i];
                          return FeatureCard(
                            title: f['title'] as String,
                            icon: f['icon'] as IconData,
                            onTap:
                                () => Navigator.pushNamed(
                                  context,
                                  f['route'] as String,
                                ),
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // ─── Caretaker Panel ──────────────────────────────
                  const PairingStatusWidget(),
                  const SizedBox(height: 16),

                  // ─── Contextual Tips ──────────────────────────────
                  const ContextTipsWidget(),
                ],
              ),
            ),
          ],
        ),
      ),

      // ─── Voice Launcher & Bottom Nav ─────────────────────────
      floatingActionButton: const VoiceLauncher(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: Theme.of(context).primaryColor,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_none),
            label: 'Alerts',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
        onTap: (idx) {
          // TODO: navigate to Alerts/Profile based on idx
        },
      ),
    );
  }
}
