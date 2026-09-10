import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/mcp_tool_entity.dart';
import '../entities/subagent_task.dart';
import '../entities/tool_call_info.dart';
import 'material_contract_assumption_guard.dart';
import 'tool_call_execution_policy.dart';

/// Keeps command observations distinct from accepting a delegated result.
class SubagentCommandObservation {
  bool _success = false;

  /// A child may mutate before its overall run fails or is cancelled.
  static bool changesWorkspace(ToolCallInfo call, McpToolResult result) =>
      result.outcome?.fileMutations.any((change) => change.changed != false) ==
          true ||
      (result.isSuccess &&
          const MaterialContractAssumptionGuard().isContractMutation(call));

  static McpToolResult failed(String toolName, SubagentTask task) =>
      McpToolResult(
        toolName: toolName,
        result: jsonEncode({
          'status': 'failed',
          'task_id': task.id,
          'description': task.description,
          'error': task.error ?? 'Subagent failed',
        }),
        isSuccess: false,
        errorMessage: task.error ?? 'Subagent failed',
      );

  void observe(ToolCallInfo call, McpToolResult result) {
    const policy = ToolCallExecutionPolicy();
    if (policy.isFileMutationToolCall(call)) _success = false;
    if (!policy.isCommandExecutionTool(call.name)) return;
    final command = call.arguments['command'];
    // A shell-list exit status describes its last command only. Conservatively
    // omit compound expressions rather than interpreting model-written output.
    final compound =
        command is String && RegExp(r'[;&|\n\r`$()]').hasMatch(command);
    _success = !compound && result.isSuccess && result.outcome?.exitCode == 0;
  }

  McpToolResult completed(String toolName, SubagentTask task) => McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'status': 'completed',
      'task_id': task.id,
      'description': task.description,
      'summary': task.resultSummary,
      'accepted': false,
    }),
    outcome: _success ? const ToolOutcome(exitCode: 0) : null,
    isSuccess: true,
  );
}
