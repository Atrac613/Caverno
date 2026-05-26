import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_progress_inference.dart';

void main() {
  test('marks the goal complete when every saved task is complete', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse: 'Validation passed.',
      tasks: const [
        ConversationWorkflowTask(
          id: 'task-1',
          title: 'Implement the fix',
          status: ConversationWorkflowTaskStatus.completed,
        ),
        ConversationWorkflowTask(
          id: 'task-2',
          title: 'Run validation',
          status: ConversationWorkflowTaskStatus.completed,
        ),
      ],
    );

    expect(result.status, ConversationGoalStatus.completed);
    expect(result.completionSummary, 'Validation passed.');
  });

  test('does not complete on incomplete progress narration', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          'The implementation is not complete yet; one validation step remains.',
      tasks: const [
        ConversationWorkflowTask(
          id: 'task-1',
          title: 'Implement the fix',
          status: ConversationWorkflowTaskStatus.inProgress,
        ),
      ],
    );

    expect(result.status, isNull);
    expect(result.hasCompletion, isFalse);
  });

  test('does not complete on negative validation narration', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          'Not all tests passed. The login regression still fails.',
      tasks: const [],
    );

    expect(result.status, isNull);
    expect(result.hasCompletion, isFalse);
  });

  test('completes when an earlier failure is followed by rerun success', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          'Goal complete. Tests passed.\n\n'
          'The initial test run failed because the greeting was incomplete. '
          'I updated the implementation, and the subsequent test run exited '
          'with code 0 and printed the expected marker, confirming the fix.',
      tasks: const [],
    );

    expect(result.status, ConversationGoalStatus.completed);
    expect(result.hasCompletion, isTrue);
  });

  test('completes on successfully completed goal narration', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          'I have successfully completed the coding goal. The validation '
          'command exited with code 0 and printed the expected marker.',
      tasks: const [],
    );

    expect(result.status, ConversationGoalStatus.completed);
    expect(result.hasCompletion, isTrue);
  });

  test('does not complete when failure narration has no recovery evidence', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          'Goal complete. Tests passed, but the final validation failed with '
          'a syntax error.',
      tasks: const [],
    );

    expect(result.status, isNull);
    expect(result.hasCompletion, isFalse);
  });

  test('extracts a stable blocker signature from blocked output', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          'Blocked: permission denied while reading `/tmp/project/config.json`.',
      tasks: const [],
    );

    expect(result.status, isNull);
    expect(result.hasBlocker, isTrue);
    expect(result.blockerSignature, 'blocked permission denied while reading');
  });
}
