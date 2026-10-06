import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../../chat/domain/entities/mcp_tool_entity.dart';
import '../../../chat/domain/entities/tool_call_info.dart';
import '../../../chat/domain/services/tool_definition_search_service.dart';

/// Keeps an unattended personal-eval replay off the user's screen.
///
/// A replay runs overnight with no interactive approval, against the same
/// browser pane and desktop the user works in. Coding replays still need file
/// edits and commands, so the replay cannot adopt RoutineToolPolicy whole. The
/// tools that drive the visible browser or the desktop are refused here, as
/// routines refuse them.
///
/// Measured 2026-10-02 on the one case replayed nightly since 2026-08-17:
/// browser calls ran on 18 nights. 15 ended in `browser_not_ready` because the
/// screen was locked, and each of those left the pane armed to open at the next
/// unlock. The one call that succeeded loaded in the user's on-screen pane.
/// The catalog also carried 19 `computer_*` tools, including pointer, keyboard
/// and audio-recording actions.
class PersonalEvalReplayToolPolicy {
  const PersonalEvalReplayToolPolicy._();

  /// Built-in tool families. Remote MCP servers cannot claim these prefixes,
  /// so a prefix match never catches a third-party tool.
  static const Set<String> deniedToolNamePrefixes = {'browser_', 'computer_'};

  static bool isDenied(String toolName) =>
      deniedToolNamePrefixes.any(toolName.startsWith);

  static List<Map<String, dynamic>> filterDefinitions(
    List<Map<String, dynamic>> definitions,
  ) => definitions
      .where(
        (definition) => !isDenied(
          ToolDefinitionSearchService.toolNameFromDefinition(definition) ?? '',
        ),
      )
      .toList(growable: false);

  /// Refuses a denied tool even when the model names one that is not in the
  /// catalog it was given.
  static Future<McpToolResult> Function(ToolCallInfo toolCall) guard(
    Future<McpToolResult> Function(ToolCallInfo toolCall) dispatch,
  ) =>
      (toolCall) async =>
          isDenied(toolCall.name) ? deniedResult(toolCall) : dispatch(toolCall);

  static McpToolResult deniedResult(ToolCallInfo toolCall) {
    const message =
        'Personal eval replays run unattended and cannot drive the on-screen '
        'browser or desktop. Use the search, fetch, file, and command tools '
        'instead.';
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'ok': false,
        'code': 'permission_denied',
        'reason': 'personal_eval_replay_screen_tool_denied',
        ...ToolResultOrigin.refusal.marker,
        'error': message,
        'tool': toolCall.name,
      }),
      isSuccess: false,
      errorMessage: 'Personal eval replay blocked a browser or desktop tool',
    );
  }
}
