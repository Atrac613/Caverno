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
  });
}
