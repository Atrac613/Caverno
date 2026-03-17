import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/conversation.dart';
import '../providers/conversations_notifier.dart';

class ConversationDrawer extends ConsumerWidget {
  const ConversationDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsState = ref.watch(conversationsNotifierProvider);
    final notifier = ref.read(conversationsNotifierProvider.notifier);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'drawer.title'.tr(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (conversationsState.conversations.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      tooltip: 'drawer.delete_all_tooltip'.tr(),
                      onPressed: () {
                        _showDeleteAllDialog(context, notifier);
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'drawer.new_conversation'.tr(),
                    onPressed: () {
                      notifier.createNewConversation();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Conversation list
            Expanded(
              child: conversationsState.conversations.isEmpty
                  ? Center(
                      child: Text(
                        'drawer.no_conversations'.tr(),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: conversationsState.conversations.length,
                      itemBuilder: (context, index) {
                        final conversation =
                            conversationsState.conversations[index];
                        final isSelected =
                            conversation.id ==
                            conversationsState.currentConversationId;

                        return _ConversationTile(
                          conversation: conversation,
                          isSelected: isSelected,
                          onTap: () {
                            notifier.selectConversation(conversation.id);
                            Navigator.pop(context);
                          },
                          onDelete: () {
                            _showDeleteDialog(context, notifier, conversation);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    ConversationsNotifier notifier,
    Conversation conversation,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('drawer.delete_title'.tr()),
        content: Text('drawer.delete_confirm'.tr(namedArgs: {'title': conversation.title})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              notifier.deleteConversation(conversation.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteAllDialog(
    BuildContext context,
    ConversationsNotifier notifier,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('drawer.delete_all_title'.tr()),
        content: Text('drawer.delete_all_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete_all'.tr()),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    await notifier.deleteAllConversations();
    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('drawer.delete_all_done'.tr())));
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  final Conversation conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      selected: isSelected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: 0.3,
      ),
      leading: Icon(
        Icons.chat_bubble_outline,
        color: isSelected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        conversation.title == defaultConversationTitle
            ? 'drawer.new_conversation'.tr()
            : conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        _formatDate(conversation.updatedAt),
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: onDelete,
        tooltip: 'drawer.delete_tooltip'.tr(),
      ),
      onTap: onTap,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      final time = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      return 'drawer.date_today'.tr(namedArgs: {'time': time});
    } else if (diff.inDays == 1) {
      return 'drawer.date_yesterday'.tr();
    } else if (diff.inDays < 7) {
      return 'drawer.days_ago'.tr(namedArgs: {'days': diff.inDays.toString()});
    } else {
      return '${date.month}/${date.day}';
    }
  }
}
