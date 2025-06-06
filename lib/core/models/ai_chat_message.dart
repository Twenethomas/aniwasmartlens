// lib/models/ai_chat_message.dart
enum MessageSender { user, ai }

class AIChatMessage {
  final String text;
  final MessageSender sender;
  final DateTime timestamp; // Added for realistic timestamps

  AIChatMessage({
    required this.text,
    required this.sender,
    required this.timestamp,
  });
}
