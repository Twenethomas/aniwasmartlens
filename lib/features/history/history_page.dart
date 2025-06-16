// lib/features/history/history_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../aniwa_chat/state/chat_state.dart'; // Import ChatState

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  // Internal state to hold the conversation history
  List<Map<String, String>> _history = [];
  late ChatState _chatState; // Reference to ChatState
  VoidCallback? _chatStateListener; // Store the listener for disposal

  @override
  void initState() {
    super.initState();
    // No direct access to Provider.of in initState, use didChangeDependencies or a post-frame callback
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get the ChatState instance
    final newChatState = Provider.of<ChatState>(context);

    // Only re-register the listener if the ChatState instance has changed or if _chatState is not yet initialized
    if (_chatStateListener == null || newChatState != _chatState) {
      _chatStateListener?.call(); // Deregister old listener if exists

      _chatState = newChatState; // Assign the new ChatState instance
      _chatStateListener = () {
        // When ChatState notifies, update our local history and trigger a rebuild
        _loadHistory();
      };
      _chatState.addListener(_chatStateListener!);
      _loadHistory(); // Load history initially
    }
  }

  void _loadHistory() {
    setState(() {
      _history = List.unmodifiable(_chatState.conversationHistory);
    });
    // For debugging:
    // print('HistoryPage: Loaded history. Current length: ${_history.length}');
  }

  @override
  void dispose() {
    _chatStateListener?.call(); // Deregister the listener
    super.dispose();
  }

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
      // The Consumer is no longer strictly needed for data, but can be kept for consistency
      // or if specific widgets within the body still need to directly listen to ChatState.
      // However, since we're managing _history in StatefulWidget, direct use is fine.
      body:
          _history.isEmpty
              ? Center(
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
              )
              : ListView.builder(
                reverse: true, // Display latest messages at the bottom
                padding: const EdgeInsets.all(16.0),
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  // Access messages in reverse order for ListView.builder(reverse: true)
                  final message = _history[_history.length - 1 - index];
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
                // Access ChatState via Provider and call clearChatHistory
                Provider.of<ChatState>(
                  context,
                  listen:
                      false, // listen: false because we are only calling a method
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
