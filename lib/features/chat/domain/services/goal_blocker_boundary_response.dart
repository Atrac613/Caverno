import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import 'goal_update_ack.dart';
import 'project_task_terminal_status.dart';

/// Renders a recorded blocker without granting further execution authority.
abstract final class GoalBlockerBoundaryResponse {
  static McpToolResult refusal(String toolName) {
    const error =
        'The goal was marked blocked during this turn. End the turn and '
        'report the recorded blocker; further tool calls were not executed.';
    return McpToolResult(
      toolName: toolName,
      isSuccess: false,
      errorMessage: error,
      result: jsonEncode({
        'ok': false,
        'code': 'goal_blocked_turn',
        'executed': false,
        'error': error,
      }),
    );
  }

  static String report(String? reason, {required bool projectTask}) {
    if (projectTask) {
      return ProjectTaskTerminalStatus(
        outcome: GoalUpdateAckOutcome.blockerLogged,
        gaps: [?reason],
      ).incompleteResponse;
    }
    return 'The goal is blocked${reason == null ? '.' : ': $reason'}\n\n'
        'Resolve the blocker or ask the user before reactivating the goal.';
  }
}
