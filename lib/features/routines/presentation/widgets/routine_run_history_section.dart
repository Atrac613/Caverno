import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../chat/presentation/widgets/parsed_content_view.dart';
import '../../domain/entities/routine.dart';

/// Displays the stored execution history for one routine.
class RoutineRunHistorySection extends StatelessWidget {
  const RoutineRunHistorySection({super.key, required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'routines.history_title'.tr(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (routine.runs.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'routines.history_empty'.tr(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
        else
          ...routine.runs.map(
            (run) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RunRecordCard(
                run: run,
                onViewTranscript:
                    run.output.trim().isEmpty && run.toolCalls.isEmpty
                    ? null
                    : () => _showRunTranscriptViewer(
                        context,
                        routine: routine,
                        run: run,
                      ),
                onViewError: run.error.trim().isEmpty
                    ? null
                    : () => _showTextViewer(
                        context,
                        title: 'routines.error_title'.tr(),
                        content: run.error,
                      ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showTextViewer(
    BuildContext context, {
    required String title,
    required String content,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('common.close'.tr()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    content.trim(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRunTranscriptViewer(
    BuildContext context, {
    required Routine routine,
    required RoutineRunRecord run,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.86;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'routines.transcript_title'.tr(),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('common.close'.tr()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        _TranscriptBlock(
                          label: 'routines.transcript_user'.tr(),
                          content: routine.trimmedPrompt,
                          role: _TranscriptRole.user,
                        ),
                        for (final toolCall in run.toolCalls)
                          _TranscriptBlock(
                            label: 'routines.transcript_tool'.tr(
                              namedArgs: {'name': toolCall.name},
                            ),
                            content: [
                              if (toolCall.arguments.trim().isNotEmpty)
                                '${'routines.tool_arguments_label'.tr()}\n${toolCall.arguments.trim()}',
                              if (toolCall.result.trim().isNotEmpty)
                                '${'routines.tool_result_label'.tr()}\n${toolCall.result.trim()}',
                            ].join('\n\n'),
                            role: _TranscriptRole.tool,
                          ),
                        if (run.output.trim().isNotEmpty)
                          _TranscriptBlock(
                            label: 'routines.transcript_assistant'.tr(),
                            content: run.output.trim(),
                            role: _TranscriptRole.assistant,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _TranscriptRole { user, tool, assistant }

class _TranscriptBlock extends StatelessWidget {
  const _TranscriptBlock({
    required this.label,
    required this.content,
    required this.role,
  });

  final String label;
  final String content;
  final _TranscriptRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = role == _TranscriptRole.user;
    final isTool = role == _TranscriptRole.tool;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = screenWidth < 720 ? screenWidth * 0.84 : 680.0;
    final backgroundColor = isUser
        ? theme.colorScheme.primary
        : isTool
        ? theme.colorScheme.surfaceContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foregroundColor = isUser
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final labelColor = isUser
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.78)
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16).copyWith(
                bottomRight: isUser ? const Radius.circular(4) : null,
                bottomLeft: !isUser ? const Radius.circular(4) : null,
              ),
              border: isTool
                  ? Border.all(color: theme.colorScheme.outlineVariant)
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: labelColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (role == _TranscriptRole.assistant)
                    ParsedContentView(
                      content: content,
                      textColor: foregroundColor,
                    )
                  else
                    SelectableText(
                      content,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foregroundColor,
                        height: 1.35,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RunRecordCard extends StatelessWidget {
  const _RunRecordCard({
    required this.run,
    this.onViewTranscript,
    this.onViewError,
  });

  final RoutineRunRecord run;
  final VoidCallback? onViewTranscript;
  final VoidCallback? onViewError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = run.preview.trim();
    final summaryText = preview.isEmpty
        ? (run.isSuccessful
              ? 'routines.no_result_preview'.tr()
              : (run.error.trim().isEmpty
                    ? 'common.unknown_error'.tr()
                    : run.error.trim()))
        : preview;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    DateFormat('yyyy/MM/dd HH:mm:ss').format(run.startedAt),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  _formatDuration(run.effectiveDurationMs),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HistoryStatusChip(
                  label: run.isSuccessful
                      ? 'routines.status_completed'.tr()
                      : 'routines.status_failed'.tr(),
                  color: run.isSuccessful
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.errorContainer,
                ),
                _HistoryStatusChip(
                  label: switch (run.trigger) {
                    RoutineRunTrigger.manual => 'routines.trigger_manual'.tr(),
                    RoutineRunTrigger.scheduled =>
                      'routines.trigger_scheduled'.tr(),
                  },
                  color: theme.colorScheme.secondaryContainer,
                ),
                if (run.usedTools)
                  _HistoryStatusChip(
                    label: 'routines.tools_used_badge'.tr(
                      namedArgs: {'count': run.toolCallCount.toString()},
                    ),
                    color: theme.colorScheme.tertiaryContainer,
                  ),
                if (run.usedPlan)
                  _HistoryStatusChip(
                    label: 'routines.plan_used_badge'.tr(),
                    color: theme.colorScheme.primaryContainer,
                  ),
                if (run.deliveryStatus != RoutineDeliveryStatus.notRequested)
                  _HistoryStatusChip(
                    label: _deliveryStatusLabel(run),
                    color: _deliveryStatusColor(theme, run.deliveryStatus),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _HistoryMetaLine(
                  label: 'routines.started_label'.tr(),
                  value: DateFormat(
                    'yyyy/MM/dd HH:mm:ss',
                  ).format(run.startedAt),
                ),
                _HistoryMetaLine(
                  label: 'routines.finished_label'.tr(),
                  value: DateFormat(
                    'yyyy/MM/dd HH:mm:ss',
                  ).format(run.finishedAt),
                ),
                if (run.usedTools)
                  _HistoryMetaLine(
                    label: 'routines.tools_label'.tr(),
                    value: run.toolNames.isEmpty
                        ? 'routines.tools_mode_read_only'.tr()
                        : run.toolDisplayNames.join(', '),
                  ),
                if (run.deliveryStatus != RoutineDeliveryStatus.notRequested)
                  _HistoryMetaLine(
                    label: 'routines.delivery_label'.tr(),
                    value: _deliveryStatusLabel(run),
                  ),
                if (run.deliveredAt != null)
                  _HistoryMetaLine(
                    label: 'routines.delivered_at_label'.tr(),
                    value: DateFormat(
                      'yyyy/MM/dd HH:mm:ss',
                    ).format(run.deliveredAt!),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(summaryText, style: theme.textTheme.bodyMedium),
            if (!run.isSuccessful && run.failureAcknowledged) ...[
              const SizedBox(height: 12),
              Text(
                'routines.failure_reviewed_hint'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (run.deliveryMessage.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                run.deliveryMessage.trim(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (onViewTranscript != null || onViewError != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onViewTranscript != null)
                    OutlinedButton.icon(
                      onPressed: onViewTranscript,
                      icon: const Icon(Icons.article_outlined),
                      label: Text('routines.view_transcript'.tr()),
                    ),
                  if (onViewError != null)
                    OutlinedButton.icon(
                      onPressed: onViewError,
                      icon: const Icon(Icons.error_outline),
                      label: Text('routines.view_error'.tr()),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(int durationMs) {
    if (durationMs < 1000) {
      return '${durationMs}ms';
    }
    final seconds = durationMs ~/ 1000;
    if (seconds < 60) {
      final remainingMs = (durationMs % 1000) ~/ 100;
      return remainingMs == 0
          ? '$seconds'
                's'
          : '$seconds.${remainingMs}s';
    }
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes}m ${remainingSeconds.toString().padLeft(2, '0')}s';
  }

  String _deliveryStatusLabel(RoutineRunRecord run) {
    return switch (run.deliveryStatus) {
      RoutineDeliveryStatus.notRequested =>
        'routines.delivery_not_requested'.tr(),
      RoutineDeliveryStatus.skipped => 'routines.delivery_skipped'.tr(),
      RoutineDeliveryStatus.delivered => 'routines.delivery_delivered'.tr(),
      RoutineDeliveryStatus.failed => 'routines.delivery_failed'.tr(),
    };
  }

  Color _deliveryStatusColor(ThemeData theme, RoutineDeliveryStatus status) {
    return switch (status) {
      RoutineDeliveryStatus.notRequested =>
        theme.colorScheme.surfaceContainerHighest,
      RoutineDeliveryStatus.skipped =>
        theme.colorScheme.surfaceContainerHighest,
      RoutineDeliveryStatus.delivered => theme.colorScheme.primaryContainer,
      RoutineDeliveryStatus.failed => theme.colorScheme.errorContainer,
    };
  }
}

class _HistoryStatusChip extends StatelessWidget {
  const _HistoryStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _HistoryMetaLine extends StatelessWidget {
  const _HistoryMetaLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}
