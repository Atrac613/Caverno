import 'tool_result_prompt_builder.dart';

/// Routes a length-truncated response back to executable coding work when the
/// current tool evidence still proves that the task is incomplete.
class PendingActionLengthRecoveryPolicy {
  const PendingActionLengthRecoveryPolicy();

  bool shouldRequestActionOnlyRecovery({
    required String? finishReason,
    required bool isCodingWorkspace,
    required bool hasAvailableActionTools,
    required bool retryAlreadyUsed,
    required ToolResultCompletionEvidence completionEvidence,
  }) {
    return _isLengthTruncated(finishReason) &&
        canPrepareActionOnlyRecovery(
          isCodingWorkspace: isCodingWorkspace,
          hasAvailableActionTools: hasAvailableActionTools,
          retryAlreadyUsed: retryAlreadyUsed,
          completionEvidence: completionEvidence,
        );
  }

  bool canPrepareActionOnlyRecovery({
    required bool isCodingWorkspace,
    required bool hasAvailableActionTools,
    required bool retryAlreadyUsed,
    required ToolResultCompletionEvidence completionEvidence,
  }) {
    return isCodingWorkspace &&
        hasAvailableActionTools &&
        !retryAlreadyUsed &&
        completionEvidence.hasIncompleteEvidence;
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
