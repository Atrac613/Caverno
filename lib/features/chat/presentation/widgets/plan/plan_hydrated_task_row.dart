import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation_workflow.dart';
import '../../../domain/services/conversation_execution_summary_service.dart';
import '../../../domain/services/task_lifecycle_state.dart';

class PlanHydratedTaskRow extends StatelessWidget {
  const PlanHydratedTaskRow({
    super.key,
    required this.task,
    required this.progress,
    this.acceptance,
  });

  final ConversationWorkflowTask task;
  final ConversationExecutionTaskProgress? progress;

  /// The acceptance the parent recorded for this task, if it recorded one.
  ///
  /// Passed in because only the conversation records one and this row is given
  /// a task -- and passed whole rather than as a flag, because `accepted` is
  /// the one state that owes an explanation: the rationale and the evidence it
  /// rested on were written by `recordTaskAcceptance` and, until this row read
  /// them, by nothing at all. A chip that says "accepted" and cannot say on
  /// what is the same shortfall one layer up from the prompt's.
  final ConversationTaskAcceptance? acceptance;

  bool get accepted => acceptance != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final executionSummary = ConversationExecutionSummaryService.summarize(
      progress,
    );
    final validationStatus =
        progress?.validationStatus ??
        ConversationExecutionValidationStatus.unknown;
    final blockedReason = progress?.normalizedBlockedReason;
    final validationSummary = executionSummary.lastValidation;
    final summary = executionSummary.lastOutcome;
    final validationCommand = executionSummary.lastValidationCommand;
    final blockedSince = executionSummary.blockedSince;
    // What the task has actually reached, not the enum's `completed`, which
    // answers produced / verified / accepted all at once.
    final lifecycleState = const TaskLifecycleProjection().ofProgress(
      status: progress?.status ?? task.status,
      validationStatus: validationStatus,
      accepted: accepted,
    );
    final nextStep = _workflowTaskNextStepLabel(
      status: task.status,
      validationStatus: validationStatus,
      hasBlockedReason: blockedReason != null,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(_taskLifecycleLabel(lifecycleState).tr()),
                visualDensity: VisualDensity.compact,
                side: BorderSide.none,
                backgroundColor: _workflowTaskStatusColor(
                  context,
                  task.status,
                ).withValues(alpha: 0.16),
                labelStyle: theme.textTheme.labelSmall?.copyWith(
                  color: _workflowTaskStatusColor(context, task.status),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (summary != null) ...[
            const SizedBox(height: 6),
            _PlanTaskDetail(
              label: 'chat.plan_document_hydrated_last_outcome'.tr(),
              value: summary,
            ),
          ],
          if (blockedReason != null) ...[
            const SizedBox(height: 6),
            _PlanTaskDetail(
              label: 'chat.workflow_task_blocked_reason'.tr(),
              value: blockedReason,
            ),
          ],
          if (validationStatus !=
                  ConversationExecutionValidationStatus.unknown ||
              validationSummary != null) ...[
            const SizedBox(height: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (validationStatus !=
                        ConversationExecutionValidationStatus.unknown)
                      Chip(
                        label: Text(
                          _workflowValidationStatusLabel(validationStatus).tr(),
                        ),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                        backgroundColor: _workflowValidationStatusColor(
                          context,
                          validationStatus,
                        ).withValues(alpha: 0.16),
                        labelStyle: theme.textTheme.labelSmall?.copyWith(
                          color: _workflowValidationStatusColor(
                            context,
                            validationStatus,
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (validationSummary != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 0,
                          maxWidth: 420,
                        ),
                        child: Text(
                          validationSummary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                if (validationCommand != null) ...[
                  const SizedBox(height: 6),
                  _PlanTaskDetail(
                    label: 'chat.plan_document_hydrated_last_validation'.tr(),
                    value: validationCommand,
                  ),
                ],
              ],
            ),
          ],
          if (acceptance case final recorded?) ...[
            if (recorded.evidence.isNotEmpty) ...[
              const SizedBox(height: 6),
              _PlanTaskDetail(
                label: 'chat.plan_document_hydrated_accepted_on'.tr(),
                value: recorded.evidence.join(', '),
              ),
            ],
            if (recorded.rationale.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              _PlanTaskDetail(
                label: 'chat.plan_document_hydrated_accepted_because'.tr(),
                value: recorded.rationale.trim(),
              ),
            ],
          ],
          if (blockedSince != null) ...[
            const SizedBox(height: 6),
            _PlanTaskDetail(
              label: 'chat.plan_document_hydrated_blocked_since'.tr(),
              value: DateFormat('MM/dd HH:mm').format(blockedSince.toLocal()),
            ),
          ],
          const SizedBox(height: 6),
          _PlanTaskDetail(
            label: 'chat.workflow_task_next_step'.tr(),
            value: nextStep.tr(),
          ),
        ],
      ),
    );
  }

  String _workflowTaskNextStepLabel({
    required ConversationWorkflowTaskStatus status,
    required ConversationExecutionValidationStatus validationStatus,
    required bool hasBlockedReason,
  }) {
    if (status == ConversationWorkflowTaskStatus.blocked) {
      return hasBlockedReason
          ? 'chat.workflow_task_next_step_blocked'
          : 'chat.workflow_task_next_step_blocked_missing_reason';
    }
    if (validationStatus == ConversationExecutionValidationStatus.failed) {
      return 'chat.workflow_task_next_step_validation_failed';
    }
    return switch (status) {
      ConversationWorkflowTaskStatus.pending =>
        'chat.workflow_task_next_step_pending',
      ConversationWorkflowTaskStatus.inProgress =>
        'chat.workflow_task_next_step_in_progress',
      ConversationWorkflowTaskStatus.completed =>
        'chat.workflow_task_next_step_completed',
      ConversationWorkflowTaskStatus.blocked =>
        'chat.workflow_task_next_step_blocked',
    };
  }

  String _taskLifecycleLabel(TaskLifecycleState state) {
    return switch (state) {
      TaskLifecycleState.pending => 'chat.workflow_task_status_pending',
      TaskLifecycleState.inProgress => 'chat.workflow_task_status_in_progress',
      TaskLifecycleState.blocked => 'chat.workflow_task_status_blocked',
      TaskLifecycleState.produced => 'chat.workflow_task_status_produced',
      TaskLifecycleState.verified => 'chat.workflow_task_status_verified',
      TaskLifecycleState.accepted => 'chat.workflow_task_status_accepted',
    };
  }

  Color _workflowTaskStatusColor(
    BuildContext context,
    ConversationWorkflowTaskStatus status,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      ConversationWorkflowTaskStatus.pending => scheme.secondary,
      ConversationWorkflowTaskStatus.inProgress => scheme.primary,
      ConversationWorkflowTaskStatus.completed => Colors.green.shade700,
      ConversationWorkflowTaskStatus.blocked => scheme.error,
    };
  }

  String _workflowValidationStatusLabel(
    ConversationExecutionValidationStatus status,
  ) {
    return switch (status) {
      ConversationExecutionValidationStatus.unknown =>
        'chat.workflow_task_validation_status_unknown',
      ConversationExecutionValidationStatus.passed =>
        'chat.workflow_task_validation_status_passed',
      ConversationExecutionValidationStatus.failed =>
        'chat.workflow_task_validation_status_failed',
    };
  }

  Color _workflowValidationStatusColor(
    BuildContext context,
    ConversationExecutionValidationStatus status,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      ConversationExecutionValidationStatus.unknown => scheme.secondary,
      ConversationExecutionValidationStatus.passed => Colors.green.shade700,
      ConversationExecutionValidationStatus.failed => scheme.error,
    };
  }
}

class _PlanTaskDetail extends StatelessWidget {
  const _PlanTaskDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}
