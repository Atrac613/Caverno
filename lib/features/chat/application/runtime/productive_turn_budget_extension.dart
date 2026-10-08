import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/tool_loop/tool_loop_exhaustion_policy.dart';

/// Whether to extend the tool-loop budget, instead of finalizing, when a turn
/// that has changed files reaches the limit with work still pending.
///
/// The one-time exhaustion recovery declines a pending file edit, and runs
/// only once. A turn mid-implementation therefore finalized with work pending
/// and wrote a tools-free answer about unfinished work: session 78bbf53c with
/// an edit pending, and session 02fec5c8 with a read pending right after its
/// last edit, which left the verification the completion gate requires
/// unrun. ExecutionBudgetPolicy caps the total extension.
final class ProductiveTurnBudgetExtension {
  const ProductiveTurnBudgetExtension();

  bool applies(
    ToolLoopExhaustionDecisionInput input, {
    required List<ToolResultInfo> executedToolResults,
  }) =>
      input.iterationLimitReached &&
      input.hasPendingToolCalls &&
      !input.hasPendingWriteGitCommand &&
      !input.hasPendingUserQuestion &&
      !const ToolLoopExhaustionPolicy().shouldRequestRecovery(input) &&
      executedToolResults.any(
        (result) =>
            result.outcome?.fileMutations.any(
              (change) => change.changed == true,
            ) ==
            true,
      );
}
