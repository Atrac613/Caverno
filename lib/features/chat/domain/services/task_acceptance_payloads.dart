import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import 'task_acceptance_decision.dart';

/// What an acceptance attempt returns to the parent.
///
/// Split from `TaskAcceptanceDecisionService` when that file reached its
/// ratchet: these are payload shapes, and the decisions beside them are the
/// part worth reading. The refusal payloads stay there, with the grounds that
/// produce them.
class TaskAcceptancePayloads {
  const TaskAcceptancePayloads();

  /// A refusal, with [detail] merged into the payload the parent reads.
  McpToolResult refusal(
    String toolName,
    String code,
    Map<String, Object?> detail,
  ) => McpToolResult(
    toolName: toolName,
    isSuccess: false,
    result: jsonEncode({
      'ok': false,
      'code': code,
      'result_origin': 'refusal',
      ...detail,
    }),
  );

  McpToolResult writeFailed(String toolName) => McpToolResult(
    toolName: toolName,
    isSuccess: false,
    result: jsonEncode({
      'ok': false,
      'code': 'acceptance_write_failed',
      'result_origin': 'refusal',
      'required_action': 'The conversation could not be updated; retry once.',
    }),
  );

  McpToolResult accepted(String toolName, TaskAcceptanceContract contract) =>
      McpToolResult(
        toolName: toolName,
        isSuccess: true,
        result: jsonEncode({
          'ok': true,
          'accepted_task_id': contract.task.id,
          'evidence': contract.evidence,
          'premises': contract.premises,
        }),
      );
}
