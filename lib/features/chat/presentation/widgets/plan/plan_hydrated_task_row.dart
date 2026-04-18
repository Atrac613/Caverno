import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation_workflow.dart';
import '../../../domain/services/conversation_execution_summary_service.dart';

class PlanHydratedTaskRow extends StatelessWidget {
  const PlanHydratedTaskRow({
    super.key,
    required this.task,
    required this.progress,
  });

  final ConversationWorkflowTask task;
  final ConversationExecutionTaskProgress? progress;

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
                label: Text(_workflowTaskStatusLabel(task.status).tr()),
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
          if (blockedSince != null) ...[
            const SizedBox(height: 6),
            _PlanTaskDetail(
              label: 'chat.plan_document_hydrated_blocked_since'.tr(),
              value: DateFormat('MM/dd HH:mm').format(blockedSince.toLocal()),
            ),
          ],
        ],
      ),
    );
  }

  String _workflowTaskStatusLabel(ConversationWorkflowTaskStatus status) {
    return switch (status) {
      ConversationWorkflowTaskStatus.pending =>
        'chat.workflow_task_status_pending',
      ConversationWorkflowTaskStatus.inProgress =>
        'chat.workflow_task_status_in_progress',
      ConversationWorkflowTaskStatus.completed =>
        'chat.workflow_task_status_completed',
      ConversationWorkflowTaskStatus.blocked =>
        'chat.workflow_task_status_blocked',
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
