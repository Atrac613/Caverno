import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/presentation/pages/settings_page.dart';
import '../providers/chat_notifier.dart';
import '../providers/conversations_notifier.dart';
import '../widgets/conversation_drawer.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _showDeleteConversationDialog(
    BuildContext context,
    ConversationsNotifier conversationsNotifier,
    String conversationId,
    String conversationTitle,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('chat.delete_title'.tr()),
        content: Text('chat.delete_confirm'.tr(namedArgs: {'title': conversationTitle})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    await conversationsNotifier.deleteConversation(conversationId);
    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('chat.deleted'.tr())));
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatNotifierProvider);
    final chatNotifier = ref.read(chatNotifierProvider.notifier);
    final conversationsState = ref.watch(conversationsNotifierProvider);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );

    // Scroll when the message list changes.
    ref.listen(chatNotifierProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length ||
          (next.messages.isNotEmpty && next.messages.last.isStreaming)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    });

    final currentConversation = conversationsState.currentConversation;
    final rawTitle = currentConversation?.title ?? 'Caverno';
    final currentTitle = rawTitle == defaultConversationTitle
        ? 'chat.new_conversation'.tr()
        : rawTitle;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: () => conversationsNotifier.createNewConversation(),
            icon: const Icon(Icons.add),
            tooltip: 'chat.new_conversation'.tr(),
          ),
          if (currentConversation != null)
            IconButton(
              onPressed: () => _showDeleteConversationDialog(
                context,
                conversationsNotifier,
                currentConversation.id,
                currentConversation.title,
              ),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'chat.delete_current'.tr(),
            ),
          IconButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
            icon: const Icon(Icons.settings),
            tooltip: 'chat.settings'.tr(),
          ),
        ],
      ),
      drawer: const ConversationDrawer(),
      body: Column(
        children: [
          // Error banner
          if (chatState.error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chatState.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Message list
          Expanded(
            child: chatState.messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'chat.empty_state'.tr(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: chatState.messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: chatState.messages[index]);
                    },
                  ),
          ),
          // Input area
          MessageInput(
            onSend: (message, imageBase64, imageMimeType) =>
                chatNotifier.sendMessage(
                  message,
                  imageBase64: imageBase64,
                  imageMimeType: imageMimeType,
                  languageCode: context.locale.languageCode,
                ),
            onCancel: () => chatNotifier.cancelStreaming(),
            isLoading: chatState.isLoading,
          ),
        ],
      ),
    );
  }
}
