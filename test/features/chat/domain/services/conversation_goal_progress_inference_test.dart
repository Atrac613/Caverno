import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_progress_inference.dart';
import 'package:flutter_test/flutter_test.dart';

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
    expect(result.hasStructuredCompletion, isTrue);
    expect(result.completionSummary, 'Validation passed.');
  });

  test('uses a stable summary when completed tasks have no narration', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse: '   ',
      tasks: const [
        ConversationWorkflowTask(
          id: 'task-1',
          title: 'Implement the fix',
          status: ConversationWorkflowTaskStatus.completed,
        ),
      ],
    );

    expect(result.status, ConversationGoalStatus.completed);
    expect(result.completionSummary, 'All saved workflow tasks are complete.');
  });

  test('does not complete while any saved task remains', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse: 'The goal is complete. All checks passed.',
      tasks: const [
        ConversationWorkflowTask(
          id: 'task-1',
          title: 'Implement the fix',
          status: ConversationWorkflowTaskStatus.completed,
        ),
        ConversationWorkflowTask(
          id: 'task-2',
          title: 'Run validation',
          status: ConversationWorkflowTaskStatus.pending,
        ),
      ],
    );

    expect(result.status, isNull);
    expect(result.hasStructuredCompletion, isFalse);
  });

  test('does not derive completion from prose without saved tasks', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          'The verifier exited with code 0. The goal is complete and all '
          'checks passed.',
      tasks: const [],
    );

    expect(result.status, isNull);
    expect(result.hasStructuredCompletion, isFalse);
  });

  test('does not derive a blocked goal from prose', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          'Blocked: permission denied while reading the project settings.',
      tasks: const [],
    );

    expect(result.status, isNull);
    expect(result.completionSummary, isNull);
  });
}
