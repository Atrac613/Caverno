// ChatNotifier decomposition collaborator: tool-loop-exhaustion-policy

/// Immutable facts used to decide whether bounded tool-loop recovery may run.
///
/// The iteration values retain the caller's exact limit comparison. The four
/// evidence flags must be derived from the pending calls and current batch
/// results owned by the same chat turn.
final class ToolLoopExhaustionDecisionInput {
  const ToolLoopExhaustionDecisionInput({
    required this.iteration,
    required this.maxIterations,
    required this.recoveryAlreadyAttempted,
    required this.hasPendingToolCalls,
    required this.hasCurrentBatchToolResults,
    required this.hasPendingFileMutation,
    required this.hasPendingWriteGitCommand,
  });

  final int iteration;
  final int maxIterations;
  final bool recoveryAlreadyAttempted;
  final bool hasPendingToolCalls;
  final bool hasCurrentBatchToolResults;
  final bool hasPendingFileMutation;
  final bool hasPendingWriteGitCommand;

  bool get iterationLimitReached => iteration >= maxIterations;
}

/// Decides whether one bounded tool-loop exhaustion recovery may be requested.
final class ToolLoopExhaustionPolicy {
  const ToolLoopExhaustionPolicy();

  bool shouldRequestRecovery(ToolLoopExhaustionDecisionInput input) {
    if (!input.iterationLimitReached) {
      return false;
    }
    if (input.recoveryAlreadyAttempted) {
      return false;
    }
    if (input.hasPendingFileMutation) {
      return false;
    }
    if (!input.hasPendingToolCalls) {
      return false;
    }
    if (!input.hasCurrentBatchToolResults) {
      return false;
    }
    if (input.hasPendingWriteGitCommand) {
      return false;
    }
    return true;
  }
}
