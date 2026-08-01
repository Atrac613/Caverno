import 'package:caverno/features/chat/domain/services/tool_terminal_response_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolTerminalResponsePolicy hidden evidence delegation', () {
    final policy = _policy();

    test('preserves the extracted score matrix', () {
      expect(policy.hiddenAssistantEvidenceScore(''), 0);
      expect(policy.hiddenAssistantEvidenceScore('next task'), 1);
      expect(policy.hiddenAssistantEvidenceScore('task complete'), 2);
      expect(
        policy.hiddenAssistantEvidenceScore(
          'task complete; validation passed; saved task',
        ),
        5,
      );
      expect(
        policy.hiddenAssistantEvidenceScore('task complete but tests failed'),
        2,
      );
    });

    test('uses the delegated score for recovery acceptance', () {
      expect(policy.shouldAcceptRecoveryFinalTextResponse(''), isFalse);
      expect(
        policy.shouldAcceptRecoveryFinalTextResponse('Next task'),
        isFalse,
      );
      expect(
        policy.shouldAcceptRecoveryFinalTextResponse('Task complete'),
        isTrue,
      );
      expect(
        policy.shouldAcceptRecoveryFinalTextResponse(
          'Task complete but tests failed',
        ),
        isTrue,
      );
    });

    test('keeps terminal task-reference precedence unchanged', () {
      expect(
        policy.shouldAcceptTerminalToolRoleFinalTextResponse(
          'Task "task-1" complete.',
        ),
        isTrue,
      );
      expect(
        policy.shouldAcceptTerminalToolRoleFinalTextResponse(
          'Task "task-1" tests passed.',
        ),
        isFalse,
      );
      expect(
        policy.shouldAcceptTerminalToolRoleFinalTextResponse(
          'Task "task-1" complete. Would you like another task?',
        ),
        isFalse,
      );
    });
  });
}

ToolTerminalResponsePolicy _policy() {
  return ToolTerminalResponsePolicy(
    looksLikeUnexecutedToolRequest: (_) => false,
    looksLikePlanOnlyFinalToolAnswer: (_) => false,
    looksLikePendingToolActionResponse: (_) => false,
    looksLikeStructuredToolRequest: (_) => false,
    containsAnyCodeUnitSequence: (_, _) => false,
    containsCjkBlockerMarker: (_) => false,
    containsCjkMissingEvidenceMarker: (_) => false,
  );
}
