import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../entities/mcp_tool_entity.dart';

/// Builds the refusal returned when an exact release already ran this turn.
McpToolResult buildProductionReleaseAlreadyExecutedResult({
  required String toolName,
  required String command,
}) {
  return McpToolResult(
    toolName: toolName,
    result: jsonEncode({
      'ok': false,
      'code': 'production_release_already_executed',
      ...ToolResultOrigin.refusal.marker,
      'error':
          'This production release command was already approved and '
          'dispatched earlier in this turn. It was not run again.',
      'command': command,
      'required_action':
          'Do not re-issue this release and do not ask for approval again. '
          'Report the result of the release that already ran, using the '
          'tool results already in this turn, and continue with the '
          'remaining work.',
    }),
    isSuccess: true,
  );
}
