import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/execution_snapshot_projector.dart';
import 'package:caverno/features/chat/domain/services/goal_continuation_next_step_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GoalContinuationNextStepSelector', () {
    test('prefers the typed active task from the execution snapshot', () {
      final result = GoalContinuationNextStepSelector.select(
        executionSnapshot: _snapshot(activeTaskTitle: 'Implement the parser'),
        planMarkdown: '## Task checklist\n- [ ] Use the fallback',
      );

      expect(result, 'Implement the parser');
    });

    test('mines the first unchecked task only from the checklist section', () {
      const markdown = '''
## Acceptance Criteria
1. Never surface this numbered criterion

## Task checklist
- [x] Completed setup
- [ ] Implement the parser
- [ ] Run verification
''';

      expect(
        GoalContinuationNextStepSelector.select(
          executionSnapshot: _snapshot(),
          planMarkdown: markdown,
        ),
        'Implement the parser',
      );
    });

    test('stops at the next level-two section', () {
      const markdown = '''
## Task checklist
- [x] Completed setup

## Acceptance Criteria
- [ ] This is not a task
''';

      expect(
        GoalContinuationNextStepSelector.firstUncheckedChecklistItem(markdown),
        isNull,
      );
    });

    test('drops a trailing partial line from a bounded plan window', () {
      const prefix = '## Task checklist\n- [x] Setup\n';
      const partial = '- [ ] This item crosses the byte limit';
      final maxBytes = prefix.length + 8;

      expect(
        GoalContinuationNextStepSelector.firstUncheckedChecklistItem(
          '$prefix$partial',
          maxBytes: maxBytes,
        ),
        isNull,
      );
    });

    test('returns a complete multibyte item before the byte limit', () {
      const markdown = '''
## Task checklist
- [ ] Verify the caf\u00e9 output
- [ ] This trailing item is intentionally long
''';
      final firstLineEnd = markdown.indexOf('\n', markdown.indexOf('- [ ]'));
      final maxBytes = utf8
          .encode(markdown.substring(0, firstLineEnd + 1))
          .length;

      expect(
        GoalContinuationNextStepSelector.firstUncheckedChecklistItem(
          markdown,
          maxBytes: maxBytes,
        ),
        'Verify the caf\u00e9 output',
      );
    });

    test('returns null when neither source has a next step', () {
      expect(
        GoalContinuationNextStepSelector.select(
          executionSnapshot: _snapshot(),
          planMarkdown: '## Tasks\n\n1. A native numbered task',
        ),
        isNull,
      );
    });
  });
}

ExecutionSnapshot _snapshot({String activeTaskTitle = ''}) => ExecutionSnapshot(
  contractHash: '',
  workflowStage: ConversationWorkflowStage.implement,
  action: ExecutionSnapshotAction.execute,
  activeTaskId: activeTaskTitle.isEmpty ? null : 'task-1',
  activeTaskStatus: activeTaskTitle.isEmpty
      ? null
      : ConversationWorkflowTaskStatus.inProgress,
  validationStatus: ConversationExecutionValidationStatus.unknown,
  completedTaskCount: 0,
  remainingTaskCount: activeTaskTitle.isEmpty ? 0 : 1,
  unresolvedQuestionCount: 0,
  requiresValidation: false,
  latestDiagnostic: null,
  activeTaskTitle: activeTaskTitle,
);
