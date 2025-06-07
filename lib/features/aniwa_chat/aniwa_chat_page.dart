// lib/features/aniwa_chat/aniwa_chat_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart'; // Import Provider
import 'package:logger/logger.dart'; // Import logger

import 'package:assist_lens/features/aniwa_chat/state/chat_state.dart'; // Import the new ChatState
import 'package:assist_lens/main.dart'; // Import for routeObserver

class AniwaChatPage extends StatefulWidget {
  final String? initialQuery;
  final bool isForTabInitialization; // New flag
  const AniwaChatPage({
    super.key,
    this.initialQuery,
    this.isForTabInitialization = false, // Default to false
  });

  @override
  State<AniwaChatPage> createState() => _AniwaChatPageState();
}

class _AniwaChatPageState extends State<AniwaChatPage>
    with TickerProviderStateMixin, RouteAware {
  final TextEditingController _textInputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _textFocusNode = FocusNode();
  final Logger _logger = Logger();

  late ChatState _chatState; // Reference to ChatState

  // Animation for the AI typing indicator
  late AnimationController _typingAnimationController;
  late Animation<double> _typingAnimation;

  @override
  void initState() {
    super.initState();
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _typingAnimation = CurvedAnimation(
      parent: _typingAnimationController,
      curve: Curves.easeInOut,
    );

    // Add post frame callback to ensure routeObserver is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = ModalRoute.of(context);
      if (route is PageRoute) {
        // Ensure it's a PageRoute before subscribing
        routeObserver.subscribe(this, route);
      } else {
        _logger.w(
          "AniwaChatPage: Cannot subscribe to RouteObserver, current route is not a PageRoute.",
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatState = Provider.of<ChatState>(context, listen: false);

    // Set the navigation callback for ChatState
    _chatState.onNavigateRequested = (routeName, {arguments}) {
      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacementNamed(routeName, arguments: arguments);
      }
    };

    // If this page is initialized for a tab (not a direct voice command launch)
    // and there's an initial query, process it.
    if (widget.isForTabInitialization &&
        widget.initialQuery != null &&
        widget.initialQuery!.isNotEmpty) {
      _logger.i(
        "ChatPage: Processing initial query from tab init: ${widget.initialQuery}",
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatState.processUserMessage(widget.initialQuery!, context);
      });
    } else if (!widget.isForTabInitialization &&
        _chatState.conversationHistory.isEmpty) {
      // If not from tab init and chat is empty, give initial greeting
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _chatState.initialGreeting(context); // Pass context here
      });
    }
    _chatState.addListener(_scrollChatToBottom); // Listen for changes to scroll
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this); // Unsubscribe from route updates
    _textInputController.dispose();
    _scrollController.dispose();
    _textFocusNode.dispose();
    _typingAnimationController.dispose();
    _chatState.removeListener(_scrollChatToBottom);
    _chatState.onNavigateRequested = null; // Clear the callback
    super.dispose();
  }

  // --- RouteAware Methods ---
  @override
  void didPush() {
    _logger.i("AniwaChatPage: didPush - Page is active.");
    // When the page is pushed, ensure continuous listening is active if desired
    _chatState.startVoiceInput();
    super.didPush();
  }

  @override
  void didPopNext() {
    _logger.i("AniwaChatPage: didPopNext - Returning to page.");
    // When returning to this page from another, resume continuous listening
    _chatState.startVoiceInput();
    super.didPopNext();
  }

  @override
  void didPushNext() {
    _logger.i("AniwaChatPage: didPushNext - Navigating away from page.");
    // When navigating away from this page, stop continuous listening
    _chatState.stopVoiceInput();
    super.didPushNext();
  }

  @override
  void didPop() {
    _logger.i("AniwaChatPage: didPop - Page is being popped.");
    // When the page is popped, stop continuous listening
    _chatState.stopVoiceInput();
    super.didPop();
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    if (_textInputController.text.trim().isNotEmpty) {
      _chatState.sendMessage(
        _textInputController.text.trim(),
        context,
      ); // Pass context here
      _textInputController.clear();
      _textFocusNode.unfocus(); // Close keyboard after sending
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme; // Get textTheme here
    // Watch ChatState for changes to rebuild UI
    final chatState = context.watch<ChatState>();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor:
            colorScheme.surface, // AppBar background matches surface
        elevation: 0,
        title: Text(
          'Chat with Aniwa',
          style: GoogleFonts.sourceCodePro(
            color: colorScheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: colorScheme.onSurface,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: colorScheme.onSurface),
            onPressed: () {
              _chatState.clearChatHistory();
            },
            tooltip: 'Clear Chat',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child:
                chatState.conversationHistory.isEmpty &&
                        !chatState.isProcessingAI
                    ? Center(
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
                            'No recent chats. Start a new conversation!',
                            style: GoogleFonts.inter(
                              color: colorScheme.onSurface.withAlpha(
                                (0.7 * 255).round(),
                              ),
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16.0),
                      itemCount:
                          chatState.conversationHistory.length +
                          (chatState.isProcessingAI ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index < chatState.conversationHistory.length) {
                          final message = chatState.conversationHistory[index];
                          // Pass textTheme to the chat bubble builder
                          return _buildChatBubble(
                            message['role']!,
                            message['content']!,
                            textTheme,
                          );
                        } else {
                          // AI typing indicator
                          return _buildTypingIndicator(colorScheme);
                        }
                      },
                    ),
          ),
          if (chatState.errorMessage != null &&
              chatState.errorMessage!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8.0),
              color: colorScheme.error.withAlpha((0.2 * 255).round()),
              child: Text(
                chatState.errorMessage!,
                style: TextStyle(color: colorScheme.onError),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              bottom: 8.0,
              top: 8.0,
            ),
            child: Column(
              children: [
                if (chatState.isSpeaking)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.volume_up, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            chatState.aiSpeakingFullText,
                            style: GoogleFonts.inter(
                              color: colorScheme.onSurface,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.stop, color: colorScheme.primary),
                          onPressed: () {
                            _chatState.stopSpeaking();
                          },
                        ),
                      ],
                    ),
                  ),
                if (chatState.currentInputMode == InputMode.voice &&
                    chatState.isListening)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      chatState.recognizedText.isEmpty
                          ? 'Listening...'
                          : chatState.recognizedText,
                      style: GoogleFonts.inter(
                        color: colorScheme.primary,
                        fontStyle: FontStyle.italic,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Row(
                  children: [
                    // Keyboard Icon (toggles to text input)
                    IconButton(
                      icon: Icon(
                        Icons.keyboard_alt_rounded,
                        color:
                            chatState.currentInputMode == InputMode.text
                                ? colorScheme.primary
                                : colorScheme.onSurface.withOpacity(0.7),
                      ),
                      onPressed: () {
                        chatState.setInputMode(InputMode.text);
                      },
                      tooltip: 'Type message',
                    ),
                    // Camera Icon (for image input)
                    IconButton(
                      icon: Icon(
                        Icons.camera_alt_rounded,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                      onPressed: () {
                        // Handle camera input (e.g., navigate to scene description or object detection)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Image input coming soon!')),
                        );
                      },
                      tooltip: 'Send image',
                    ),
                    Expanded(
                      child: Container(
                        height: 50, // Fixed height for mic button container
                        margin: const EdgeInsets.symmetric(horizontal: 8.0),
                        child:
                            chatState.currentInputMode == InputMode.voice
                                ? ElevatedButton(
                                  onPressed:
                                      chatState.isProcessingAI
                                          ? null // Disable button if AI is processing
                                          : () {
                                            if (chatState.isListening) {
                                              _chatState.stopVoiceInput();
                                            } else {
                                              _chatState.startVoiceInput();
                                            }
                                          },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        chatState.isProcessingAI
                                            ? colorScheme.primary.withAlpha(
                                              (0.5 * 255).round(),
                                            )
                                            : colorScheme.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25.0),
                                    ),
                                    padding:
                                        EdgeInsets
                                            .zero, // Remove default padding
                                    minimumSize: const Size(
                                      double.infinity,
                                      50,
                                    ), // Ensure it fills horizontally and has height
                                  ),
                                  child: Icon(
                                    chatState.isListening
                                        ? Icons.mic_off
                                        : Icons.mic,
                                    color: colorScheme.onPrimary,
                                    size: 28,
                                  ),
                                )
                                : TextField(
                                  controller: _textInputController,
                                  focusNode: _textFocusNode,
                                  onSubmitted:
                                      (_) =>
                                          _sendMessage(), // Send message on enter key
                                  decoration: InputDecoration(
                                    hintText: 'Type your message...',
                                    hintStyle: textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurface.withOpacity(
                                        0.6,
                                      ),
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(25.0),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor:
                                        colorScheme.surfaceContainerHighest,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                  ),
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                      ),
                    ),
                    // Send/Stop Mic Button on Right
                    FloatingActionButton(
                      onPressed:
                          chatState.currentInputMode == InputMode.text
                              ? _sendMessage // Send message for text mode
                              : (chatState.isProcessingAI ||
                                      chatState.isSpeaking
                                  ? null // Disable if AI processing or speaking
                                  : (chatState.isListening
                                      ? _chatState.stopVoiceInput
                                      : _chatState.startVoiceInput)),
                      backgroundColor:
                          chatState.isProcessingAI || chatState.isSpeaking
                              ? colorScheme.primary.withAlpha(
                                (0.5 * 255).round(),
                              )
                              : (chatState.currentInputMode ==
                                          InputMode.voice &&
                                      chatState.isListening
                                  ? colorScheme
                                      .error // Red for stop listening
                                  : colorScheme.primary),
                      mini: true,
                      child: Icon(
                        chatState.currentInputMode == InputMode.text
                            ? Icons.send
                            : (chatState.isListening
                                ? Icons.stop_rounded
                                : Icons.mic),
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).padding.bottom,
          ), // Adjust for soft keyboard
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(ColorScheme colorScheme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            return FadeTransition(
              opacity: _typingAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: CircleAvatar(
                  radius: 4,
                  backgroundColor: colorScheme.onSecondaryContainer,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildChatBubble(String role, String text, TextTheme textTheme) {
    // Added textTheme parameter
    final isUser = role == 'user';
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bubbleColor =
        isUser
            ? Theme.of(context).colorScheme.primary.withAlpha(
              (0.15 * 255).round(),
            ) // User bubble color
            : Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest; // Aniwa bubble color
    final textColor = Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft:
                isUser ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight:
                isUser ? const Radius.circular(4) : const Radius.circular(16),
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(color: textColor, fontSize: 15),
        ),
      ),
    );
  }
}
