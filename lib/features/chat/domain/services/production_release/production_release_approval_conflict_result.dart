import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../entities/mcp_tool_entity.dart';
import 'blocked_production_release_retry_contract.dart';

const String productionReleaseApprovalConflictCode =
    'production_release_approval_conflict';

/// Refuses B while pending release A owns the conversation's approval token.
McpToolResult buildProductionReleaseApprovalConflictResult({
  required String toolName,
  required String command,
  required PendingBlockedRelease pending,
}) {
  final pendingDirectory = pending.workingDirectory?.trim();
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': productionReleaseApprovalConflictCode,
      ...ToolResultOrigin.refusal.marker,
      'error':
          'Another production release command is already awaiting approval '
          'in this conversation.',
      'command': command,
      'pending_command': pending.command,
      // The exact arguments, so a retry can reproduce the pending execution
      // instead of guessing which argument made this one differ.
      'pending_tool': pending.toolName,
      if (pendingDirectory != null && pendingDirectory.isNotEmpty)
        'pending_working_directory': pendingDirectory,
      'pending_background': pending.background,
      'required_action':
          'Do not ask for approval for this command. Continue only with the '
          'pending production release command, issued with exactly the '
          'pending tool, command, working directory and background values '
          'shown here, or wait for that approval flow to finish before '
          'proposing another release.',
    }),
    isSuccess: true,
  );
}
