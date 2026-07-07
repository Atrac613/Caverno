import 'package:flutter/material.dart';

import '../../domain/services/context_surgery_observation_service.dart';
import '../../domain/services/conversation_compaction_service.dart';
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

/// A single category slice of the prompt payload, sized in estimated tokens.
class _ContextSlice {
  const _ContextSlice({
    required this.label,
    required this.tokens,
    required this.color,
    this.isFree = false,
  });

  final String label;
  final int tokens;
  final Color color;

  /// Free space is rendered with a neutral color and excluded from the
  /// "used" portion of the bar.
  final bool isFree;
}

/// Partitions the current prompt payload into non-overlapping categories so
/// they can be rendered as a segmented bar plus a per-row breakdown, mirroring
/// a `/context`-style view.
///
/// The observed `System prompt` section spans the whole system prompt string,
/// which already embeds the repo map / AGENTS.md / memory / plan sub-blocks, so
/// those are subtracted out to avoid double counting. `Messages` is the
/// residual between the (real, if available) used-token count and everything we
/// could attribute to a named section — dominated by conversation history and
/// also absorbing the estimate-vs-actual unit mismatch so the bar stays honest
/// to the API's reported total.
class _ContextBreakdown {
  const _ContextBreakdown({
    required this.slices,
    required this.usedTokens,
    required this.windowTokens,
  });

  final List<_ContextSlice> slices;
  final int usedTokens;
  final int? windowTokens;

  /// Categorical palette chosen to stay legible on both light and dark
  /// surfaces. Free space falls back to a neutral color from the theme.
  static const Color _systemPromptColor = Color(0xFF6366F1); // indigo
  static const Color _projectContextColor = Color(0xFF14B8A6); // teal
  static const Color _memoryColor = Color(0xFFF59E0B); // amber
  static const Color _planWorkflowColor = Color(0xFFEC4899); // pink
  static const Color _toolResultsColor = Color(0xFF0EA5E9); // sky
  static const Color _messagesColor = Color(0xFF22C55E); // green

  static _ContextBreakdown from({
    required ChatState chatState,
    required int usageTokenCount,
    required int? contextWindowTokens,
    required Color freeSpaceColor,
  }) {
    final snapshot = chatState.contextSurgerySnapshot;

    int tokensOf(ContextSurgeryBlockKind kind) =>
        snapshot.section(kind)?.estimatedTokens ?? 0;

    final systemWhole = tokensOf(ContextSurgeryBlockKind.systemPrompt);
    final repoMap = tokensOf(ContextSurgeryBlockKind.repoMap);
    final agents = tokensOf(ContextSurgeryBlockKind.agentsMarkdown);
    final memory = tokensOf(ContextSurgeryBlockKind.memory);
    final plan = tokensOf(ContextSurgeryBlockKind.planDocument);
    final workflow = tokensOf(ContextSurgeryBlockKind.workflowProjection);

    // Sub-blocks are contained within the system prompt string, so the base
    // instructions are the whole prompt minus those embedded sections.
    final embeddedSubBlocks = repoMap + agents + memory + plan + workflow;
    final systemBase = (systemWhole - embeddedSubBlocks).clamp(0, systemWhole);
    final projectContext = repoMap + agents;
    final planWorkflow = plan + workflow;
    final toolResults =
        tokensOf(ContextSurgeryBlockKind.toolResult) +
        tokensOf(ContextSurgeryBlockKind.fileReadToolResult) +
        tokensOf(ContextSurgeryBlockKind.fileSearchToolResult) +
        tokensOf(ContextSurgeryBlockKind.commandToolResult) +
        tokensOf(ContextSurgeryBlockKind.sideEffectToolResult);

    final attributed =
        systemBase + projectContext + memory + planWorkflow + toolResults;
    // Never let the named sections exceed the reported total; the residual is
    // the conversation history plus any unit-mismatch slack.
    final used = usageTokenCount > attributed ? usageTokenCount : attributed;
    final messages = used - attributed;

    final slices = <_ContextSlice>[
      if (systemBase > 0)
        _ContextSlice(
          label: 'System prompt',
          tokens: systemBase,
          color: _systemPromptColor,
        ),
      if (projectContext > 0)
        _ContextSlice(
          label: 'Project context',
          tokens: projectContext,
          color: _projectContextColor,
        ),
      if (memory > 0)
        _ContextSlice(label: 'Memory', tokens: memory, color: _memoryColor),
      if (planWorkflow > 0)
        _ContextSlice(
          label: 'Plan / Workflow',
          tokens: planWorkflow,
          color: _planWorkflowColor,
        ),
      if (toolResults > 0)
        _ContextSlice(
          label: 'Tool results',
          tokens: toolResults,
          color: _toolResultsColor,
        ),
      _ContextSlice(
        label: 'Messages',
        tokens: messages,
        color: _messagesColor,
      ),
    ];

    final window = contextWindowTokens != null && contextWindowTokens > 0
        ? contextWindowTokens
        : null;
    if (window != null) {
      final free = (window - used).clamp(0, window);
      slices.add(
        _ContextSlice(
          label: 'Free space',
          tokens: free,
          color: freeSpaceColor,
          isFree: true,
        ),
      );
    }

    return _ContextBreakdown(
      slices: slices,
      usedTokens: used,
      windowTokens: window,
    );
  }

  /// Denominator used for per-row percentages: the context window when known,
  /// otherwise the used-token total.
  int get percentBasis => windowTokens ?? usedTokens;
}

class _ContextWindowPopover extends StatelessWidget {
  const _ContextWindowPopover({
    required this.chatState,
    required this.usageTokenCount,
    required this.contextWindowTokens,
    required this.progress,
    required this.formatTokenCount,
  });

  final ChatState chatState;
  final int usageTokenCount;
  final int? contextWindowTokens;
  final double? progress;
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

    final breakdown = _ContextBreakdown.from(
      chatState: chatState,
      usageTokenCount: usageTokenCount,
      contextWindowTokens: contextWindowTokens,
      freeSpaceColor: colorScheme.outlineVariant.withValues(alpha: 0.6),
    );

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
              _SegmentedContextBar(
                slices: breakdown.slices,
                trackColor: colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
              if (contextWindowTokens == null) ...[
                const SizedBox(height: 10),
                Text(
                  'Context window size unavailable from /models; '
                  'showing usage only.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Divider(color: colorScheme.outlineVariant, height: 1),
              const SizedBox(height: 10),
              for (final slice in breakdown.slices) ...[
                _BreakdownRow(
                  slice: slice,
                  percentBasis: breakdown.percentBasis,
                  formatTokenCount: formatTokenCount,
                ),
                const SizedBox(height: 6),
              ],
              if (chatState.contextSurgerySnapshot.staleToolResultCandidateCount >
                  0) ...[
                const SizedBox(height: 4),
                Text(
                  'Stale tool candidates '
                  '(${chatState.contextSurgerySnapshot.staleToolResultCandidateCount}) · '
                  '${formatTokenCount(chatState.contextSurgerySnapshot.staleToolResultEstimatedTokens)} reclaimable',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
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
}

/// Horizontal stacked bar where each segment's width is proportional to its
/// slice's estimated tokens.
class _SegmentedContextBar extends StatelessWidget {
  const _SegmentedContextBar({required this.slices, required this.trackColor});

  final List<_ContextSlice> slices;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    final segments = slices
        .where((slice) => slice.tokens > 0)
        .toList(growable: false);

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 8,
        child: segments.isEmpty
            ? ColoredBox(color: trackColor)
            : Row(
                children: [
                  for (final segment in segments)
                    Expanded(
                      flex: segment.tokens,
                      child: ColoredBox(color: segment.color),
                    ),
                ],
              ),
      ),
    );
  }
}

/// A single "● Label ........ 12.3k  38%" row in the breakdown list.
class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.slice,
    required this.percentBasis,
    required this.formatTokenCount,
  });

  final _ContextSlice slice;
  final int percentBasis;
  final String Function(int count) formatTokenCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelColor = slice.isFree
        ? colorScheme.onSurfaceVariant
        : colorScheme.onSurface;

    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: slice.color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            slice.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: labelColor),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          formatTokenCount(slice.tokens),
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            _percentLabel(),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  String _percentLabel() {
    if (percentBasis <= 0) {
      return '';
    }
    final percent = slice.tokens / percentBasis * 100;
    if (percent > 0 && percent < 1) {
      return '<1%';
    }
    return '${percent.round()}%';
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
