import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_diff_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';

void main() {
  test('buildTaskDiff reports added, removed, and changed task entries', () {
    final approvedMarkdown = ConversationPlanDocumentBuilder.build(
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: const ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-a',
            title: 'Keep the current task stable',
            validationCommand: 'flutter test',
          ),
          ConversationWorkflowTask(
            id: 'task-b',
            title: 'Remove the old follow-up task',
          ),
        ],
      ),
    );
    final draftMarkdown = ConversationPlanDocumentBuilder.build(
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: const ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-a',
            title: 'Keep the current task stable',
            validationCommand: 'flutter test --plain-name stable',
          ),
          ConversationWorkflowTask(
            id: 'task-c',
            title: 'Add the new validation follow-up',
          ),
        ],
      ),
    );

    final diff = ConversationPlanDiffService.buildTaskDiff(
      approvedMarkdown: approvedMarkdown,
      draftMarkdown: draftMarkdown,
    );

    expect(diff.isValid, isTrue);
    expect(diff.hasChanges, isTrue);
    expect(diff.countByType(ConversationPlanTaskDiffType.added), 1);
    expect(diff.countByType(ConversationPlanTaskDiffType.removed), 1);
    expect(diff.countByType(ConversationPlanTaskDiffType.changed), 1);
  });

  test('buildTaskDiff returns an invalid result for malformed markdown', () {
    final diff = ConversationPlanDiffService.buildTaskDiff(
      approvedMarkdown: '# Plan\n\n## Stage\nimplement',
      draftMarkdown: '# Plan\n\n## Tasks\n- invalid',
    );

    expect(diff.isValid, isFalse);
    expect(diff.errorMessage, isNotEmpty);
  });
}
