import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/presentation/providers/conversations_notifier.dart';
import '../../application/project_task_review_workflow.dart';
import '../../domain/project_task_progress.dart';
import '../project_task_review_launcher.dart';
import '../providers/project_task_progress_provider.dart';
import '../providers/project_task_status_provider.dart';

enum _StepState { done, active, pending, failed }

/// The companion-sidebar summary of a project task's workflow: which stage is
/// running, which are finished, and which remain.
///
/// Renders nothing for a thread with no workflow run. The subtasks themselves
/// appear in the Plan Mode progress rows below, from the thread's execution
/// tasks.
class ProjectTaskProgressSection extends ConsumerWidget {
  const ProjectTaskProgressSection({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(
      projectTaskProgressProvider.select((all) => all[conversationId]),
    );
    // A live run reports its own stage. Otherwise the stage is derived from
    // the saved thread and git, so work done after a stop shows; the stop
    // reason is kept while the derived stage is still the one it stopped in.
    final derived = ref.watch(projectTaskStatusProvider(conversationId)).value;
    final progress =
        live?.outcome == ProjectTaskOutcome.running || derived == null
        ? live
        : live?.outcome == ProjectTaskOutcome.stopped &&
              _row(live!.phase) == _row(derived.phase)
        ? derived.copyWith(stopReason: live.stopReason)
        : derived;
    // Until git has been read after a restart, the saved thread still says
    // a started task can be resumed.
    final startedTask = ref.watch(
      conversationsNotifierProvider.select((state) {
        final task = state.conversationForId(conversationId);
        return task?.goal?.projectTaskAutoReview == true &&
            task!.messages.isNotEmpty;
      }),
    );
    final resumable = progress == null
        ? startedTask
        : progress.outcome != ProjectTaskOutcome.running &&
              progress.outcome != ProjectTaskOutcome.committed;
    if (progress == null && !resumable) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final resumeButton = resumable
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              key: const ValueKey('project-task-resume'),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text('project_task_progress.resume'.tr()),
              onPressed: () => ref
                  .read(projectTaskResumeLauncherProvider)
                  .start(
                    ref: ref,
                    conversationId: conversationId,
                    languageCode: context.locale.languageCode,
                    isMounted: () => context.mounted,
                    showMessage: (message) => ScaffoldMessenger.maybeOf(
                      context,
                    )?.showSnackBar(SnackBar(content: Text(message))),
                    resume: true,
                  ),
            ),
          )
        : null;
    if (progress == null) {
      return Padding(
        key: const ValueKey('project-task-progress'),
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'project_task_progress.title'.tr(),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            resumeButton!,
          ],
        ),
      );
    }
    final (outcomeKey, outcomeColor) = switch (progress.outcome) {
      ProjectTaskOutcome.running => (
        'project_task_progress.running',
        theme.colorScheme.primary,
      ),
      ProjectTaskOutcome.committed => (
        'project_task_progress.committed',
        theme.colorScheme.primary,
      ),
      ProjectTaskOutcome.findingsRemain => (
        'project_task_progress.findings_remain',
        theme.colorScheme.error,
      ),
      ProjectTaskOutcome.stopped => (
        'project_task_progress.stopped',
        theme.colorScheme.error,
      ),
      ProjectTaskOutcome.paused => (
        'project_task_progress.paused',
        theme.colorScheme.onSurfaceVariant,
      ),
      ProjectTaskOutcome.unreviewed => (
        'project_task_progress.unreviewed',
        theme.colorScheme.tertiary,
      ),
      ProjectTaskOutcome.readyToCommit => (
        'project_task_progress.ready_to_commit',
        theme.colorScheme.primary,
      ),
    };
    final stopReason = progress.stopReason;
    return Padding(
      key: const ValueKey('project-task-progress'),
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'project_task_progress.title'.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                outcomeKey.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: outcomeColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final row in _rows(progress))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _StepRow(
                label: row.label,
                detail: row.detail,
                state: row.state,
              ),
            ),
          if (progress.outcome != ProjectTaskOutcome.committed &&
              stopReason != null)
            Text(
              stopReason,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ?resumeButton,
        ],
      ),
    );
  }

  static int _row(ProjectTaskPhase phase) => switch (phase) {
    ProjectTaskPhase.decompose => 0,
    ProjectTaskPhase.implement => 1,
    ProjectTaskPhase.review || ProjectTaskPhase.repair => 2,
    ProjectTaskPhase.commit => 3,
  };

  /// Review and repair alternate, so they share one row whose detail names
  /// the repair round.
  static List<({String label, String? detail, _StepState state})> _rows(
    ProjectTaskProgress progress,
  ) {
    final current = _row(progress.phase);
    _StepState stateOf(int row) {
      if (progress.outcome == ProjectTaskOutcome.committed || row < current) {
        return _StepState.done;
      }
      if (row > current) return _StepState.pending;
      return switch (progress.outcome) {
        ProjectTaskOutcome.running => _StepState.active,
        ProjectTaskOutcome.stopped ||
        ProjectTaskOutcome.findingsRemain => _StepState.failed,
        _ => _StepState.pending,
      };
    }

    // Completed subtasks, as the Plan Mode progress rows count them. The
    // position of the running one read as "3/3" while the third had not
    // finished, and the workflow had stopped on it.
    final count = progress.subtaskCount;
    final implementDetail = count == 0
        ? null
        : 'project_task_progress.subtasks_done'.tr(
            args: ['${progress.completedSubtasks}', '$count'],
          );
    final repairDetail = progress.repairRound == 0
        ? null
        : 'project_task_progress.repair_round'.tr(
            args: [
              '${progress.repairRound}',
              '${ProjectTaskReviewWorkflow.maxRepairRounds}',
            ],
          );
    return [
      (
        label: 'project_task_progress.decompose'.tr(),
        detail: null,
        state: stateOf(0),
      ),
      (
        label: 'project_task_progress.implement'.tr(),
        detail: implementDetail,
        state: stateOf(1),
      ),
      (
        label: 'project_task_progress.review'.tr(),
        detail: repairDetail,
        state: stateOf(2),
      ),
      (
        label: 'project_task_progress.commit'.tr(),
        detail: null,
        state: stateOf(3),
      ),
    ];
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.detail,
    required this.state,
  });

  final String label;
  final String? detail;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final icon = switch (state) {
      _StepState.done => Icon(
        Icons.check_circle,
        size: 18,
        color: colors.primary,
      ),
      _StepState.active => const SizedBox(
        width: 18,
        height: 18,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      _StepState.pending => Icon(
        Icons.radio_button_unchecked,
        size: 18,
        color: colors.outline,
      ),
      _StepState.failed => Icon(Icons.error, size: 18, color: colors.error),
    };
    final detail = this.detail;
    return Row(
      key: ValueKey('project-task-step-$label-${state.name}'),
      children: [
        icon,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: state == _StepState.pending
                  ? colors.onSurfaceVariant
                  : colors.onSurface,
              fontWeight: state == _StepState.active
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
          ),
        ),
        if (detail != null)
          Text(
            detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
