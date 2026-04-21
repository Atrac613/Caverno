import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/routine.dart';
import '../../domain/services/routine_schedule_service.dart';
import '../models/routine_home_snapshot.dart';
import 'routine_detail_page.dart';
import '../providers/routines_notifier.dart';
import '../widgets/routine_editor_sheet.dart';

class RoutinesHomePage extends ConsumerWidget {
  const RoutinesHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(routinesNotifierProvider);
    final snapshot = RoutineHomeSnapshotBuilder.build(
      routines: state.routines,
      runningRoutineIds: state.runningRoutineIds,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'routines.title'.tr(),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'routines.subtitle'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryChip(
                      label: 'routines.summary_enabled'.tr(),
                      value: snapshot.enabledCount.toString(),
                    ),
                    _SummaryChip(
                      label: 'routines.summary_due'.tr(),
                      value: snapshot.dueCount.toString(),
                    ),
                    _SummaryChip(
                      label: 'routines.summary_attention'.tr(),
                      value: snapshot.attentionCount.toString(),
                    ),
                    _SummaryChip(
                      label: 'routines.summary_running'.tr(),
                      value: snapshot.runningCount.toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _openEditor(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text('routines.create_cta'.tr()),
                ),
                if (snapshot.dueCount > 0) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _runDueRoutines(context, ref),
                    icon: const Icon(Icons.playlist_play),
                    label: Text('routines.run_due_now'.tr()),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (state.routines.isEmpty)
          _EmptyRoutineCard(onCreate: () => _openEditor(context, ref))
        else
          for (var index = 0; index < snapshot.sections.length; index++) ...[
            _RoutineSectionHeader(section: snapshot.sections[index]),
            const SizedBox(height: 12),
            ...snapshot.sections[index].routines.map(
              (routine) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RoutineCard(
                  routine: routine,
                  isRunning: state.isRunning(routine.id),
                  onToggleEnabled: (enabled) async {
                    await ref
                        .read(routinesNotifierProvider.notifier)
                        .toggleRoutine(routine.id, enabled);
                  },
                  onRunNow: () => _runRoutine(context, ref, routine),
                  onOpenDetails: () => _openDetails(context, routine),
                  onEdit: () => _openEditor(context, ref, routine: routine),
                  onDelete: () => _confirmDelete(context, ref, routine),
                ),
              ),
            ),
            if (index != snapshot.sections.length - 1)
              const SizedBox(height: 8),
          ],
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    Routine? routine,
  }) async {
    final result = await showModalBottomSheet<RoutineEditorResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => RoutineEditorSheet(initialRoutine: routine),
    );

    if (result == null) {
      return;
    }

    final notifier = ref.read(routinesNotifierProvider.notifier);
    if (routine == null) {
      await notifier.createRoutine(
        name: result.name,
        prompt: result.prompt,
        intervalValue: result.intervalValue,
        intervalUnit: result.intervalUnit,
        enabled: result.enabled,
        notifyOnCompletion: result.notifyOnCompletion,
        toolsEnabled: result.toolsEnabled,
        completionAction: result.completionAction,
        googleChatRule: result.googleChatRule,
      );
    } else {
      await notifier.updateRoutine(
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
      );
    }
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

  Future<void> _runDueRoutines(BuildContext context, WidgetRef ref) async {
    final executedCount = await ref
        .read(routinesNotifierProvider.notifier)
        .runDueRoutines(trigger: RoutineRunTrigger.manual);
    if (!context.mounted) {
      return;
    }

    final message = executedCount == 0
        ? 'routines.run_due_now_empty'.tr()
        : 'routines.run_due_now_completed'.tr(
            namedArgs: {'count': executedCount.toString()},
          );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openDetails(BuildContext context, Routine routine) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoutineDetailPage(routineId: routine.id),
      ),
    );
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
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmptyRoutineCard extends StatelessWidget {
  const _EmptyRoutineCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.schedule_send_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'routines.empty_title'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'routines.empty_body'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text('routines.create_cta'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineSectionHeader extends StatelessWidget {
  const _RoutineSectionHeader({required this.section});

  final RoutineHomeSection section;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color, title, subtitle) = switch (section.kind) {
      RoutineHomeSectionKind.attention => (
        Icons.warning_amber_rounded,
        colorScheme.tertiary,
        'routines.attention_title'.tr(),
        'routines.attention_subtitle'.tr(),
      ),
      RoutineHomeSectionKind.scheduled => (
        Icons.schedule_rounded,
        colorScheme.primary,
        'routines.scheduled_title'.tr(),
        'routines.scheduled_subtitle'.tr(),
      ),
      RoutineHomeSectionKind.paused => (
        Icons.pause_circle_outline_rounded,
        colorScheme.onSurfaceVariant,
        'routines.paused_title'.tr(),
        'routines.paused_subtitle'.tr(),
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _SectionCountChip(count: section.routines.length),
      ],
    );
  }
}

class _SectionCountChip extends StatelessWidget {
  const _SectionCountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count.toString(),
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.isRunning,
    required this.onToggleEnabled,
    required this.onRunNow,
    required this.onOpenDetails,
    required this.onEdit,
    required this.onDelete,
  });

  final Routine routine;
  final bool isRunning;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onRunNow;
  final VoidCallback onOpenDetails;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final latestRun = routine.latestRun;
    final isDue = RoutineScheduleService.isDue(routine);
    final isFailed = latestRun != null && !latestRun.isSuccessful;
    final colorScheme = Theme.of(context).colorScheme;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        routine.trimmedName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _RoutineStatusChip(
                            label: routine.enabled
                                ? 'routines.enabled_badge'.tr()
                                : 'routines.disabled_badge'.tr(),
                            color: routine.enabled
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                          ),
                          if (routine.toolsEnabled)
                            _RoutineStatusChip(
                              label: 'routines.tools_read_only_badge'.tr(),
                              color: colorScheme.secondaryContainer,
                            ),
                          if (routine.postsToGoogleChat)
                            _RoutineStatusChip(
                              label: 'routines.google_chat_badge'.tr(),
                              color: colorScheme.tertiaryContainer,
                            ),
                          if (isRunning)
                            _RoutineStatusChip(
                              label: 'routines.running_badge'.tr(),
                              color: Theme.of(
                                context,
                              ).colorScheme.secondaryContainer,
                            ),
                          if (isDue && !isRunning)
                            _RoutineStatusChip(
                              label: 'routines.due_badge'.tr(),
                              color: colorScheme.tertiaryContainer,
                            ),
                          if (isFailed)
                            _RoutineStatusChip(
                              label: 'routines.failed_badge'.tr(),
                              color: colorScheme.errorContainer,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: routine.enabled,
                  onChanged: isRunning ? null : onToggleEnabled,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              routine.trimmedPrompt,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _RoutineMetaLine(
                  label: 'routines.schedule_label'.tr(),
                  value: _formatSchedule(context, routine),
                ),
                _RoutineMetaLine(
                  label: 'routines.next_run_label'.tr(),
                  value: _formatNextRun(context, routine),
                ),
                _RoutineMetaLine(
                  label: 'routines.last_run_label'.tr(),
                  value: _formatLastRun(context, routine),
                ),
              ],
            ),
            if (latestRun != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: latestRun.isSuccessful
                      ? colorScheme.surfaceContainerHighest
                      : colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      latestRun.isSuccessful
                          ? 'routines.latest_result_label'.tr()
                          : 'routines.latest_error_label'.tr(),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      latestRun.isSuccessful
                          ? (latestRun.preview.isEmpty
                                ? 'routines.no_result_preview'.tr()
                                : latestRun.preview)
                          : (latestRun.error.isEmpty
                                ? 'common.unknown_error'.tr()
                                : latestRun.error),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: latestRun.isSuccessful
                            ? null
                            : colorScheme.onErrorContainer,
                      ),
                    ),
                    if (latestRun.usedTools &&
                        latestRun.toolNames.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'routines.tools_used_summary'.tr(
                          namedArgs: {
                            'count': latestRun.toolCallCount.toString(),
                            'names': latestRun.toolNames.join(', '),
                          },
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: latestRun.isSuccessful
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: isRunning ? null : onRunNow,
                  icon: const Icon(Icons.play_arrow),
                  label: Text('routines.run_now'.tr()),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenDetails,
                  icon: const Icon(Icons.open_in_new),
                  label: Text('routines.details'.tr()),
                ),
                OutlinedButton.icon(
                  onPressed: isRunning ? null : onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text('routines.edit'.tr()),
                ),
                OutlinedButton.icon(
                  onPressed: isRunning ? null : onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text('common.delete'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatSchedule(BuildContext context, Routine routine) {
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
}

class _RoutineStatusChip extends StatelessWidget {
  const _RoutineStatusChip({required this.label, required this.color});

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

class _RoutineMetaLine extends StatelessWidget {
  const _RoutineMetaLine({required this.label, required this.value});

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
