import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';

import 'plan_mode_heartbeat.dart';

bool executionLogsContainWorkflowCompleted(List<String> logs) {
  const completionMarkers = <String>[
    'all planned tasks are complete',
    'all planned tasks have been completed',
    'all tasks in the plan are complete',
    'all tasks in the plan have been completed',
    'all tasks in the current plan are now complete',
    'all scheduled tasks are complete',
    'all scheduled tasks have been completed',
    'all saved tasks are complete',
    'すべての予定されていたタスクが完了しました',
  ];
  return logs.any((line) {
        final normalized = line.trim().toLowerCase();
        return completionMarkers.any(normalized.contains);
      }) ||
      _logsShowFinalTaskCompletion(logs);
}

bool executionLogsContainLateValidationAnswerProgress(List<String> logs) {
  var sawSuccessfulValidation = false;

  for (final line in logs) {
    final normalized = line.trim().toLowerCase();
    if (normalized.contains('"exit_code":0')) {
      sawSuccessfulValidation = true;
      continue;
    }
    if (!sawSuccessfulValidation) {
      continue;
    }
    if (normalized.contains('[tool] resending tool results as user message') ||
        normalized.contains(
          '[llm] ========== streamchatcompletion ==========',
        )) {
      return true;
    }
  }

  return false;
}

bool executionTasksContainOnlyCompleted(List<ConversationWorkflowTask> tasks) {
  return tasks.isNotEmpty &&
      tasks.every(
        (task) => task.status == ConversationWorkflowTaskStatus.completed,
      );
}

String? activePlanModeWorkflowTaskTitle(List<ConversationWorkflowTask> tasks) {
  for (final task in tasks) {
    if (task.status == ConversationWorkflowTaskStatus.inProgress) {
      return task.title;
    }
  }
  for (final task in tasks) {
    if (task.status == ConversationWorkflowTaskStatus.blocked) {
      return task.title;
    }
  }
  for (final task in tasks) {
    if (task.status == ConversationWorkflowTaskStatus.pending) {
      return task.title;
    }
  }
  return tasks.isEmpty ? null : tasks.last.title;
}

int countPlanModeContentToolResults(List<String> logs) {
  return logs
      .where(
        (line) => line.contains('[ContentTool] Appended result to message'),
      )
      .length;
}

int countPlanModeFileWriteExecutions(List<String> logs) {
  const writeToolPatterns = <String>[
    '[McpToolService] Executing tool: write_file',
    '[McpToolService] Executing tool: edit_file',
    '[McpToolService] Executing tool: create_file',
    '[McpToolService] Executing tool: update_file',
    '[McpToolService] Executing tool: delete_file',
    '[McpToolService] Executing tool: rollback_last_file_change',
  ];
  return logs
      .where(
        (line) => writeToolPatterns.any((pattern) => line.contains(pattern)),
      )
      .length;
}

int countPlanModeValidationLikeExecutions(List<String> logs) {
  const validationPatterns = <String>[
    '[McpToolService] Executing tool: run_tests',
    '[McpToolService] Executing tool: local_execute_command',
  ];
  return logs
      .where(
        (line) => validationPatterns.any((pattern) => line.contains(pattern)),
      )
      .length;
}

int countPlanModeExecutionActivities(List<String> logs) {
  return logs.where((line) {
    return (line.contains('[Tool] Lifecycle') &&
            (line.contains('"lifecycleState":"completed"') ||
                line.contains('"lifecycleState":"skipped"'))) ||
        line.contains('[LLM] === Response');
  }).length;
}

String resolvePlanModeExecutionSubphase(
  PlanModePhaseTrace phaseTrace,
  String? activeTaskTitle,
) {
  if (phaseTrace.validationStartedAt != null) {
    return 'validation';
  }
  if (phaseTrace.nextTaskStartedAt != null) {
    return 'nextTask';
  }
  if (phaseTrace.firstTaskStartedAt != null) {
    return activeTaskTitle == null ? 'execution' : 'savedTask';
  }
  return 'execution';
}

String summarizePlanModeWorkflowTasks(List<ConversationWorkflowTask> tasks) {
  if (tasks.isEmpty) {
    return 'none';
  }
  return tasks.map((task) => '${task.title}:${task.status.name}').join(', ');
}

bool shouldRecoverExecutionFromExecutionDocument({
  required Conversation? conversation,
  required bool isLoading,
  required bool hasPendingApprovals,
  required DateTime? approvalTappedAt,
}) {
  if (conversation == null ||
      isLoading ||
      hasPendingApprovals ||
      approvalTappedAt == null) {
    return false;
  }
  if (conversation.projectedExecutionTasks.isNotEmpty) {
    return false;
  }
  return conversation.shouldPreferPlanDocument &&
      (conversation.effectiveExecutionDocument?.trim().isNotEmpty ?? false);
}

bool _logsShowFinalTaskCompletion(List<String> logs) {
  var lastTaskCompletionIndex = -1;

  for (var index = 0; index < logs.length; index++) {
    final normalized = logs[index].trim().toLowerCase();
    if (_isTerminalTaskCompletionLine(normalized)) {
      lastTaskCompletionIndex = index;
    }
  }

  if (lastTaskCompletionIndex < 0) {
    return false;
  }

  var finalAnswerStreamIndex = -1;
  for (var index = lastTaskCompletionIndex + 1; index < logs.length; index++) {
    final normalized = logs[index].trim().toLowerCase();
    if (normalized.contains(
      '[llm] ========== streamchatcompletion ==========',
    )) {
      finalAnswerStreamIndex = index;
      break;
    }
  }

  if (finalAnswerStreamIndex < 0) {
    return false;
  }

  for (
    var index = lastTaskCompletionIndex + 1;
    index < finalAnswerStreamIndex;
    index++
  ) {
    final normalized = logs[index].trim().toLowerCase();
    if (_isNextTaskHandoffLine(normalized)) {
      return false;
    }
  }

  return logs.skip(lastTaskCompletionIndex).any((line) {
    final normalized = line.trim().toLowerCase();
    return normalized.contains(
          '[tool] resending tool results as user message',
        ) ||
        normalized.contains('[llm] ========== streamchatcompletion ==========');
  });
}

bool _isTerminalTaskCompletionLine(String normalized) {
  if ((normalized.contains('the task "') &&
          normalized.contains('has been completed successfully')) ||
      (normalized.contains('the task "') &&
          normalized.contains('" is complete')) ||
      normalized.contains('the final saved task is complete') ||
      normalized.contains(
        'the saved task is complete and no pending saved tasks remain',
      )) {
    return true;
  }

  final taskIdCompletionPattern = RegExp(
    r'\btask [0-9a-f-]{8,}.*has been completed successfully\b',
  );
  return taskIdCompletionPattern.hasMatch(normalized);
}

bool _isNextTaskHandoffLine(String normalized) {
  return normalized.contains(
    'the previous saved task is complete. continue immediately with the next pending saved task',
  );
}
