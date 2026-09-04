import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation_workflow.dart';

/// What this task is still waiting for (ANA1).
///
/// Readiness is derived, never stored, so this renders the *unmet* edges rather
/// than a "not ready" flag: a task that cannot start is only actionable if the
/// user can see which of the three things is missing — another task, an
/// assumption nobody has confirmed, or a question nobody has answered. Two of
/// those three are things the user themself can clear.
class TaskPreconditionNotice extends StatelessWidget {
  const TaskPreconditionNotice({required this.unmet, super.key});

  final List<ConversationTaskPrecondition> unmet;

  @override
  Widget build(BuildContext context) {
    if (unmet.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'chat.workflow_task_waiting_on'.tr(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        for (final edge in unmet)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '• ${_kindLabel(edge.kind)}: ${edge.ref.trim()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  String _kindLabel(ConversationTaskPreconditionKind kind) {
    return switch (kind) {
      ConversationTaskPreconditionKind.task =>
        'chat.workflow_task_waiting_task'.tr(),
      ConversationTaskPreconditionKind.assumption =>
        'chat.workflow_task_waiting_assumption'.tr(),
      ConversationTaskPreconditionKind.question =>
        'chat.workflow_task_waiting_question'.tr(),
    };
  }
}
