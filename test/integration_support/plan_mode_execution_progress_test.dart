import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_execution_progress.dart';

void main() {
  group('executionLogsContainWorkflowCompleted', () {
    test('detects English all-tasks-complete markers', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'The validation passed.',
          'All planned tasks are complete.',
        ]),
        isTrue,
      );
    });

    test('detects Japanese all-tasks-complete markers', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'タスク「Verify ping execution with localhost」が完了しました。',
          'すべての予定されていたタスクが完了しました。',
        ]),
        isTrue,
      );
    });

    test('ignores single-task completion without workflow completion', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'The task is complete.',
          'Continue immediately with the next pending saved task.',
        ]),
        isFalse,
      );
    });

    test('detects terminal task completion before final answer streaming', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'The previous saved task is complete. Continue immediately with the next pending saved task without asking for confirmation.',
          'The task "Create test_ping.py to validate the CLI" has been completed successfully.',
          '[Tool] Resending tool results as user message',
          '[LLM] ========== streamChatCompletion ==========',
        ]),
        isTrue,
      );
    });

    test(
      'detects final task completion when the final answer request repeats the handoff prompt',
      () {
        expect(
          executionLogsContainWorkflowCompleted(const <String>[
            'The task "Verify the CLI tool by pinging 8.8.8.8" has been completed successfully.',
            '[Tool] Resending tool results as user message',
            '[LLM] ========== streamChatCompletion ==========',
            'The previous saved task is complete. Continue immediately with the next pending saved task without asking for confirmation.',
          ]),
          isTrue,
        );
      },
    );

    test('detects all-tasks-in-plan completion markers', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'Task 16901b8a-0a8e-4304-b54d-12d9850a7968 has been completed successfully.',
          'All tasks in the plan have been completed.',
        ]),
        isTrue,
      );
    });

    test('ignores mid-workflow completion followed by another handoff', () {
      expect(
        executionLogsContainWorkflowCompleted(const <String>[
          'The task "Create README.md with usage instructions" is complete.',
          '[Tool] Resending tool results as user message',
          'The previous saved task is complete. Continue immediately with the next pending saved task without asking for confirmation.',
        ]),
        isFalse,
      );
    });
  });
}
