import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/mcp_tool_entity.dart';
import '../entities/subagent_task.dart';
import 'subagent_tool_contract.dart';

/// What `get_subagent_result` answers with, in every case it can answer.
///
/// Extracted from the notifier because none of it needs a turn: the shapes are a
/// function of the child, or of the ids that exist. What stays behind is the
/// registry read, which is the only part that does.
class SubagentResultPayloads {
  const SubagentResultPayloads();

  McpToolResult missingTaskId(String toolName) => McpToolResult(
    toolName: toolName,
    result: '',
    isSuccess: false,
    errorMessage: 'task_id is required',
  );

  /// An id that names no child, answered with the ids that do.
  ///
  /// Measured live: the parent passed a *workflow* task id -- the plan's -- to a
  /// tool whose parameter is `task_id`, twice, and the second failure ended the
  /// whole turn as if the tool were unreachable. A refusal that names nothing
  /// correctable is what made that possible.
  McpToolResult unknownTask({
    required String toolName,
    required String taskId,
    required List<String> knownTaskIds,
  }) => McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': subagentTaskUnknownCode,
      ...ToolResultOrigin.refusal.marker,
      'status': 'not_found',
      'task_id': taskId,
      'known_task_ids': knownTaskIds,
      'required_action':
          'Pass a task_id from known_task_ids. A workflow_task_id names a '
          'task in the plan, not a child that ran.',
    }),
    isSuccess: false,
    errorMessage: 'No subagent task with id $taskId',
  );

  /// The child's own state, and only the field its state earns: a summary for a
  /// completed child, an error for a failed one, and a note for one still going.
  McpToolResult forTask({
    required String toolName,
    required SubagentTask task,
  }) {
    final payload = <String, dynamic>{
      'task_id': task.id,
      'description': task.description,
      'status': task.status.name,
    };
    if (task.status == SubagentTaskStatus.completed) {
      payload['summary'] = task.resultSummary;
    } else if (task.status == SubagentTaskStatus.failed) {
      payload['error'] = task.error ?? 'Subagent failed';
    } else if (task.isActive) {
      payload['note'] = 'Still running. Check again shortly.';
    }
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode(payload),
      isSuccess: task.status != SubagentTaskStatus.failed,
    );
  }
}
