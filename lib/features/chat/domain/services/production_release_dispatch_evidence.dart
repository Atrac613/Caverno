import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'blocked_production_release_retry_policy.dart';
import 'production_release_approval_policy.dart';
import 'tool_call_execution_policy.dart';

// ChatNotifier decomposition collaborator: production-release-dispatch-evidence

/// Whether a production release already left the harness during this turn.
///
/// A release that ran must be answered with what happened, not with a fresh
/// approval demand. Re-gating it cannot succeed: the token that authorized it
/// is spent and dropped, a second attempt mints a new one, and the turn's
/// `ask_user_question` cache can only replay the answer carrying the old
/// token -- so no answer the user is able to give would satisfy the new one.
/// The session log this was built from (2026-09-20, gen-13) shows the cost:
/// the release had already succeeded, and the turn still spent six
/// `process_start` attempts and three approval prompts chasing an approval
/// that could never land.
final class ProductionReleaseDispatchEvidence {
  const ProductionReleaseDispatchEvidence();

  static const _policy = ProductionReleaseApprovalPolicy();
  static const _executionPolicy = ToolCallExecutionPolicy();

  /// Borrowed for [BlockedProductionReleaseRetryPolicy.normalizeCommand] alone,
  /// so "the same release command" means one thing across the gate and the
  /// retry path. Two spellings of one release must not be able to disagree
  /// about whether it already ran.
  static const _commandIdentity = BlockedProductionReleaseRetryPolicy();

  /// Whether [command] already ran as a release in [executedToolResults].
  ///
  /// Read from [ToolResultInfo.outcome] rather than remembered, so the fact
  /// cannot desync from what the turn actually did: a gate that recorded its
  /// own permission would count a release that a later guard, or the process
  /// launch itself, went on to refuse.
  ///
  /// `outcome` is the typed report a tool makes about its own execution, and
  /// an absent one means "unknown", never "succeeded" -- so a guard refusal,
  /// which carries no outcome at all, can never be mistaken for a dispatch.
  /// A launched process reports a process state; a foreground command reports
  /// an exit code. Either is proof the command left the harness.
  bool hasDispatched({
    required String command,
    required List<ToolResultInfo> executedToolResults,
  }) {
    final normalized = _commandIdentity.normalizeCommand(command);
    if (normalized.isEmpty) return false;
    for (final toolResult in executedToolResults) {
      final outcome = toolResult.outcome;
      if (outcome == null) continue;
      if (outcome.processState == null && outcome.exitCode == null) continue;
      if (!_executionPolicy.isCommandExecutionTool(toolResult.name)) continue;
      final executed = _executionPolicy.toolCommandArgument(
        toolResult.arguments,
      );
      if (executed == null) continue;
      if (_commandIdentity.normalizeCommand(executed) != normalized) continue;
      if (!_policy.looksLikeProductionReleaseCommand(executed)) continue;
      return true;
    }
    return false;
  }

  /// The refusal a repeated production release reports to the model.
  ///
  /// Reporting the real reason ends the approval chase at the first attempt,
  /// and keeps the release itself un-run: the point is not to make the second
  /// release grantable, it is to say it already happened.
  McpToolResult buildAlreadyExecutedResult({
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
}
