import 'package:caverno/features/chat/domain/services/pending_action_length_recovery_policy.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = PendingActionLengthRecoveryPolicy();
  const incompleteEvidence = ToolResultCompletionEvidence(
    unresolvedErrorCount: 1,
    unresolvedErrorPaths: ['lib/main.dart'],
  );

  test('requests one action retry for truncated incomplete coding work', () {
    expect(
      policy.shouldRequestActionOnlyRecovery(
        finishReason: 'length',
        isCodingWorkspace: true,
        hasAvailableActionTools: true,
        retryAlreadyUsed: false,
        completionEvidence: incompleteEvidence,
      ),
      isTrue,
    );
  });

  test('does not retry completed or non-coding work', () {
    expect(
      policy.shouldRequestActionOnlyRecovery(
        finishReason: 'length',
        isCodingWorkspace: true,
        hasAvailableActionTools: true,
        retryAlreadyUsed: false,
        completionEvidence: const ToolResultCompletionEvidence(),
      ),
      isFalse,
    );
    expect(
      policy.shouldRequestActionOnlyRecovery(
        finishReason: 'length',
        isCodingWorkspace: false,
        hasAvailableActionTools: true,
        retryAlreadyUsed: false,
        completionEvidence: incompleteEvidence,
      ),
      isFalse,
    );
  });

  test('does not retry without tools or after the bounded retry was used', () {
    expect(
      policy.shouldRequestActionOnlyRecovery(
        finishReason: 'length',
        isCodingWorkspace: true,
        hasAvailableActionTools: false,
        retryAlreadyUsed: false,
        completionEvidence: incompleteEvidence,
      ),
      isFalse,
    );
    expect(
      policy.shouldRequestActionOnlyRecovery(
        finishReason: 'max_tokens',
        isCodingWorkspace: true,
        hasAvailableActionTools: true,
        retryAlreadyUsed: true,
        completionEvidence: incompleteEvidence,
      ),
      isFalse,
    );
  });

  test('does not treat a normal stop as length truncation', () {
    expect(
      policy.shouldRequestActionOnlyRecovery(
        finishReason: 'stop',
        isCodingWorkspace: true,
        hasAvailableActionTools: true,
        retryAlreadyUsed: false,
        completionEvidence: incompleteEvidence,
      ),
      isFalse,
    );
  });

  test('resumes a turn cut off before it acted on anything', () {
    // Session 5206eab6: ten iterations of reads and git queries, the eleventh
    // cut off at the token cap with no visible answer. Nothing had been
    // changed, so every incompleteness signal was false -- and that is exactly
    // the turn worth resuming.
    const nothingDoneYet = ToolResultCompletionEvidence();
    expect(nothingDoneYet.hasIncompleteEvidence, isFalse);

    expect(
      policy.shouldRequestActionOnlyRecovery(
        finishReason: 'stop',
        cutOffBeforeAnswer: true,
        isCodingWorkspace: true,
        hasAvailableActionTools: true,
        retryAlreadyUsed: false,
        completionEvidence: nothingDoneYet,
      ),
      isTrue,
      reason:
          'the reply ran out of tokens before acting, which the regenerated '
          'answer\'s own finish reason hides',
    );
  });

  test('a cut-off reply still respects the other gates', () {
    const nothingDoneYet = ToolResultCompletionEvidence();
    for (final gate in <String>['workspace', 'tools', 'retry']) {
      expect(
        policy.shouldRequestActionOnlyRecovery(
          finishReason: 'stop',
          cutOffBeforeAnswer: true,
          isCodingWorkspace: gate != 'workspace',
          hasAvailableActionTools: gate != 'tools',
          retryAlreadyUsed: gate == 'retry',
          completionEvidence: nothingDoneYet,
        ),
        isFalse,
        reason: gate,
      );
    }
  });

  test('a finished turn that changed nothing is left alone', () {
    // Without the cut-off fact this is just a turn that answered.
    expect(
      policy.shouldRequestActionOnlyRecovery(
        finishReason: 'stop',
        isCodingWorkspace: true,
        hasAvailableActionTools: true,
        retryAlreadyUsed: false,
        completionEvidence: const ToolResultCompletionEvidence(),
      ),
      isFalse,
    );
  });

  test('builds a compact executable retry prompt', () {
    final prompt = policy.buildRetryPrompt(incompleteEvidence);

    expect(prompt, contains('1 unresolved Error diagnostic(s)'));
    expect(prompt, contains('exactly one available tool call'));
    expect(prompt, contains('Do not provide analysis'));
  });
}
