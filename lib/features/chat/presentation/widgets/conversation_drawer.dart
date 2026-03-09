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
            // ヘッダー
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '会話履歴',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (conversationsState.conversations.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      tooltip: '履歴を一括削除',
                      onPressed: () {
                        _showDeleteAllDialog(context, notifier);
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: '新しい会話',
                    onPressed: () {
                      notifier.createNewConversation();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 会話一覧
            Expanded(
              child: conversationsState.conversations.isEmpty
                  ? const Center(
                      child: Text(
                        '会話がありません',
                        style: TextStyle(color: Colors.grey),
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
        title: const Text('会話を削除'),
        content: Text('「${conversation.title}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              notifier.deleteConversation(conversation.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
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
        title: const Text('会話履歴を一括削除'),
        content: const Text('すべての会話履歴を削除しますか？この操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('すべて削除'),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    await notifier.deleteAllConversations();
    if (!context.mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('会話履歴をすべて削除しました')));
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
        conversation.title,
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
        tooltip: '削除',
      ),
      onTap: onTap,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '今日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return '昨日';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}日前';
    } else {
      return '${date.month}/${date.day}';
    }
  }
}
