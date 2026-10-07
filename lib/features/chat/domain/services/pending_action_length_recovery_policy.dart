import 'tool_result_prompt_builder.dart';

/// Routes a length-truncated response back to executable coding work when the
/// task is demonstrably unfinished.
///
/// Tool evidence proves that in the usual case: a mutation nothing verified, an
/// unresolved error, an unexecuted action claim. It cannot prove it when the
/// reply ran out of tokens *before* the model acted, because a turn that only
/// looked at things leaves nothing incomplete behind -- which is exactly the
/// turn most worth resuming. Session 5206eab6 is that case: ten iterations of
/// reads and git queries, the eleventh cut off at the cap with no visible
/// answer, and every incompleteness signal false because nothing had been
/// changed yet. [cutOffBeforeAnswer] carries that fact in on its own.
class PendingActionLengthRecoveryPolicy {
  const PendingActionLengthRecoveryPolicy();

  bool shouldRequestActionOnlyRecovery({
    required String? finishReason,
    required bool isCodingWorkspace,
    required bool hasAvailableActionTools,
    required bool retryAlreadyUsed,
    required ToolResultCompletionEvidence completionEvidence,
    bool cutOffBeforeAnswer = false,
  }) {
    return (_isLengthTruncated(finishReason) || cutOffBeforeAnswer) &&
        canPrepareActionOnlyRecovery(
          isCodingWorkspace: isCodingWorkspace,
          hasAvailableActionTools: hasAvailableActionTools,
          retryAlreadyUsed: retryAlreadyUsed,
          completionEvidence: completionEvidence,
          cutOffBeforeAnswer: cutOffBeforeAnswer,
        );
  }

  bool canPrepareActionOnlyRecovery({
    required bool isCodingWorkspace,
    required bool hasAvailableActionTools,
    required bool retryAlreadyUsed,
    required ToolResultCompletionEvidence completionEvidence,
    bool cutOffBeforeAnswer = false,
  }) {
    return isCodingWorkspace &&
        hasAvailableActionTools &&
        !retryAlreadyUsed &&
        (completionEvidence.hasIncompleteEvidence || cutOffBeforeAnswer);
  }

  String buildRetryPrompt(ToolResultCompletionEvidence completionEvidence) {
    return '''
The previous response hit the output-token limit while executable work remains incomplete.

Incomplete evidence: ${completionEvidence.summary}

Do not provide analysis, a plan, or a final answer. Issue exactly one available tool call now that directly advances the incomplete work. Reuse the diagnostics and file contents already provided. Prefer a targeted edit over a full rewrite, and split an oversized change into a smaller edit. If verification is the pending action, call the available verifier. If no safe tool action is possible, state one concise concrete blocker.
'''
        .trim();
  }

  bool _isLengthTruncated(String? finishReason) {
    switch (finishReason?.trim().toLowerCase()) {
      case 'length':
      case 'max_tokens':
      case 'max_output_tokens':
        return true;
    }
    return false;
  }
}
