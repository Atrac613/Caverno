import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/presentation/widgets/parsed_content_view.dart';
import '../../domain/entities/routine.dart';
import '../../domain/services/routine_schedule_service.dart';
import '../providers/routines_notifier.dart';
import '../widgets/routine_editor_sheet.dart';

enum _RoutineDetailAction { duplicate, clearHistory, delete }

class RoutineDetailPage extends ConsumerWidget {
  const RoutineDetailPage({super.key, required this.routineId});

  final String routineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routinesState = ref.watch(routinesNotifierProvider);
    final routine = ref
        .read(routinesNotifierProvider.notifier)
        .findRoutine(routineId);
    final isRunning = routinesState.isRunning(routineId);
    final latestRun = routine?.latestRun;
    final requiresFailureAcknowledgement =
        latestRun?.requiresAttention ?? false;

    if (routine == null) {
      return Scaffold(
        appBar: AppBar(title: Text('routines.title'.tr())),
        body: Center(
          child: Text(
            'routines.not_found'.tr(),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          routine.trimmedName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          PopupMenuButton<_RoutineDetailAction>(
            onSelected: (action) {
              switch (action) {
                case _RoutineDetailAction.duplicate:
                  _duplicateRoutine(context, ref, routine);
                  break;
                case _RoutineDetailAction.clearHistory:
                  _confirmClearHistory(context, ref, routine);
                  break;
                case _RoutineDetailAction.delete:
                  _confirmDelete(context, ref, routine);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _RoutineDetailAction.duplicate,
                child: Text('routines.duplicate'.tr()),
              ),
              PopupMenuItem(
                value: _RoutineDetailAction.clearHistory,
                child: Text('routines.clear_history'.tr()),
              ),
              PopupMenuItem(
                value: _RoutineDetailAction.delete,
                child: Text('common.delete'.tr()),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusChip(
                        label: routine.enabled
                            ? 'routines.enabled_badge'.tr()
                            : 'routines.disabled_badge'.tr(),
                        color: routine.enabled
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                      ),
                      if (RoutineScheduleService.isDue(routine) && !isRunning)
                        _StatusChip(
                          label: 'routines.due_badge'.tr(),
                          color: Theme.of(
                            context,
                          ).colorScheme.tertiaryContainer,
                        ),
                      if (isRunning)
                        _StatusChip(
                          label: 'routines.running_badge'.tr(),
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                        ),
                      if (routine.toolsEnabled)
                        _StatusChip(
                          label: routine.hasWorkspaceWriteAccess
                              ? 'routines.tools_workspace_write_badge'.tr()
                              : 'routines.tools_read_only_badge'.tr(),
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                        ),
                      if (routine.postsToGoogleChat)
                        _StatusChip(
                          label: 'routines.google_chat_badge'.tr(),
                          color: Theme.of(
                            context,
                          ).colorScheme.tertiaryContainer,
                        ),
                      if (routine.hasPendingPlanEdits)
                        _StatusChip(
                          label: 'routines.plan_draft_badge'.tr(),
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                        )
                      else if (routine.hasStaleApprovedPlan)
                        _StatusChip(
                          label: 'routines.plan_stale_badge'.tr(),
                          color: Theme.of(context).colorScheme.errorContainer,
                        )
                      else if (routine.isApprovedPlanFresh)
                        _StatusChip(
                          label: 'routines.plan_approved_badge'.tr(),
                          color: Theme.of(context).colorScheme.primaryContainer,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'routines.prompt_label'.tr(),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    routine.trimmedPrompt,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _MetaLine(
                        label: 'routines.schedule_label'.tr(),
                        value: _formatSchedule(routine),
                      ),
                      _MetaLine(
                        label: 'routines.next_run_label'.tr(),
                        value: _formatNextRun(context, routine),
                      ),
                      _MetaLine(
                        label: 'routines.last_run_label'.tr(),
                        value: _formatLastRun(context, routine),
                      ),
                      if (routine.consecutiveFailureCount > 0)
                        _MetaLine(
                          label: 'routines.consecutive_failures_label'.tr(),
                          value: routine.consecutiveFailureCount.toString(),
                        ),
                      _MetaLine(
                        label: 'routines.notifications_label'.tr(),
                        value: routine.notifyOnCompletion
                            ? 'routines.notifications_on'.tr()
                            : 'routines.notifications_off'.tr(),
                      ),
                      _MetaLine(
                        label: 'routines.tools_label'.tr(),
                        value: routine.toolsEnabled
                            ? (routine.hasWorkspaceWriteAccess
                                  ? 'routines.tools_mode_workspace_writes'.tr()
                                  : 'routines.tools_mode_read_only'.tr())
                            : 'routines.tools_mode_off'.tr(),
                      ),
                      if (routine.toolsEnabled && routine.hasWorkspaceDirectory)
                        _MetaLine(
                          label: 'routines.workspace_directory_label'.tr(),
                          value: routine.trimmedWorkspaceDirectory,
                        ),
                      _MetaLine(
                        label: 'routines.completion_action_label'.tr(),
                        value: _formatCompletionAction(context, routine),
                      ),
                      if (routine.effectivePlanArtifact.hasContent)
                        _MetaLine(
                          label: 'routines.plan_status_label'.tr(),
                          value: _formatPlanStatus(routine),
                        ),
                      if (routine.postsToGoogleChat)
                        _MetaLine(
                          label: 'routines.google_chat_rule_label'.tr(),
                          value: _formatGoogleChatRule(context, routine),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: isRunning
                            ? null
                            : () => _runRoutine(context, ref, routine),
                        icon: const Icon(Icons.play_arrow),
                        label: Text('routines.run_now'.tr()),
                      ),
                      OutlinedButton.icon(
                        onPressed: isRunning
                            ? null
                            : () => _openEditor(context, ref, routine),
                        icon: const Icon(Icons.edit_outlined),
                        label: Text('routines.edit'.tr()),
                      ),
                      if (requiresFailureAcknowledgement)
                        OutlinedButton.icon(
                          onPressed: isRunning
                              ? null
                              : () => _acknowledgeLatestFailure(
                                  context,
                                  ref,
                                  routine,
                                ),
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text('routines.acknowledge_failure'.tr()),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
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
      ),
    );
  }

  String _formatSchedule(Routine routine) {
    final value = RoutineScheduleService.normalizeIntervalValue(
      routine.intervalValue,
    );
    final unit = switch (routine.intervalUnit) {
      RoutineIntervalUnit.minutes =>
        value == 1 ? 'routines.unit_minute'.tr() : 'routines.unit_minutes'.tr(),
      RoutineIntervalUnit.hours =>
        value == 1 ? 'routines.unit_hour'.tr() : 'routines.unit_hours'.tr(),
      RoutineIntervalUnit.days =>
        value == 1 ? 'routines.unit_day'.tr() : 'routines.unit_days'.tr(),
    };
    return 'routines.every_interval'.tr(
      namedArgs: {'value': value.toString(), 'unit': unit},
    );
  }

  String _formatNextRun(BuildContext context, Routine routine) {
    if (!routine.enabled) {
      return 'routines.disabled_value'.tr();
    }
    if (RoutineScheduleService.isDue(routine)) {
      return 'routines.due_now_value'.tr();
    }
    final nextRunAt = routine.nextRunAt;
    if (nextRunAt == null) {
      return 'common.none'.tr();
    }
    return DateFormat('yyyy/MM/dd HH:mm').format(nextRunAt);
  }

  String _formatLastRun(BuildContext context, Routine routine) {
    final lastRunAt = routine.lastRunAt;
    if (lastRunAt == null) {
      return 'routines.never_value'.tr();
    }
    return DateFormat('yyyy/MM/dd HH:mm').format(lastRunAt);
  }

  Future<void> _runRoutine(
    BuildContext context,
    WidgetRef ref,
    Routine routine,
  ) async {
    final runRecord = await ref
        .read(routinesNotifierProvider.notifier)
        .runRoutineNow(routine.id);
    if (!context.mounted || runRecord == null) {
      return;
    }

    final message = runRecord.isSuccessful
        ? 'routines.run_now_completed'.tr(
            namedArgs: {'name': routine.trimmedName},
          )
        : 'routines.run_now_failed'.tr(
            namedArgs: {'name': routine.trimmedName},
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _acknowledgeLatestFailure(
    BuildContext context,
    WidgetRef ref,
    Routine routine,
  ) async {
    await ref
        .read(routinesNotifierProvider.notifier)
        .acknowledgeLatestFailure(routine.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('routines.acknowledge_failure_done'.tr())),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    Routine routine,
  ) async {
    final result = await showModalBottomSheet<RoutineEditorResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => RoutineEditorSheet(initialRoutine: routine),
    );

    if (result == null) {
      return;
    }

    await ref
        .read(routinesNotifierProvider.notifier)
        .updateRoutine(
          routineId: routine.id,
          name: result.name,
          prompt: result.prompt,
          intervalValue: result.intervalValue,
          intervalUnit: result.intervalUnit,
          enabled: result.enabled,
          notifyOnCompletion: result.notifyOnCompletion,
          toolsEnabled: result.toolsEnabled,
          completionAction: result.completionAction,
          googleChatRule: result.googleChatRule,
          workspaceDirectory: result.workspaceDirectory,
          allowWorkspaceWrites: result.allowWorkspaceWrites,
        );
  }

  String _formatCompletionAction(BuildContext context, Routine routine) {
    return switch (routine.completionAction) {
      RoutineCompletionAction.none => 'routines.completion_action_none'.tr(),
      RoutineCompletionAction.googleChat =>
        'routines.completion_action_google_chat'.tr(),
      RoutineCompletionAction.promptGoogleChat =>
        'routines.completion_action_prompt_google_chat'.tr(),
    };
  }

  String _formatGoogleChatRule(BuildContext context, Routine routine) {
    return switch (routine.googleChatRule) {
      RoutineGoogleChatRule.onSuccess =>
        'routines.google_chat_rule_on_success'.tr(),
      RoutineGoogleChatRule.onFailure =>
        'routines.google_chat_rule_on_failure'.tr(),
      RoutineGoogleChatRule.always => 'routines.google_chat_rule_always'.tr(),
    };
  }

  String _formatPlanStatus(Routine routine) {
    if (routine.hasPendingPlanEdits) {
      return 'routines.plan_status_draft'.tr();
    }
    if (routine.hasStaleApprovedPlan) {
      return 'routines.plan_status_stale'.tr();
    }
    if (routine.isApprovedPlanFresh) {
      return 'routines.plan_status_approved'.tr();
    }
    return 'routines.plan_status_unapproved'.tr();
  }

  Future<void> _duplicateRoutine(
    BuildContext context,
    WidgetRef ref,
    Routine routine,
  ) async {
    final duplicatedRoutine = await ref
        .read(routinesNotifierProvider.notifier)
        .duplicateRoutine(
          routineId: routine.id,
          duplicatedName: 'routines.duplicate_name'.tr(
            namedArgs: {'name': routine.trimmedName},
          ),
        );
    if (!context.mounted || duplicatedRoutine == null) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('routines.duplicate_done'.tr())));
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    WidgetRef ref,
    Routine routine,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('routines.clear_history_title'.tr()),
        content: Text(
          'routines.clear_history_confirm'.tr(
            namedArgs: {'name': routine.trimmedName},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('routines.clear_history'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await ref
        .read(routinesNotifierProvider.notifier)
        .clearRunHistory(routine.id);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('routines.clear_history_done'.tr())));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Routine routine,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('routines.delete_title'.tr()),
        content: Text(
          'routines.delete_confirm'.tr(
            namedArgs: {'name': routine.trimmedName},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    await ref.read(routinesNotifierProvider.notifier).deleteRoutine(routine.id);
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('routines.delete_done'.tr())));
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
                _StatusChip(
                  label: run.isSuccessful
                      ? 'routines.status_completed'.tr()
                      : 'routines.status_failed'.tr(),
                  color: run.isSuccessful
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.errorContainer,
                ),
                _StatusChip(
                  label: switch (run.trigger) {
                    RoutineRunTrigger.manual => 'routines.trigger_manual'.tr(),
                    RoutineRunTrigger.scheduled =>
                      'routines.trigger_scheduled'.tr(),
                  },
                  color: theme.colorScheme.secondaryContainer,
                ),
                if (run.usedTools)
                  _StatusChip(
                    label: 'routines.tools_used_badge'.tr(
                      namedArgs: {'count': run.toolCallCount.toString()},
                    ),
                    color: theme.colorScheme.tertiaryContainer,
                  ),
                if (run.deliveryStatus != RoutineDeliveryStatus.notRequested)
                  _StatusChip(
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
                _MetaLine(
                  label: 'routines.started_label'.tr(),
                  value: DateFormat(
                    'yyyy/MM/dd HH:mm:ss',
                  ).format(run.startedAt),
                ),
                _MetaLine(
                  label: 'routines.finished_label'.tr(),
                  value: DateFormat(
                    'yyyy/MM/dd HH:mm:ss',
                  ).format(run.finishedAt),
                ),
                if (run.usedTools)
                  _MetaLine(
                    label: 'routines.tools_label'.tr(),
                    value: run.toolNames.isEmpty
                        ? 'routines.tools_mode_read_only'.tr()
                        : run.toolDisplayNames.join(', '),
                  ),
                if (run.deliveryStatus != RoutineDeliveryStatus.notRequested)
                  _MetaLine(
                    label: 'routines.delivery_label'.tr(),
                    value: _deliveryStatusLabel(run),
                  ),
                if (run.deliveredAt != null)
                  _MetaLine(
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

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

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});

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
