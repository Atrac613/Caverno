import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_execution_progress_inference.dart';

void main() {
  const task = ConversationWorkflowTask(
    id: 'task-1',
    title: 'Ship the execution handoff',
    status: ConversationWorkflowTaskStatus.inProgress,
    validationCommand: 'flutter test',
  );

  test('infers a completed task from assistant execution output', () {
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse:
          'Implemented the execution handoff and updated the validation flow.',
      task: task,
      isValidationRun: false,
    );

    expect(result.status, ConversationWorkflowTaskStatus.completed);
    expect(
      result.summary,
      'Implemented the execution handoff and updated the validation flow.',
    );
    expect(result.blockedReason, isNull);
  });

  test('treats plain complete phrasing as a completed task', () {
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse:
          'Task 1 is complete because the saved validation command passed.',
      task: task,
      isValidationRun: false,
    );

    expect(result.status, ConversationWorkflowTaskStatus.completed);
    expect(
      result.summary,
      'Task 1 is complete because the saved validation command passed.',
    );
  });

  test('infers blocked validation output from the assistant response', () {
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse:
          'Validation failed because flutter test found one failing smoke test.',
      task: task,
      isValidationRun: true,
    );

    expect(result.status, ConversationWorkflowTaskStatus.blocked);
    expect(
      result.validationStatus,
      ConversationExecutionValidationStatus.failed,
    );
    expect(
      result.validationSummary,
      'Validation failed because flutter test found one failing smoke test.',
    );
    expect(
      result.blockedReason,
      'Validation failed because flutter test found one failing smoke test.',
    );
  });

  test(
    'keeps validation runs in progress when the assistant response is neutral',
    () {
      final result = ConversationExecutionProgressInference.infer(
        assistantResponse:
            'Checked the current validation context and outlined the next step.',
        task: task,
        isValidationRun: true,
      );

      expect(result.status, ConversationWorkflowTaskStatus.inProgress);
      expect(
        result.validationStatus,
        ConversationExecutionValidationStatus.unknown,
      );
      expect(
        result.validationSummary,
        'Checked the current validation context and outlined the next step.',
      );
    },
  );
}
