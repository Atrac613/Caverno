import 'dart:convert';

import '../../data/datasources/chat_datasource.dart';
import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';

// ChatNotifier decomposition collaborator: truncated-tool-call-arguments-guard

/// The guard is stateless, so callers share one instance rather than holding a
/// field for it.
const truncatedToolCallArgumentsGuard = TruncatedToolCallArgumentsGuard();

/// Answers tool calls whose arguments were lost to the output-token limit.
///
/// A completion that stops on `length` mid-generation can still carry tool
/// calls, with arguments that parsed empty. Executing those produces a generic
/// missing-argument error, and the model cannot tell that its own generation
/// was cut off — so it abandons whatever it was doing, which is usually a long
/// verification chain, instead of re-issuing the call in smaller pieces.
///
/// Deliberately stateless and free of notifier types: the caller decides which
/// completion was truncated and records the turn transform, so this stays
/// testable against a bare [ToolCallInfo].
final class TruncatedToolCallArgumentsGuard {
  const TruncatedToolCallArgumentsGuard();

  /// The ids of [result]'s tool calls that the truncation ate.
  ///
  /// Empty unless [truncated], because a completion that finished normally
  /// with empty arguments is a model error rather than a lost generation.
  Set<String> casualtyToolCallIds(
    ChatCompletionResult result, {
    required bool truncated,
  }) {
    if (!result.hasToolCalls || !truncated) {
      return const <String>{};
    }
    return result.toolCalls!
        .where((toolCall) => toolCall.arguments.isEmpty)
        .map((toolCall) => toolCall.id)
        .toSet();
  }

  /// Whether [toolCall] is one of the casualties in [casualtyToolCallIds], and
  /// so must be answered rather than executed.
  bool isCasualty(ToolCallInfo toolCall, Set<String> casualtyToolCallIds) =>
      casualtyToolCallIds.contains(toolCall.id) && toolCall.arguments.isEmpty;

  /// The diagnostic to return in place of executing [toolCall].
  McpToolResult diagnosticFor(ToolCallInfo toolCall) => McpToolResult(
    toolName: toolCall.name,
    result: jsonEncode({
      'ok': false,
      'code': 'tool_call_arguments_truncated',
      'error':
          'The ${toolCall.name} arguments were lost because the response '
          'hit the output token limit (finish_reason=length) while '
          'generating them.',
      'required_action':
          'Re-issue the ${toolCall.name} call you intended. If the '
          'arguments were long, split the work into several smaller tool '
          'calls instead of one large call, and keep each command short.',
    }),
    isSuccess: false,
    errorMessage:
        'Tool call arguments were truncated by the output token limit; '
        're-issue the intended call as smaller separate calls.',
  );
}
