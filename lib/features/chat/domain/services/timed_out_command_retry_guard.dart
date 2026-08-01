import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'immutable_json_snapshot.dart';
import 'tool_call_execution_policy.dart';

// ChatNotifier decomposition collaborator: timed-out-command-retry-guard

/// Immutable owner-turn command and result facts for one retry decision.
final class TimedOutCommandRetryInput {
  TimedOutCommandRetryInput({
    required ToolCallInfo toolCall,
    required List<ToolResultInfo> executedToolResults,
  }) : toolCall = _freezeToolCall(toolCall),
       executedToolResults = List<ToolResultInfo>.unmodifiable(
         executedToolResults.map(_freezeToolResult),
       );

  final ToolCallInfo toolCall;
  final List<ToolResultInfo> executedToolResults;
}

/// Blocks an unchanged command retry after its latest matching timeout.
final class TimedOutCommandRetryGuard {
  const TimedOutCommandRetryGuard();

  static const blockedCode = 'command_retry_after_timeout_blocked';
  static const _executionPolicy = ToolCallExecutionPolicy();

  McpToolResult? evaluate(TimedOutCommandRetryInput input) {
    final toolCall = input.toolCall;
    if (!_executionPolicy.isCommandExecutionTool(toolCall.name) ||
        _executionPolicy.isReadOnlyCommandExecutionToolCall(toolCall)) {
      return null;
    }
    final command = _executionPolicy.toolCommandArgument(toolCall.arguments);
    if (command == null) {
      return null;
    }

    final normalizedCommand = _executionPolicy
        .normalizeToolCommandForComparison(command);
    ToolResultInfo? matchingTimedOutResult;
    for (final result in input.executedToolResults.reversed) {
      if (_executionPolicy.isCommandExecutionTool(result.name) &&
          _executionPolicy.toolResultTimedOut(result) &&
          _executionPolicy.toolResultCommandMatches(
            result,
            normalizedCommand: normalizedCommand,
          )) {
        matchingTimedOutResult = result;
        break;
      }
    }
    if (matchingTimedOutResult == null) {
      return null;
    }

    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'error':
            'The same command already timed out. Automatic retry is blocked '
            'because the previous process may still be running or may have '
            'partially completed side effects.',
        'code': blockedCode,
        'command': command,
        'previous_error': _executionPolicy.toolResultErrorText(
          matchingTimedOutResult,
        ),
        'required_action':
            'Ask the user before retrying, or verify the previous process state '
            'with a read-only inspection command first.',
      }),
      isSuccess: true,
    );
  }
}

ToolCallInfo _freezeToolCall(ToolCallInfo source) {
  return ToolCallInfo(
    id: source.id,
    name: source.name,
    arguments: ImmutableJsonSnapshot.freezeMap(source.arguments),
  );
}

ToolResultInfo _freezeToolResult(ToolResultInfo source) {
  return ToolResultInfo(
    id: source.id,
    name: source.name,
    arguments: ImmutableJsonSnapshot.freezeMap(source.arguments),
    result: source.result,
  );
}
