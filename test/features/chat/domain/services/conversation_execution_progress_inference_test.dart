import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_execution_progress_inference.dart';

void main() {
  ConversationWorkflowTask loadFixtureTask(String fixtureName) {
    final fixture =
        jsonDecode(File('test/fixtures/$fixtureName').readAsStringSync())
            as Map<String, dynamic>;
    return ConversationWorkflowTask.fromJson(
      fixture['task'] as Map<String, dynamic>,
    );
  }

  String loadFixtureAssistantResponse(String fixtureName) {
    final fixture =
        jsonDecode(File('test/fixtures/$fixtureName').readAsStringSync())
            as Map<String, dynamic>;
    return fixture['assistantResponse'] as String;
  }

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

  test(
    'keeps auto-continue transition narration in progress for the next task',
    () {
      final task = loadFixtureTask(
        'plan_mode_ping_cli_auto_continue_transition_replay.json',
      );
      final assistantResponse = loadFixtureAssistantResponse(
        'plan_mode_ping_cli_auto_continue_transition_replay.json',
      );

      final result = ConversationExecutionProgressInference.infer(
        assistantResponse: assistantResponse,
        task: task,
        isValidationRun: false,
      );

      expect(result.status, ConversationWorkflowTaskStatus.inProgress);
      expect(
        result.summary,
        startsWith(
          'The previous saved task is complete. Continue immediately with the next pending saved task without asking for confirmation.',
        ),
      );
    },
  );

  test(
    'prefers fallback completion evidence over a generic follow-up summary',
    () {
      final result = ConversationExecutionProgressInference.infer(
        assistantResponse:
            'I reviewed the tool results and outlined the next step.',
        fallbackAssistantResponse:
            'The saved task is complete because the validation passed.',
        task: task,
        isValidationRun: false,
      );

      expect(result.status, ConversationWorkflowTaskStatus.completed);
      expect(
        result.summary,
        'The saved task is complete because the validation passed.',
      );
    },
  );

  test(
    'treats validation command success narratives as completion evidence',
    () {
      final result = ConversationExecutionProgressInference.infer(
        assistantResponse:
            'The validation command `python3 ping_lib.py --help` was successful. The CLI interface is working as expected and correctly displays the help message.',
        task: task,
        isValidationRun: false,
      );

      expect(result.status, ConversationWorkflowTaskStatus.completed);
      expect(
        result.summary,
        'The validation command `python3 ping_lib.py --help` was successful. The CLI interface is working as expected and correctly displays the help message.',
      );
    },
  );
}
