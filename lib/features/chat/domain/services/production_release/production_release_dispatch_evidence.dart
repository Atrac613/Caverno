import '../../entities/tool_call_info.dart';
import '../tool_loop/tool_call_execution_policy.dart';
import 'production_release_approval_policy.dart';
import 'production_release_execution_identity.dart';

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
  static const _executionIdentity = ProductionReleaseExecutionIdentity();

  /// Whether [toolCall] already ran as the same exact release execution in
  /// [executedToolResults].
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
    required ToolCallInfo toolCall,
    required List<ToolResultInfo> executedToolResults,
    Map<String, dynamic> Function(ToolCallInfo toolCall)?
    resolveExecutionArguments,
  }) {
    final resolver = resolveExecutionArguments ?? _identityArguments;
    final expectedIdentity = _executionIdentity.forDispatch(
      toolCall,
      resolveArguments: resolver,
    );
    for (final toolResult in executedToolResults) {
      final outcome = toolResult.outcome;
      if (outcome == null) continue;
      if (outcome.processState == null && outcome.exitCode == null) continue;
      if (!_executionPolicy.isCommandExecutionTool(toolResult.name)) continue;
      final executed = _executionPolicy.toolCommandArgument(
        toolResult.arguments,
      );
      if (executed == null) continue;
      if (!_policy.looksLikeProductionReleaseCommand(executed)) continue;
      final executedToolCall = ToolCallInfo(
        id: toolResult.id,
        name: toolResult.name,
        arguments: toolResult.arguments,
      );
      final executedIdentity = _executionIdentity.forDispatch(
        executedToolCall,
        resolveArguments: resolver,
      );
      if (executedIdentity != expectedIdentity) continue;
      return true;
    }
    return false;
  }

  static Map<String, dynamic> _identityArguments(ToolCallInfo toolCall) =>
      toolCall.arguments;
}
