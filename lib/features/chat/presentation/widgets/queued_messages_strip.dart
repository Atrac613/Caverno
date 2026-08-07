import 'package:flutter/material.dart';

import '../providers/chat_state.dart';

class QueuedMessagesStrip extends StatelessWidget {
  const QueuedMessagesStrip({
    super.key,
    required this.messages,
    required this.onRemove,
    this.steeringMessages = const <QueuedChatMessage>[],
  });

  final List<QueuedChatMessage> messages;

  /// Interruptions already handed to the running turn, waiting for its next
  /// request to pick them up. Listed first because they act sooner than
  /// anything queued behind the turn.
  final List<QueuedChatMessage> steeringMessages;

  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && steeringMessages.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rows = <Widget>[
      for (final message in steeringMessages)
        _QueuedMessageRow(
          message: message,
          onRemove: onRemove,
          isSteering: true,
        ),
      for (final message in messages)
        _QueuedMessageRow(message: message, onRemove: onRemove),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            rows[index],
            if (index < rows.length - 1)
              Divider(
                height: 10,
                thickness: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
          ],
        ],
      ),
    );
  }
}

class _QueuedMessageRow extends StatelessWidget {
  const _QueuedMessageRow({
    required this.message,
    required this.onRemove,
    this.isSteering = false,
  });

  final QueuedChatMessage message;
  final bool isSteering;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final preview = _previewText(message);

    return Row(
      key: ValueKey(
        isSteering
            ? 'steering_message_${message.id}'
            : 'queued_message_${message.id}',
      ),
      children: [
        Icon(
          isSteering ? Icons.bolt : Icons.schedule_send,
          size: 18,
          color: isSteering ? colorScheme.tertiary : colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSteering
                ? colorScheme.tertiaryContainer
                : colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            isSteering ? 'Interrupting' : 'Queued',
            style: theme.textTheme.labelSmall?.copyWith(
              color: isSteering
                  ? colorScheme.onTertiaryContainer
                  : colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: isSteering
              ? 'Withdraw this interruption'
              : 'Remove queued message',
          onPressed: () => onRemove(message.id),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  String _previewText(QueuedChatMessage message) {
    final text = message.content.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (message.hasImage && text.isNotEmpty) {
      return 'Image - $text';
    }
    if (message.hasImage) {
      return 'Image message';
    }
    if (text.isEmpty) {
      return 'Queued message';
    }
    return text;
  }
}
