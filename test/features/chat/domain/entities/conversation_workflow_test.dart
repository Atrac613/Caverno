import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';

void main() {
  test('conversation workflow survives json roundtrip', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Spec thread',
      messages: const [],
      createdAt: DateTime(2026, 4, 15, 9, 0),
      updatedAt: DateTime(2026, 4, 15, 9, 5),
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-1',
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: const ConversationWorkflowSpec(
        goal: 'Add workflow state to coding conversations',
        constraints: ['Do not block quick fixes'],
        acceptanceCriteria: ['Prompt includes the saved workflow'],
        openQuestions: ['Task nodes are now in scope'],
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Persist workflow tasks',
            targetFiles: [
              'lib/features/chat/domain/entities/conversation_workflow.dart',
            ],
            validationCommand: 'flutter test',
          ),
        ],
      ),
      openQuestionProgress: const [
        ConversationOpenQuestionProgress(
          questionId: 'open-question-task-nodes',
          question: 'Task nodes are now in scope',
          status: ConversationOpenQuestionStatus.needsUserInput,
          note: 'The execution handoff still depends on this decision.',
        ),
      ],
    );

    final restored = Conversation.fromJson(conversation.toJson());

    expect(restored.workflowStage, ConversationWorkflowStage.implement);
    expect(
      restored.workflowSpec,
      const ConversationWorkflowSpec(
        goal: 'Add workflow state to coding conversations',
        constraints: ['Do not block quick fixes'],
        acceptanceCriteria: ['Prompt includes the saved workflow'],
        openQuestions: ['Task nodes are now in scope'],
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Persist workflow tasks',
            targetFiles: [
              'lib/features/chat/domain/entities/conversation_workflow.dart',
            ],
            validationCommand: 'flutter test',
          ),
        ],
      ),
    );
    expect(restored.hasWorkflowContext, isTrue);
    expect(restored.effectiveOpenQuestionProgress, [
      const ConversationOpenQuestionProgress(
        questionId: 'open-question-task-nodes',
        question: 'Task nodes are now in scope',
        status: ConversationOpenQuestionStatus.needsUserInput,
        note: 'The execution handoff still depends on this decision.',
      ),
    ]);
  });
}
