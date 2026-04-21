import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                          label: 'routines.tools_read_only_badge'.tr(),
                          color: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
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
                      _MetaLine(
                        label: 'routines.notifications_label'.tr(),
                        value: routine.notifyOnCompletion
                            ? 'routines.notifications_on'.tr()
                            : 'routines.notifications_off'.tr(),
                      ),
                      _MetaLine(
                        label: 'routines.tools_label'.tr(),
                        value: routine.toolsEnabled
                            ? 'routines.tools_mode_read_only'.tr()
                            : 'routines.tools_mode_off'.tr(),
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
                  onViewOutput: run.output.trim().isEmpty
                      ? null
                      : () => _showTextViewer(
                          context,
                          title: 'routines.output_title'.tr(),
                          content: run.output,
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
        );
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
}

class _RunRecordCard extends StatelessWidget {
  const _RunRecordCard({
    required this.run,
    this.onViewOutput,
    this.onViewError,
  });

  final RoutineRunRecord run;
  final VoidCallback? onViewOutput;
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
                        : run.toolNames.join(', '),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(summaryText, style: theme.textTheme.bodyMedium),
            if (onViewOutput != null || onViewError != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onViewOutput != null)
                    OutlinedButton.icon(
                      onPressed: onViewOutput,
                      icon: const Icon(Icons.article_outlined),
                      label: Text('routines.view_output'.tr()),
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
