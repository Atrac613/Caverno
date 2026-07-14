import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/services/pending_action_length_recovery_policy.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';

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

  test('builds a compact executable retry prompt', () {
    final prompt = policy.buildRetryPrompt(incompleteEvidence);

    expect(prompt, contains('1 unresolved Error diagnostic(s)'));
    expect(prompt, contains('exactly one available tool call'));
    expect(prompt, contains('Do not provide analysis'));
  });
}
