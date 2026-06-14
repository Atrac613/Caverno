import 'package:flutter/material.dart';

import '../../domain/services/conversation_compaction_service.dart';
import '../../domain/services/context_surgery_observation_service.dart';
import '../providers/chat_state.dart';

class TokenUsageIndicator extends StatelessWidget {
  const TokenUsageIndicator({
    super.key,
    required this.chatState,
    required this.model,
    required this.contextWindowTokens,
    required this.formatTokenCount,
  });

  final ChatState chatState;
  final String model;
  final int? contextWindowTokens;
  final String Function(int count) formatTokenCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final usageTokenCount = _contextUsageTokenCount();
    final progress = _contextWindowProgress(usageTokenCount);
    final progressColor = _progressColor(colorScheme, progress);
    final tooltip = _tooltipText(usageTokenCount: usageTokenCount);

    return Container(
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
          const SizedBox(width: 8),
          MenuAnchor(
            alignmentOffset: const Offset(-320, -8),
            style: const MenuStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
              elevation: WidgetStatePropertyAll(0),
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
              minimumSize: WidgetStatePropertyAll(Size.zero),
            ),
            menuChildren: [
              _ContextWindowPopover(
                chatState: chatState,
                usageTokenCount: usageTokenCount,
                contextWindowTokens: contextWindowTokens,
                progress: progress,
                progressColor: progressColor,
                formatTokenCount: formatTokenCount,
              ),
            ],
            builder: (context, controller, child) {
              return Tooltip(
                message: tooltip,
                child: Semantics(
                  button: true,
                  label: 'Context window',
                  value: progress == null
                      ? 'Unknown'
                      : '${(progress * 100).round()} percent',
                  child: InkResponse(
                    radius: 18,
                    onTap: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        value: progress ?? 0,
                        strokeWidth: 3,
                        strokeCap: StrokeCap.round,
                        backgroundColor: colorScheme.outlineVariant.withValues(
                          alpha: 0.45,
                        ),
                        color: progressColor,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  double? _contextWindowProgress(int usageTokenCount) {
    final budget = contextWindowTokens;
    if (budget == null || budget <= 0) {
      return null;
    }
    return (usageTokenCount / budget).clamp(0.0, 1.0).toDouble();
  }

  int _contextUsageTokenCount() {
    if (chatState.promptTokens > 0) {
      return chatState.promptTokens;
    }
    if (chatState.estimatedPromptTokens > 0) {
      return chatState.estimatedPromptTokens;
    }
    final estimatedFromMessages =
        ConversationCompactionService.estimatePromptTokens(chatState.messages);
    if (estimatedFromMessages > 0) {
      return estimatedFromMessages;
    }
    return chatState.totalTokens;
  }

  Color _progressColor(ColorScheme colorScheme, double? progress) {
    if (progress == null) {
      return colorScheme.outline;
    }
    if (progress >= 0.95) {
      return colorScheme.error;
    }
    if (progress >= 0.8) {
      return colorScheme.tertiary;
    }
    return colorScheme.primary;
  }

  String _tooltipText({required int usageTokenCount}) {
    final lines = [
      if (contextWindowTokens == null)
        'Context window: Unknown'
      else
        'Context window: ${formatTokenCount(usageTokenCount)} / ${formatTokenCount(contextWindowTokens!)}',
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

class _ContextWindowPopover extends StatelessWidget {
  const _ContextWindowPopover({
    required this.chatState,
    required this.usageTokenCount,
    required this.contextWindowTokens,
    required this.progress,
    required this.progressColor,
    required this.formatTokenCount,
  });

  final ChatState chatState;
  final int usageTokenCount;
  final int? contextWindowTokens;
  final double? progress;
  final Color progressColor;
  final String Function(int count) formatTokenCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final contextWindowTokens = this.contextWindowTokens;
    final progress = this.progress;
    final contextValueText = contextWindowTokens == null || progress == null
        ? 'Unknown'
        : '${formatTokenCount(usageTokenCount)} / '
              '${formatTokenCount(contextWindowTokens)} '
              '(${(progress * 100).round()}%)';

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 360),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Context window',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    contextValueText,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress ?? 0,
                  minHeight: 7,
                  color: progressColor,
                  backgroundColor: colorScheme.outlineVariant.withValues(
                    alpha: 0.45,
                  ),
                ),
              ),
              if (contextWindowTokens == null) ...[
                const SizedBox(height: 10),
                Text(
                  'Context metadata unavailable from /models.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Divider(color: colorScheme.outlineVariant, height: 1),
              const SizedBox(height: 10),
              _TokenDetailRow(
                label: 'Prompt',
                value: formatTokenCount(chatState.promptTokens),
              ),
              const SizedBox(height: 6),
              _TokenDetailRow(
                label: 'Completion',
                value: formatTokenCount(chatState.completionTokens),
              ),
              const SizedBox(height: 6),
              _TokenDetailRow(
                label: 'Total',
                value: formatTokenCount(chatState.totalTokens),
              ),
              if (chatState.contextSurgerySnapshot.hasData) ...[
                const SizedBox(height: 12),
                Divider(color: colorScheme.outlineVariant, height: 1),
                const SizedBox(height: 10),
                Text(
                  'Context sections',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                for (final section
                    in chatState.contextSurgerySnapshot.sections) ...[
                  _TokenDetailRow(
                    label: _contextSectionLabel(section),
                    value: formatTokenCount(section.estimatedTokens),
                  ),
                  const SizedBox(height: 6),
                ],
                if (chatState
                        .contextSurgerySnapshot
                        .staleToolResultCandidateCount >
                    0)
                  _TokenDetailRow(
                    label:
                        'Stale tool candidates '
                        '(${chatState.contextSurgerySnapshot.staleToolResultCandidateCount})',
                    value: formatTokenCount(
                      chatState
                          .contextSurgerySnapshot
                          .staleToolResultEstimatedTokens,
                    ),
                  ),
              ],
              if (chatState.promptCompactionActive) ...[
                const SizedBox(height: 8),
                Text(
                  'Prompt compaction active',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _contextSectionLabel(ContextSurgerySectionSummary section) {
    if (section.blockCount <= 1) {
      return section.label;
    }
    return '${section.label} (${section.blockCount})';
  }
}

class _TokenDetailRow extends StatelessWidget {
  const _TokenDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
