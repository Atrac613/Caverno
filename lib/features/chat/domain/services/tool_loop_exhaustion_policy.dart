import '../entities/tool_call_info.dart';
import 'ask_user_question_policy.dart';
import 'file_mutation_evidence_policy.dart';
import 'git_write_confirmation_policy.dart';

// ChatNotifier decomposition collaborator: tool-loop-exhaustion-policy

/// Immutable facts used to decide whether bounded tool-loop recovery may run.
///
/// The iteration values retain the caller's exact limit comparison. The
/// evidence flags must be derived from the pending calls and current batch
/// results owned by the same chat turn; the `fromPendingCalls` factory derives
/// the pending-call ones, so a new one cannot be left out at the call site.
final class ToolLoopExhaustionDecisionInput {
  const ToolLoopExhaustionDecisionInput({
    required this.iteration,
    required this.maxIterations,
    required this.recoveryAlreadyAttempted,
    required this.hasPendingToolCalls,
    required this.hasCurrentBatchToolResults,
    required this.hasPendingFileMutation,
    required this.hasPendingWriteGitCommand,
    required this.hasPendingUserQuestion,
  });

  factory ToolLoopExhaustionDecisionInput.fromPendingCalls({
    required int iteration,
    required int maxIterations,
    required bool recoveryAlreadyAttempted,
    required List<ToolCallInfo> pendingToolCalls,
    required bool hasCurrentBatchToolResults,
  }) => ToolLoopExhaustionDecisionInput(
    iteration: iteration,
    maxIterations: maxIterations,
    recoveryAlreadyAttempted: recoveryAlreadyAttempted,
    hasPendingToolCalls: pendingToolCalls.isNotEmpty,
    hasCurrentBatchToolResults: hasCurrentBatchToolResults,
    hasPendingFileMutation: pendingToolCalls.any(
      (call) =>
          const FileMutationEvidencePolicy().isMutationToolName(call.name),
    ),
    hasPendingWriteGitCommand: pendingToolCalls.any(
      const GitWriteConfirmationPolicy().isWriteGitCommandToolCall,
    ),
    hasPendingUserQuestion: pendingToolCalls.any(
      (call) => call.name.trim().toLowerCase() == askUserQuestionToolName,
    ),
  );

  final int iteration;
  final int maxIterations;
  final bool recoveryAlreadyAttempted;
  final bool hasPendingToolCalls;
  final bool hasCurrentBatchToolResults;
  final bool hasPendingFileMutation;
  final bool hasPendingWriteGitCommand;

  /// The model stopped to ask the user something when the budget ran out.
  ///
  /// Recovery tells it to finish without asking for confirmation, so it
  /// answers its own question: session dd50d110 hit the limit with only
  /// `ask_user_question` pending -- which version to release as -- and the
  /// recovery reply settled it unasked. Declining recovery runs the pending
  /// batch before finalization instead, which puts the question to the user.
  final bool hasPendingUserQuestion;

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
    if (input.hasPendingUserQuestion) {
      return false;
    }
    return true;
  }
}
