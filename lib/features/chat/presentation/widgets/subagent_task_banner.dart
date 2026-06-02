import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/subagent_task.dart';
import '../providers/subagent_task_notifier.dart';

/// Compact banner shown on the chat page while background subagent tasks exist.
///
/// Collapses to zero height when there are no tasks. Tapping it opens a sheet to
/// inspect each task's output and cancel running tasks or clear finished ones.
class SubagentTaskBanner extends ConsumerWidget {
  const SubagentTaskBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(subagentTaskNotifierProvider);
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final activeCount = tasks.where((task) => task.isActive).length;
    final hasActive = activeCount > 0;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => _showSheet(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: hasActive
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : Icon(
                        Icons.task_alt,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasActive
                      ? 'subagent.banner_running'.tr(
                          namedArgs: {'count': '$activeCount'},
                        )
                      : 'subagent.banner_done'.tr(
                          namedArgs: {'count': '${tasks.length}'},
                        ),
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.expand_more,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _SubagentTaskSheet(),
    );
  }
}

class _SubagentTaskSheet extends ConsumerWidget {
  const _SubagentTaskSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(subagentTaskNotifierProvider);
    final notifier = ref.read(subagentTaskNotifierProvider.notifier);
    final theme = Theme.of(context);
    final hasFinished = tasks.any((task) => task.isTerminal);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'subagent.sheet_title'.tr(),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (hasFinished)
                  TextButton(
                    onPressed: notifier.clearFinished,
                    child: Text('subagent.clear_finished'.tr()),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('subagent.empty'.tr()),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const Divider(height: 16),
                  itemBuilder: (context, index) => _SubagentTaskTile(
                    task: tasks[index],
                    onCancel: () => notifier.cancel(tasks[index].id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SubagentTaskTile extends StatelessWidget {
  const _SubagentTaskTile({required this.task, required this.onCancel});

  final SubagentTask task;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = switch (task.status) {
      SubagentTaskStatus.completed => task.resultSummary,
      SubagentTaskStatus.failed => task.error ?? '',
      _ => '',
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusIcon(theme),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.description,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _statusLabel(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    detail,
                    style: theme.textTheme.bodySmall,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        if (task.isActive)
          TextButton(
            onPressed: onCancel,
            child: Text('subagent.cancel'.tr()),
          ),
      ],
    );
  }

  Widget _statusIcon(ThemeData theme) {
    return switch (task.status) {
      SubagentTaskStatus.pending ||
      SubagentTaskStatus.running => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      SubagentTaskStatus.completed => Icon(
        Icons.check_circle,
        size: 18,
        color: theme.colorScheme.primary,
      ),
      SubagentTaskStatus.failed => Icon(
        Icons.error_outline,
        size: 18,
        color: theme.colorScheme.error,
      ),
      SubagentTaskStatus.cancelled => Icon(
        Icons.cancel_outlined,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    };
  }

  String _statusLabel() {
    return switch (task.status) {
      SubagentTaskStatus.pending => 'subagent.status_pending'.tr(),
      SubagentTaskStatus.running => 'subagent.status_running'.tr(),
      SubagentTaskStatus.completed => 'subagent.status_completed'.tr(),
      SubagentTaskStatus.failed => 'subagent.status_failed'.tr(),
      SubagentTaskStatus.cancelled => 'subagent.status_cancelled'.tr(),
    };
  }
}
