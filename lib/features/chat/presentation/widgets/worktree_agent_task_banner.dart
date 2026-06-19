import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/worktree_agent_task.dart';
import '../providers/worktree_agent_task_orchestrator.dart';
import '../providers/worktree_agent_task_registry_notifier.dart';

class WorktreeAgentTaskBanner extends ConsumerWidget {
  const WorktreeAgentTaskBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(worktreeAgentTaskRegistryNotifierProvider);
    final tasks = state.visibleTasks;
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final recoverableCount = tasks.where((task) => task.isRecoverable).length;
    final hasRecovery = recoverableCount > 0;
    final activeCount = tasks.where((task) => task.occupiesWorktree).length;
    final reviewReadyCount = tasks
        .where(
          (task) =>
              task.status == WorktreeAgentTaskStatus.completed &&
              task.verifiedGreen,
        )
        .length;
    final finishedCount = tasks.where((task) => task.isTerminal).length;
    final hasActive = activeCount > 0;
    final hasReviewReady = reviewReadyCount > 0;

    return Material(
      color: hasRecovery
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => _showSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                hasRecovery
                    ? Icons.warning_amber_rounded
                    : hasActive
                    ? Icons.account_tree
                    : hasReviewReady
                    ? Icons.task_alt
                    : Icons.done_all,
                size: 18,
                color: hasRecovery
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasRecovery
                      ? 'worktree_agent.banner_recovery'.tr(
                          namedArgs: {'count': '$recoverableCount'},
                        )
                      : hasActive
                      ? 'worktree_agent.banner_active'.tr(
                          namedArgs: {'count': '$activeCount'},
                        )
                      : hasReviewReady
                      ? 'worktree_agent.banner_review_ready'.tr(
                          namedArgs: {'count': '$reviewReadyCount'},
                        )
                      : 'worktree_agent.banner_finished'.tr(
                          namedArgs: {'count': '$finishedCount'},
                        ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hasRecovery
                        ? theme.colorScheme.onErrorContainer
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.expand_more,
                size: 18,
                color: hasRecovery
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _WorktreeAgentTaskSheet(),
    );
  }
}

class _WorktreeAgentTaskSheet extends ConsumerWidget {
  const _WorktreeAgentTaskSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(worktreeAgentTaskRegistryNotifierProvider);
    final tasks = state.visibleTasks;
    final notifier = ref.read(
      worktreeAgentTaskRegistryNotifierProvider.notifier,
    );
    final runState = ref.watch(worktreeAgentTaskRunControllerProvider);
    final theme = Theme.of(context);
    final hasFinished = state.finishedTasks.isNotEmpty;
    final hasQueued = tasks.any(
      (task) => task.status == WorktreeAgentTaskStatus.queued,
    );

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
                    'worktree_agent.sheet_title'.tr(),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (hasQueued)
                  TextButton(
                    onPressed: runState.isRunning
                        ? null
                        : () async {
                            await ref
                                .read(
                                  worktreeAgentTaskRunControllerProvider
                                      .notifier,
                                )
                                .startAndExecuteReady(
                                  const WorktreeAgentTaskRunRequest(),
                                );
                          },
                    child: Text(
                      runState.isRunning
                          ? 'worktree_agent.run_ready_running'.tr()
                          : 'worktree_agent.run_ready'.tr(),
                    ),
                  ),
                if (hasFinished)
                  TextButton(
                    onPressed: notifier.clearFinished,
                    child: Text('worktree_agent.clear_finished'.tr()),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _WorktreeAgentRunSummary(runState: runState),
            if (runState.isRunning ||
                runState.lastResult != null ||
                runState.errorMessage.isNotEmpty)
              const SizedBox(height: 8),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text('worktree_agent.empty'.tr()),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  separatorBuilder: (_, _) => const Divider(height: 16),
                  itemBuilder: (context, index) =>
                      _WorktreeAgentTaskTile(task: tasks[index]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WorktreeAgentRunSummary extends StatelessWidget {
  const _WorktreeAgentRunSummary({required this.runState});

  final WorktreeAgentTaskRunState runState;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _summaryText();
    if (text == null) {
      return const SizedBox.shrink();
    }

    final isError = runState.errorMessage.isNotEmpty && !runState.isRunning;
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError ? Icons.error_outline : Icons.info_outline,
          size: 16,
          color: isError ? colorScheme.error : colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isError ? colorScheme.error : colorScheme.onSurfaceVariant,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String? _summaryText() {
    if (runState.isRunning) {
      return 'worktree_agent.run_status_running'.tr();
    }

    final errorMessage = runState.errorMessage.trim();
    if (errorMessage.isNotEmpty) {
      return 'worktree_agent.run_status_error'.tr(
        namedArgs: {'error': errorMessage},
      );
    }

    final result = runState.lastResult;
    if (result == null) {
      return null;
    }

    final executionFailures = result.executions
        .where((execution) => !execution.success)
        .length;
    final failed = result.schedule.failed.length + executionFailures;
    return 'worktree_agent.run_status_last'.tr(
      namedArgs: {
        'started': '${result.schedule.started.length}',
        'executed': '${result.executions.length}',
        'failed': '$failed',
        'skipped': '${result.schedule.skipped.length}',
      },
    );
  }
}

class _WorktreeAgentTaskTile extends ConsumerWidget {
  const _WorktreeAgentTaskTile({required this.task});

  final WorktreeAgentTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(
      worktreeAgentTaskRegistryNotifierProvider.notifier,
    );
    final verificationLabel = _verificationLabel();
    final detail = _detailText();

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
                task.title.isEmpty ? task.branchName : task.title,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${_statusLabel()} · ${task.branchName}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (verificationLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    verificationLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: task.verifiedGreen
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    detail,
                    style: theme.textTheme.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (task.isRecoverable)
          TextButton(
            onPressed: () => notifier.markRecoveryQueued(task.id),
            child: Text('worktree_agent.resume'.tr()),
          ),
        if (!task.isTerminal)
          TextButton(
            onPressed: () => notifier.cancel(task.id),
            child: Text('worktree_agent.cancel'.tr()),
          ),
      ],
    );
  }

  String _detailText() {
    return switch (task.status) {
      WorktreeAgentTaskStatus.completed =>
        task.verificationSummary.isNotEmpty
            ? task.verificationSummary
            : task.resultSummary.isNotEmpty
            ? task.resultSummary
            : task.worktreePath,
      WorktreeAgentTaskStatus.failed =>
        task.error.isNotEmpty ? task.error : task.worktreePath,
      WorktreeAgentTaskStatus.needsRecovery =>
        task.recoveryNote.isNotEmpty ? task.recoveryNote : task.worktreePath,
      _ => task.worktreePath,
    };
  }

  String? _verificationLabel() {
    if (task.status != WorktreeAgentTaskStatus.completed) {
      return null;
    }
    return task.verifiedGreen
        ? 'worktree_agent.verification_green'.tr()
        : 'worktree_agent.verification_not_green'.tr();
  }

  Widget _statusIcon(ThemeData theme) {
    return switch (task.status) {
      WorktreeAgentTaskStatus.queued => Icon(
        Icons.schedule,
        size: 18,
        color: theme.colorScheme.primary,
      ),
      WorktreeAgentTaskStatus.running => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      WorktreeAgentTaskStatus.needsRecovery => Icon(
        Icons.warning_amber_rounded,
        size: 18,
        color: theme.colorScheme.error,
      ),
      WorktreeAgentTaskStatus.completed => Icon(
        Icons.check_circle,
        size: 18,
        color: theme.colorScheme.primary,
      ),
      WorktreeAgentTaskStatus.failed => Icon(
        Icons.error_outline,
        size: 18,
        color: theme.colorScheme.error,
      ),
      WorktreeAgentTaskStatus.cancelled => Icon(
        Icons.cancel_outlined,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    };
  }

  String _statusLabel() {
    return switch (task.status) {
      WorktreeAgentTaskStatus.queued => 'worktree_agent.status_queued'.tr(),
      WorktreeAgentTaskStatus.running => 'worktree_agent.status_running'.tr(),
      WorktreeAgentTaskStatus.needsRecovery =>
        'worktree_agent.status_needs_recovery'.tr(),
      WorktreeAgentTaskStatus.completed =>
        'worktree_agent.status_completed'.tr(),
      WorktreeAgentTaskStatus.failed => 'worktree_agent.status_failed'.tr(),
      WorktreeAgentTaskStatus.cancelled =>
        'worktree_agent.status_cancelled'.tr(),
    };
  }
}
