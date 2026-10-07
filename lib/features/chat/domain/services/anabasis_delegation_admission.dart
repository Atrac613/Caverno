import 'dart:convert';

import '../entities/conversation.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'conversation_task_readiness.dart';
import 'task_delegation_brief_builder.dart';

/// Binds planned delegation to current saved state before a child can run.
abstract final class AnabasisDelegationAdmission {
  static const refusedCode = 'anabasis_delegation_not_ready';

  static ({String prompt, McpToolResult? refusal, String workflowTaskId})
  prepare(
    ToolCallInfo call, {
    required bool isParent,
    required Conversation? conversation,
    required String prompt,
  }) {
    if (!isParent) {
      return (prompt: prompt, refusal: null, workflowTaskId: '');
    }
    final taskId = call.arguments['workflow_task_id'];
    if (conversation != null &&
        conversation.effectiveWorkflowSpec.tasks.isEmpty &&
        taskId == null) {
      return (prompt: prompt, refusal: null, workflowTaskId: '');
    }
    final candidates = conversation == null
        ? const <TaskDelegationBrief>[]
        : const TaskDelegationBriefBuilder().candidates(conversation);
    final matches = candidates.where((brief) => brief.task.id == taskId);
    if (matches.length != 1) {
      final requestedTask = conversation?.effectiveWorkflowSpec.tasks
          .where((task) => task.id == taskId)
          .firstOrNull;
      final requestedStatus = requestedTask == null
          ? null
          : conversation!.executionProgressForTask(requestedTask.id)?.status ??
                requestedTask.status;
      final unmetPreconditions = requestedTask == null
          ? const <Map<String, String>>[]
          : const ConversationTaskReadinessResolver()
                .resolve(conversation!, requestedTask)
                .unmet
                .map((item) => {'kind': item.kind.name, 'ref': item.ref})
                .toList(growable: false);
      return (
        prompt: prompt,
        workflowTaskId: '',
        refusal: McpToolResult(
          toolName: call.name,
          isSuccess: false,
          result: jsonEncode({
            'ok': false,
            'code': refusedCode,
            'result_origin': 'refusal',
            'ready_task_ids': candidates.map((brief) => brief.task.id).toList(),
            if (requestedStatus != null)
              'requested_task_status': requestedStatus.name,
            if (requestedTask != null)
              'unmet_preconditions': unmetPreconditions,
            'required_action':
                'Choose an exact ready workflow_task_id from the current plan. '
                'Do not recreate completed work. Inspect the requested task '
                'status and unmet preconditions. Resolving one question does '
                'not make downstream tasks ready by itself; recheck the plan '
                'before promising delegation.',
          }),
        ),
      );
    }
    final brief = matches.single;
    return (
      refusal: null,
      workflowTaskId: brief.task.id,
      prompt:
          '$prompt\n\nSaved task contract (authoritative scope):\n'
          '${jsonEncode({'workflow_task_id': brief.task.id, 'title': brief.task.title, 'target_files': brief.task.targetFiles, 'validation_command': brief.task.validationCommand, 'confirmed_premises': brief.premises})}\n'
          'Work only on this task. Inspect existing files before changing them. '
          'Run the saved validation command exactly, without wrappers or '
          'trailing commands that mask its exit status. Report failures as '
          'failures; the parent owns acceptance and goal state.',
    );
  }
}
