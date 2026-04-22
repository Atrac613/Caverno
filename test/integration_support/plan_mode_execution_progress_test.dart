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
