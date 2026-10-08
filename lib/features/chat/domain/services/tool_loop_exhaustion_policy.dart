import '../entities/tool_call_info.dart';
import 'ask_user_question/ask_user_question_policy.dart';
import 'file_mutation_evidence_policy.dart';
import 'git/git_write_confirmation_policy.dart';
import 'tool_call_execution_policy.dart';

// ChatNotifier decomposition collaborator: tool-loop-exhaustion-policy

/// Owner-turn facts for deciding whether bounded tool-loop recovery may run.
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
    this.hasPendingCommandExecution = false,
    this.hasPendingFileRead = false,
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
    hasPendingCommandExecution: pendingToolCalls.any(
      (call) =>
          const ToolCallExecutionPolicy().isCommandExecutionTool(call.name),
    ),
    hasPendingFileRead: pendingToolCalls.any(
      (call) => call.name.trim().toLowerCase() == 'read_file',
    ),
  );

  final int iteration;
  final int maxIterations;
  final bool recoveryAlreadyAttempted;
  final bool hasPendingToolCalls;
  final bool hasCurrentBatchToolResults;
  final bool hasPendingFileMutation;
  final bool hasPendingWriteGitCommand;

  /// Run a pending user question before recovery can answer it unasked.
  final bool hasPendingUserQuestion;
  final bool hasPendingCommandExecution;
  final bool hasPendingFileRead;

  bool get iterationLimitReached => iteration >= maxIterations;
}

/// Decides whether one bounded tool-loop exhaustion recovery may be requested.
final class ToolLoopExhaustionPolicy {
  const ToolLoopExhaustionPolicy();

  bool shouldRequestRecovery(ToolLoopExhaustionDecisionInput input) {
    return input.iterationLimitReached &&
        !input.recoveryAlreadyAttempted &&
        !input.hasPendingFileMutation &&
        input.hasPendingToolCalls &&
        input.hasCurrentBatchToolResults &&
        !input.hasPendingWriteGitCommand &&
        !input.hasPendingUserQuestion &&
        !input.hasPendingCommandExecution &&
        !input.hasPendingFileRead;
  }
}
