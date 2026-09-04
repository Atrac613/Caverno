import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../mentions/mention_target.dart';

/// Mention completion list shown above the composer while the draft starts
/// with `@`.
///
/// Presentation only: the composer owns the selection state and decides what a
/// tap inserts.
class MessageInputMentionSuggestionList extends StatelessWidget {
  const MessageInputMentionSuggestionList({
    super.key,
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<MentionTarget> suggestions;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('mention-suggestions'),
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final target = suggestions[index];
          final selected = index == selectedIndex;
          return Material(
            color: selected
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            child: InkWell(
              key: ValueKey('mention-suggestion-${target.handle}'),
              onTap: () => onSelected(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 148,
                      child: Text(
                        '@${target.handle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: selected
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        target.descriptionKey.tr(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
