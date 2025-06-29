// lib/features/aniwa_chat/aniwa_chat_page.dart
// Keep if any Timer or StreamController is used directly in this file
import 'package:assist_lens/core/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:animated_text_kit/animated_text_kit.dart';

import 'package:assist_lens/features/aniwa_chat/state/chat_state.dart';
import 'package:assist_lens/main.dart'; // Ensure this import is correct

class AniwaChatPage extends StatefulWidget {
  final String? initialQuery;
  final bool isForTabInitialization;

  const AniwaChatPage({
    super.key,
    this.initialQuery,
    this.isForTabInitialization = false,
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

  late ChatState _chatState;
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _waveAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _waveController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _waveAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Get chatState without listening here, as the Consumer handles rebuilding
    _chatState = Provider.of<ChatState>(context, listen: false);

    // Set the scroll callback in ChatState
    _chatState.setScrollToBottomCallback(_scrollToBottom);

    if (!widget.isForTabInitialization) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Initial greeting should only happen once per app launch, or when relevant.
        // It's better managed by ChatState's own initialization logic.
        // If initialQuery is provided, we should add it.
        if (widget.initialQuery != null) {
          _chatState.addUserMessage(widget.initialQuery!);
        } else {
          // If no initial query, and chat history is empty, provide greeting.
          // This ensures greeting is only given when starting a fresh chat.
          if (_chatState.conversationHistory.isEmpty) {
            _chatState.initialGreeting(context);
          }
        }
      });
    }

    // Subscribe to route events for lifecycle management
    // Only subscribe if the route is valid (not null)
    final ModalRoute<dynamic>? currentRoute = ModalRoute.of(context);
    if (currentRoute != null && currentRoute is PageRoute) {
      routeObserver.subscribe(this, currentRoute);
    } else {
      _logger.w(
        "AniwaChatPage: ModalRoute is null or not a PageRoute, skipping RouteAware subscription.",
      );
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _fadeController.dispose();
    _textInputController.dispose();
    _scrollController.dispose();
    _textFocusNode.dispose();
    routeObserver.unsubscribe(this); // Unsubscribe from route events
    super.dispose();
  }

  // --- RouteAware methods for lifecycle management ---

  @override
  void didPush() {
    // This page has been pushed onto the stack and is now fully visible.
    context.read<ChatState>().updateCurrentRoute(AppRouter.aniwaChat); // or the correct route

    _logger.i('AniwaChatPage: didPush - Resuming chat state.');
    _chatState.setChatPageActive(true); // Set chat page active
    // Resume chat state, which will enable wake word if in voice mode
    _chatState.resume();
  }

  @override
  void didPopNext() {
    // This page is re-emerging as the top-most route after another route was popped.
    _logger.i('AniwaChatPage: didPopNext - Resuming chat state.');
    _chatState.setChatPageActive(true); // Set chat page active
    // Resume chat state, which will enable wake word if in voice mode
    _chatState.resume();
  }

  @override
  void didPop() {
    // This page has been popped off the stack and is no longer visible.
    _logger.i('AniwaChatPage: didPop - Pausing chat state.');
    _chatState.setChatPageActive(false); // Set chat page inactive
    // Pause chat state to stop microphone use when not on this screen
    // _chatState.pause();
  }

  @override
  void didPushNext() {
    // Another page has been pushed on top of this one, making this page inactive.
    _logger.i('AniwaChatPage: didPushNext - Pausing chat state.');
    _chatState.setChatPageActive(false); // Set chat page inactive
    // Pause chat state to stop microphone use when not on this screen
    // _chatState.pause();
  }

  // --- End RouteAware methods ---

  void _scrollToBottom() {
    _logger.d("AniwaChatPage._scrollToBottom: Attempting to scroll.");
    if (_scrollController.hasClients) {
      // Use a post-frame callback to ensure layout has occurred for new items
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
          _logger.d(
            "AniwaChatPage._scrollToBottom: Scrolled to bottom. Max extent: ${_scrollController.position.maxScrollExtent}",
          );
        } else {
          _logger.w(
            "AniwaChatPage._scrollToBottom: ScrollController lost clients after post-frame callback.",
          );
        }
      });
    } else {
      _logger.w(
        "AniwaChatPage._scrollToBottom: ScrollController has no clients, cannot scroll.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatTheme = Theme.of(context).extension<ChatThemeExtension>()!;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Consumer<ChatState>(
        builder: (context, chatState, child) {
          // This ensures that the UI rebuilds whenever ChatState notifies listeners.
          // The scrolling itself is now triggered directly by ChatState after adding messages.
          _logger.d(
            "AniwaChatPage: Consumer rebuild. History length: ${chatState.conversationHistory.length}, Is processing AI: ${chatState.isProcessingAI}",
          );

          return Container(
            decoration: BoxDecoration(gradient: chatTheme.chatBackground),
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(chatState, chatTheme),
                  Expanded(child: _buildChatArea(chatState, chatTheme)),
                  _buildInputArea(chatState, chatTheme),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(ChatState chatState, ChatThemeExtension chatTheme) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: const EdgeInsets.only(right: 5.0),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            _buildAIAvatar(chatState, chatTheme),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aniwa AI',
                    style: GoogleFonts.orbitron(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildStatusText(chatState, chatTheme),
                ],
              ),
            ),
            _buildWakeWordIndicator(chatState, chatTheme),
          ],
        ),
      ),
    );
  }

  Widget _buildAIAvatar(ChatState chatState, ChatThemeExtension chatTheme) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient:
            chatState.isSpeaking
                ? chatTheme.speakingGradient
                : chatTheme.aiAvatarGradient,
        boxShadow: [
          BoxShadow(
            color: (chatState.isSpeaking
                    ? Theme.of(context).colorScheme.secondary
                    : Theme.of(context).colorScheme.primary)
                .withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: chatState.isSpeaking ? _pulseAnimation : _fadeAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: chatState.isSpeaking ? _pulseAnimation.value : 1.0,
            child: const Icon(Icons.psychology, color: Colors.white, size: 24),
          );
        },
      ),
    );
  }

  Widget _buildStatusText(ChatState chatState, ChatThemeExtension chatTheme) {
    String statusText;
    Color statusColor;

    if (chatState.errorMessage != null && chatState.errorMessage!.isNotEmpty) {
      statusText = 'Error: ${chatState.errorMessage}';
      statusColor = Colors.red;
    } else if (chatState.isProcessingAI) {
      statusText = 'Thinking...';
      statusColor = chatTheme.statusColors.thinking;
    } else if (chatState.isSpeaking) {
      statusText = 'Speaking';
      statusColor = chatTheme.statusColors.speaking;
    } else if (chatState.isListening) {
      statusText = 'Listening';
      statusColor = chatTheme.statusColors.listening;
    } else if (chatState.isWakeWordListening) {
      statusText = 'Say "Assistive Lens"';
      statusColor = chatTheme.statusColors.wakeWord;
    } else {
      statusText = 'Ready';
      statusColor = chatTheme.statusColors.ready;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Text(
        statusText,
        key: ValueKey(statusText),
        style: GoogleFonts.inter(
          fontSize: 14,
          color: statusColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildWakeWordIndicator(
    ChatState chatState,
    ChatThemeExtension chatTheme,
  ) {
    return AnimatedBuilder(
      animation: _waveAnimation,
      builder: (context, child) {
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                chatState.isWakeWordListening
                    ? chatTheme.wakeWordColor.withOpacity(0.2)
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
            border: Border.all(
              color:
                  chatState.isWakeWordListening
                      ? chatTheme.wakeWordColor.withOpacity(0.5)
                      : Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.3),
              width: 2,
            ),
          ),
          child:
              chatState.isWakeWordListening
                  ? Stack(
                    alignment: Alignment.center,
                    children: [
                      // Animated rings
                      for (int i = 0; i < 3; i++)
                        AnimatedBuilder(
                          animation: _waveAnimation,
                          builder: (context, child) {
                            final delay = i * 0.3;
                            final animationValue =
                                (_waveAnimation.value + delay) % 1.0;
                            return Container(
                              width: 20 + (animationValue * 20),
                              height: 20 + (animationValue * 20),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: chatTheme.wakeWordColor.withOpacity(
                                    1 - animationValue,
                                  ),
                                  width: 1,
                                ),
                              ),
                            );
                          },
                        ),
                      Icon(Icons.mic, color: chatTheme.wakeWordColor, size: 16),
                    ],
                  )
                  : Icon(
                    Icons.mic_off,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.5),
                    size: 16,
                  ),
        );
      },
    );
  }

  Widget _buildChatArea(ChatState chatState, ChatThemeExtension chatTheme) {
    _logger.d(
      "AniwaChatPage: Building chat area. History length: ${chatState.conversationHistory.length}, Is processing AI: ${chatState.isProcessingAI}",
    );

    if (chatState.conversationHistory.isEmpty) {
      return _buildEmptyState(chatTheme);
    }

    // The conversationHistory now inherently handles the streaming message
    int totalItems = chatState.conversationHistory.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 20),
        key: ValueKey(
          'unified_chat_list_${chatState.conversationHistory.length}_${chatState.isProcessingAI}',
        ), // Simplify key as partial message is now within history
        itemCount: totalItems,
        itemBuilder: (context, index) {
          _logger.d(
            "AniwaChatPage: ListView.builder building item at index $index, total items: $totalItems",
          );

          final message = chatState.conversationHistory[index];
          final isUser = message['role'] == 'user';

          // Determine if this is the last AI message currently being streamed
          final bool isPartialMessageBeingStreamed =
              !isUser && // It's an assistant message
              chatState.isProcessingAI && // AI is currently processing
              index ==
                  totalItems - 1 && // It's the very last message in the list
              (message['content']?.isEmpty ??
                  true); // And its content is still empty or being filled

          return _buildMessageBubble(
            message['content'] ?? '',
            isUser,
            index,
            chatTheme,
            isPartial: isPartialMessageBeingStreamed,
          );
        },
      ),
    );
  }

  Widget _buildMessageBubble(
    String content,
    bool isUser,
    int index,
    ChatThemeExtension chatTheme, {
    bool isPartial = false, // Add this parameter
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildMessageAvatar(false, chatTheme),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: isUser ? chatTheme.userMessageGradient : null,
                color: isUser ? null : chatTheme.aiMessageBackground,
                borderRadius: BorderRadius.circular(20).copyWith(
                  topLeft:
                      isUser
                          ? const Radius.circular(20)
                          : const Radius.circular(4),
                  topRight:
                      isUser
                          ? const Radius.circular(4)
                          : const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        isUser
                            ? Theme.of(
                              context,
                            ).colorScheme.primary.withOpacity(0.2)
                            : Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (content.isNotEmpty)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        content,
                        key: ValueKey('message_${index}_partial_$isPartial'),
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color:
                              isUser
                                  ? Colors.white
                                  : Theme.of(context).colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTimestamp(DateTime.now()),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color:
                              isUser
                                  ? Colors.white.withOpacity(0.8)
                                  : Theme.of(
                                    context,
                                  ).colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      if (isUser) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ],
                    ],
                  ),
                  // Show partial indicator for streaming messages
                  if (isPartial)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.7),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Receiving...',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 12),
            _buildMessageAvatar(true, chatTheme),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageAvatar(bool isUser, ChatThemeExtension chatTheme) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient:
            isUser ? chatTheme.userAvatarGradient : chatTheme.aiAvatarGradient,
        boxShadow: [
          BoxShadow(
            color: (isUser
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.tertiary)
                .withOpacity(0.3),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Icon(
        isUser ? Icons.person : Icons.psychology,
        color: Colors.white,
        size: 18,
      ),
    );
  }

  Widget _buildTypingIndicator(ChatThemeExtension chatTheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMessageAvatar(false, chatTheme),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: chatTheme.aiMessageBackground,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedTextKit(
                  animatedTexts: [
                    TypewriterAnimatedText(
                      'Typing...',
                      textStyle: GoogleFonts.inter(
                        fontSize: 16,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                      ),
                      speed: const Duration(milliseconds: 200),
                    ),
                  ],
                  isRepeatingAnimation: true,
                  repeatForever: true,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 40,
                  height: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(3, (index) {
                      return AnimatedBuilder(
                        animation: _waveAnimation,
                        builder: (context, child) {
                          final delay = index * 0.2;
                          final animationValue =
                              (_waveAnimation.value + delay) % 1.0;
                          return Transform.translate(
                            offset: Offset(
                              0,
                              -5 * (1 - (animationValue * 2 - 1).abs()),
                            ),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(0.7),
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ChatState chatState, ChatThemeExtension chatTheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: chatTheme.inputBackground,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color:
                        _textFocusNode.hasFocus
                            ? chatTheme.focusedInputBorder
                            : chatTheme.inputBorder,
                    width: 2,
                  ),
                ),
                child: TextField(
                  controller: _textInputController,
                  focusNode: _textFocusNode,
                  maxLines: null,
                  minLines: 1,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  enabled: !chatState.isProcessingAI,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        chatState.isProcessingAI
                            ? 'AI is thinking...'
                            : 'Type your message...',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 16,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (text) {
                    if (text.trim().isNotEmpty && !chatState.isProcessingAI) {
 _sendMessageWithInterruption(chatState, text.trim());
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            _buildMicButton(chatState, chatTheme),
            const SizedBox(width: 8),
            _buildSendButton(chatState, chatTheme),
          ],
        ),
      ),
    );
  }

  // Override _sendMessage to handle interruption
  // void _sendMessage(ChatState chatState, String message) {
  //   if (message.isEmpty) return;

  //   _textInputController.clear();
  //   _textFocusNode.unfocus();

  //   // Interrupt any ongoing AI speech and restart listening
  //   chatState.handleInterruption();

  //   // The scroll will be triggered by ChatState itself via the callback
  //   chatState.addUserMessage(message);
  // }

  // // Override _toggleListening to disable mic button during processing
  // void _toggleListening(ChatState chatState) {
  //   if (chatState.isProcessingAI) return;

  //   if (chatState.isListening) {
  //     chatState.stopVoiceInput();
  //   } else {
  //     chatState.startVoiceInput();
  //   }
  // }

  Widget _buildMicButton(ChatState chatState, ChatThemeExtension chatTheme) {
    return GestureDetector(
      onTap: chatState.isProcessingAI
          ? null
          : () => _toggleListeningWithProcessingCheck(chatState),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              chatState.isListening
                  ? chatTheme.wakeWordColor.withOpacity(0.2)
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
          border: Border.all(
            color:
                chatState.isListening
                    ? chatTheme.wakeWordColor
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: AnimatedBuilder(
          animation: chatState.isListening ? _pulseAnimation : _fadeAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale:
                  chatState.isListening
                      ? _pulseAnimation.value * 0.1 + 0.9
                      : 1.0,
              child: Icon(
                chatState.isListening ? Icons.mic : Icons.mic_none,
                color:
                    chatState.isListening
                        ? chatTheme.wakeWordColor
                        : Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                size: 24,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSendButton(ChatState chatState, ChatThemeExtension chatTheme) {
    final hasText = _textInputController.text.trim().isNotEmpty;

    return GestureDetector(
      onTap:
          (hasText && !chatState.isProcessingAI)
              ? () => _sendMessageWithInterruption(chatState, _textInputController.text.trim())
              : null,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient:
              (hasText && !chatState.isProcessingAI)
                  ? chatTheme.sendButtonGradient
                  : null,
          color:
              (!hasText || chatState.isProcessingAI)
                  ? Theme.of(context).colorScheme.onSurface.withOpacity(0.2)
                  : null,
        ),
        child: Icon(
          Icons.send,
          color:
              (hasText && !chatState.isProcessingAI)
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          size: 20,
        ),
      ),
    );
  }

  // Override _sendMessageWithInterruption to handle interruption
  void _sendMessageWithInterruption(ChatState chatState, String message) {
    if (message.isEmpty) return;

    _textInputController.clear();
    _textFocusNode.unfocus();

    // The scroll will be triggered by ChatState itself via the callback
    chatState.addUserMessage(message);
  }

  Widget _buildEmptyState(ChatThemeExtension chatTheme) {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: chatTheme.aiAvatarGradient,
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: const Icon(
                Icons.psychology,
                color: Colors.white,
                size: 50,
              ),
            ),
            const SizedBox(height: 30),
            Text(
              'Welcome to Aniwa AI',
              style: GoogleFonts.orbitron(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                'Your intelligent assistant is ready to help.\nSay "Assistive Lens" to start a conversation.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 30),
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      {'icon': Icons.help_outline, 'text': 'Ask a question'},
      {'icon': Icons.navigation, 'text': 'Get directions'},
      {'icon': Icons.chat, 'text': 'Start chatting'},
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children:
          actions.map((action) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.2),
                ),
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withOpacity(0.05),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    action['icon'] as IconData,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    action['text'] as String,
                    style: GoogleFonts.inter(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }

  // Override _toggleListening to disable mic button during processing
  void _toggleListeningWithProcessingCheck(ChatState chatState) {
    if (chatState.isProcessingAI) return;

    if (chatState.isListening) {
      chatState.stopVoiceInput();
    } else {
      chatState.startVoiceInput();
    }
  }

  String _formatTimestamp(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return '${dateTime.day}/${dateTime.month}';
    }
  }
}
