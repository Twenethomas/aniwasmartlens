// lib/features/history/history_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../aniwa_chat/state/chat_state.dart'; // Import ChatState

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        title: Text(
          'Chat History',
          style: textTheme.headlineSmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.delete_forever_rounded, color: colorScheme.error),
            onPressed: () {
              // Show a confirmation dialog before clearing history
              _showClearHistoryConfirmationDialog(context);
            },
            tooltip: 'Clear All History',
          ),
        ],
      ),
      body: Consumer<ChatState>(
        builder: (context, chatState, child) {
          final history = chatState.conversationHistory;

          if (history.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 80,
                      color: colorScheme.onSurface.withAlpha(
                        (0.3 * 255).round(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Your chat history is empty.',
                      style: textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface.withAlpha(
                          (0.7 * 255).round(),
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Start a conversation on the Home page or Aniwa Chat to see it here.',
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withAlpha(
                          (0.6 * 255).round(),
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            reverse: true, // Display latest messages at the bottom
            padding: const EdgeInsets.all(16.0),
            itemCount: history.length,
            itemBuilder: (context, index) {
              final message =
                  history[history.length -
                      1 -
                      index]; // Access messages in reverse order
              final isUser = message['role'] == 'user';

              return Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4.0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 10.0,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isUser
                            ? colorScheme.primary.withOpacity(0.15)
                            : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft:
                          isUser
                              ? const Radius.circular(16)
                              : const Radius.circular(4),
                      bottomRight:
                          isUser
                              ? const Radius.circular(4)
                              : const Radius.circular(16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        isUser
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                    children: [
                      Text(
                        isUser ? 'You' : 'Aniwa',
                        style: textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color:
                              isUser
                                  ? colorScheme.primary
                                  : colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message['content'] ?? '',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Shows a confirmation dialog before clearing the chat history.
  void _showClearHistoryConfirmationDialog(BuildContext context) {
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
            'Clear Chat History?',
            style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurface),
          ),
          content: Text(
            'Are you sure you want to clear all your chat history? This action cannot be undone.',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withAlpha((0.8 * 255).round()),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Dismiss dialog
              },
              child: Text(
                'Cancel',
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Provider.of<ChatState>(
                  context,
                  listen: false,
                ).clearChatHistory();
                Navigator.of(dialogContext).pop(); // Dismiss dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Chat history cleared!',
                      style: TextStyle(color: colorScheme.onPrimary),
                    ),
                    backgroundColor: colorScheme.primary,
                  ),
                );
              },
              child: Text(
                'Clear',
                style: textTheme.labelLarge?.copyWith(color: colorScheme.error),
              ),
            ),
          ],
        );
      },
    );
  }
}
