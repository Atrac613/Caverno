import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/tool_loop_exhaustion_policy.dart';

/// Whether to extend the tool-loop budget, instead of finalizing, when the
/// limit falls on a pending file edit.
///
/// [ToolLoopExhaustionPolicy.shouldRequestRecovery] declines that case to keep
/// the declared edit, so a turn mid-implementation ran one last edit and then
/// had to write a tools-free final answer about unfinished work: in session
/// 78bbf53c a farm subtask stopped this way with its edits succeeding and its
/// tests passing. Only a turn that has already changed files qualifies, and
/// ExecutionBudgetPolicy caps the total extension.
final class PendingEditBudgetExtension {
  const PendingEditBudgetExtension();

  bool applies(
    ToolLoopExhaustionDecisionInput input, {
    required List<ToolResultInfo> executedToolResults,
  }) =>
      input.iterationLimitReached &&
      input.hasPendingFileMutation &&
      !input.hasPendingWriteGitCommand &&
      !input.hasPendingUserQuestion &&
      executedToolResults.any(
        (result) =>
            result.outcome?.fileMutations.any(
              (change) => change.changed == true,
            ) ==
            true,
      );
}
