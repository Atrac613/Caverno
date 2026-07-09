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

  test('completes on verifier success narration', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          'The verifier exited with code 0 and all diagnostics are empty. '
          'The TODO CLI app is complete and passes all verification checks.',
      tasks: const [],
    );

    expect(result.status, ConversationGoalStatus.completed);
    expect(result.hasCompletion, isTrue);
  });

  test('completes when final verifier success resolves earlier narration', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          'The remaining issue is unknown-id handling, so the task is not '
          'complete yet.\n\n'
          'I updated the implementation and ran the verifier again.\n\n'
          'The verifier exited with code 0 and all diagnostics are empty. '
          'The goal is complete.',
      tasks: const [],
    );

    expect(result.status, ConversationGoalStatus.completed);
    expect(result.hasCompletion, isTrue);
  });

  test(
    'does not complete when only a sub-item completed after remaining work',
    () {
      final result = ConversationGoalProgressInference.infer(
        assistantResponse:
            '\u6b8b\u308a2\u4ef6\u306f\u672a\u5bfe\u5fdc\u3067\u3059\u3002'
            '1\u4ef6\u76ee\u306e\u4fee\u6b63\u306f\u5b8c\u4e86\u3057\u307e\u3057\u305f\u3002',
        tasks: const [],
      );

      expect(result.status, isNull);
      expect(result.hasCompletion, isFalse);
    },
  );

  test('does not complete when generic tests passed follow remaining work', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          '\u6b8b\u308a\u306e\u30bf\u30b9\u30af\u306fX\u3067\u3059\u304c\u3001'
          '\u30c6\u30b9\u30c8\u304c\u901a\u308a\u307e\u3057\u305f\u3002',
      tasks: const [],
    );

    expect(result.status, isNull);
    expect(result.hasCompletion, isFalse);
  });

  test('completes when summary mentions remaining parsed arguments', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          'The test passed successfully. Here is a summary of what was done:\n\n'
          'Added logic to collect any remaining arguments after flag parsing '
          'as positional arguments.\n\n'
          'Goal complete. Tests passed.',
      tasks: const [],
    );

    expect(result.status, ConversationGoalStatus.completed);
    expect(result.hasCompletion, isTrue);
  });

  test('completes on Japanese saved report narration', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          '\u6771\u4eac\u306e\u660e\u65e5\uff082026\u5e746\u67083\u65e5\uff09\u306e\u5929\u6c17\u3092\u8abf\u3079\u3001'
          '\u30de\u30fc\u30af\u30c0\u30a6\u30f3\u5f62\u5f0f\u3067\u65e2\u5b58\u30d5\u30a1\u30a4\u30eb\u3092\u66f4\u65b0\u3057\u307e\u3057\u305f\u3002\n\n'
          '### \u5b8c\u4e86\u5831\u544a\n\n'
          '- **\u30d5\u30a1\u30a4\u30eb\u30d1\u30b9**: `/Users/noguwo/Documents/Workspace/tmp/tokyo_weather_2026-06-03.md`',
      tasks: const [],
    );

    expect(result.status, ConversationGoalStatus.completed);
    expect(result.hasCompletion, isTrue);
    expect(
      result.completionSummary,
      contains('\u66f4\u65b0\u3057\u307e\u3057\u305f'),
    );
  });

  test('does not complete on Japanese incomplete narration', () {
    final result = ConversationGoalProgressInference.infer(
      assistantResponse:
          '\u4e00\u90e8\u306e\u30d5\u30a1\u30a4\u30eb\u306f\u4fdd\u5b58\u3057\u307e\u3057\u305f\u304c\u3001'
          '\u691c\u8a3c\u30b9\u30c6\u30c3\u30d7\u304c\u6b8b\u3063\u3066\u3044\u307e\u3059\u3002',
      tasks: const [],
    );

    expect(result.status, isNull);
    expect(result.hasCompletion, isFalse);
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
    expect(result.blockerSignature, 'permission denied reading');
  });

  test('normalizes equivalent permission blocker wording', () {
    final signatures = [
      'Blocked: permission denied while reading `/tmp/project/settings.json`.',
      'Cannot proceed because permission was denied when reading /var/settings.json.',
      'I am blocked: access denied while reading the settings file.',
    ].map(ConversationGoalProgressInference.blockerSignatureFor).toSet();

    expect(signatures, {'permission denied reading'});
  });
}
