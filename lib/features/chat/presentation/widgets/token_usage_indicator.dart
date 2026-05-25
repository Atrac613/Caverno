import 'package:flutter/material.dart';

import '../../domain/services/conversation_compaction_service.dart';
import '../providers/chat_state.dart';

class TokenUsageIndicator extends StatelessWidget {
  const TokenUsageIndicator({
    super.key,
    required this.chatState,
    required this.model,
    required this.formatTokenCount,
  });

  final ChatState chatState;
  final String model;
  final String Function(int count) formatTokenCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pressureColor = switch (chatState.contextTokenPressureLevel) {
      ContextTokenPressureLevel.normal => colorScheme.primary,
      ContextTokenPressureLevel.warning => colorScheme.tertiary,
      ContextTokenPressureLevel.critical => colorScheme.error,
    };
    final usageTokenCount = chatState.estimatedPromptTokens > 0
        ? chatState.estimatedPromptTokens
        : chatState.totalTokens;
    final contextBudget =
        ConversationCompactionService.maxEstimatedPromptTokens;
    final usageValue = usageTokenCount / contextBudget;
    final progress = usageValue.clamp(0.0, 1.0).toDouble();
    final tooltip = _tooltipText(
      usageTokenCount: usageTokenCount,
      contextBudget: contextBudget,
    );

    return Tooltip(
      message: tooltip,
      child: Semantics(
        label: 'Token usage',
        value: '${(progress * 100).round()} percent',
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _compactModelLabel(model),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${formatTokenCount(usageTokenCount)}/${formatTokenCount(contextBudget)}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  strokeCap: StrokeCap.round,
                  backgroundColor: colorScheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
                  color: pressureColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _tooltipText({
    required int usageTokenCount,
    required int contextBudget,
  }) {
    final lines = [
      'Context estimate: ${formatTokenCount(usageTokenCount)} / ${formatTokenCount(contextBudget)}',
      'Prompt: ${formatTokenCount(chatState.promptTokens)}',
      'Completion: ${formatTokenCount(chatState.completionTokens)}',
      'Total: ${formatTokenCount(chatState.totalTokens)}',
    ];
    if (chatState.promptCompactionActive) {
      lines.add('Prompt compaction active');
    }
    return lines.join('\n');
  }

  String _compactModelLabel(String rawModel) {
    final leaf = rawModel.split('/').last.trim();
    if (leaf.isEmpty) {
      return 'Model';
    }

    var label = leaf
        .replaceFirst(
          RegExp(r'\.(gguf|bin|safetensors)$', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'q\d+(?:[_-]k)?(?:[_-]m)?', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .replaceAll(
          RegExp(r'\b(mlx|community|instruct|it)\b', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (label.isEmpty) {
      label = leaf;
    }

    final words = label.split(' ');
    return words.take(3).map(_formatModelWord).join(' ');
  }

  String _formatModelWord(String word) {
    if (word.isEmpty) {
      return word;
    }
    if (word == word.toUpperCase()) {
      return word;
    }
    return '${word[0].toUpperCase()}${word.substring(1)}';
  }
}
