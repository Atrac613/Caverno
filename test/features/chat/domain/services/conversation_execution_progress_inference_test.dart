import 'package:caverno/features/chat/domain/services/conversation_execution_progress_inference.dart';
import 'package:caverno/features/chat/domain/services/final_answer_claim_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const taskTitle = 'Ship the execution handoff';

  test('extracts completion as an advisory claim', () {
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse:
          'Implemented the execution handoff and updated the validation flow.',
      taskTitle: taskTitle,
      isValidationRun: false,
    );

    expect(result.reportsCompletion, isTrue);
    expect(result.reportsBlocker, isFalse);
    expect(
      result.summary,
      'Implemented the execution handoff and updated the validation flow.',
    );
  });

  test('ignores completion words inside code spans', () {
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse:
          'Supported commands are `add <text>`, `list`, `done <id>`, and '
          '`delete <id>`.',
      taskTitle: taskTitle,
      isValidationRun: false,
    );

    expect(result.reportsCompletion, isFalse);
    expect(result.reportsBlocker, isFalse);
  });

  test('suppresses corrected unexecuted completion claims', () {
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse:
          'The TODO MVP is complete and all checks passed.\n\n'
          '${FinalAnswerClaimDetector.unexecutedCommandActionNotice}',
      fallbackAssistantResponse:
          'The TODO MVP is complete and all checks passed.',
      taskTitle: taskTitle,
      isValidationRun: false,
    );

    expect(result.hasUnexecutedEvidence, isTrue);
    expect(result.reportsCompletion, isFalse);
    expect(result.reportsValidationSuccess, isFalse);
  });

  test('extracts blocker narration without producing a status', () {
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse:
          'Validation failed because flutter test found one failing smoke test.',
      taskTitle: taskTitle,
      isValidationRun: true,
    );

    expect(result.reportsBlocker, isTrue);
    expect(result.reportsCompletion, isFalse);
    expect(result.reportsValidationSuccess, isFalse);
  });

  test('extracts validation success without producing a verdict', () {
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse:
          'The validation command ran successfully and tests passed.',
      taskTitle: taskTitle,
      isValidationRun: true,
    );

    expect(result.reportsValidationSuccess, isTrue);
    expect(result.reportsCompletion, isTrue);
    expect(result.reportsBlocker, isFalse);
  });

  test('keeps generic task-transition narration claim-free', () {
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse:
          'The previous saved task is complete. Continue immediately with '
          'the next pending saved task without asking for confirmation.',
      taskTitle: taskTitle,
      isValidationRun: false,
    );

    expect(result.reportsCompletion, isFalse);
    expect(result.reportsBlocker, isFalse);
  });

  test('recognizes explicit current-task completion during handoff', () {
    const explicitTitle =
        'Implement the ping logic in ping_cli.py using the subprocess module';
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse:
          'The previous task "$explicitTitle" is complete. The next task is '
          'to write the README.',
      taskTitle: explicitTitle,
      isValidationRun: false,
    );

    expect(result.reportsCompletion, isTrue);
  });

  test('treats a recoverable missing target as neither terminal claim', () {
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse:
          'The validation command was attempted before the target file '
          'existed. The goal now is to implement the task. Plan: create '
          '`ping_cli.py`.',
      taskTitle: 'Implement ping_cli.py',
      isValidationRun: false,
    );

    expect(result.reportsCompletion, isFalse);
    expect(result.reportsBlocker, isFalse);
  });

  test('prefers a fallback that carries a completion claim', () {
    final result = ConversationExecutionProgressInference.infer(
      assistantResponse: 'I reviewed the tool results and outlined next steps.',
      fallbackAssistantResponse:
          'The saved task is complete because validation passed.',
      taskTitle: taskTitle,
      isValidationRun: false,
    );

    expect(result.reportsCompletion, isTrue);
    expect(
      result.summary,
      'The saved task is complete because validation passed.',
    );
  });
}
