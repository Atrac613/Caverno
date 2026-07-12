import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';

void main() {
  test('legacy workflow json defaults provenance metadata to empty', () {
    final workflow = ConversationWorkflowSpec.fromJson({
      'goal': 'Keep legacy conversations readable',
      'constraints': <String>[],
      'acceptanceCriteria': <String>[],
      'openQuestions': <String>[],
      'tasks': <Object?>[],
    });

    expect(workflow.sources, isEmpty);
    expect(workflow.provenance, isEmpty);
    expect(workflow.blockingAssumptions, isEmpty);
  });

  test('material unconfirmed assumptions block execution after roundtrip', () {
    const workflow = ConversationWorkflowSpec(
      goal: 'Ship safely',
      sources: [
        ConversationContractSourceReference(
          id: 'user-message:1',
          kind: ConversationContractSourceKind.userMessage,
          locator: 'message-1',
        ),
      ],
      provenance: [
        ConversationContractItemProvenance(
          itemId: 'constraint:runtime',
          kind: ConversationContractItemKind.constraint,
          assumption: true,
          material: true,
          clarificationQuestion: 'Which runtime must be supported?',
        ),
      ],
    );

    final restored = ConversationWorkflowSpec.fromJson(workflow.toJson());

    expect(restored.sources.single.id, 'user-message:1');
    expect(restored.blockingAssumptions, hasLength(1));
    expect(
      restored.blockingAssumptions.single.normalizedClarificationQuestion,
      'Which runtime must be supported?',
    );
  });

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
      goal: ConversationGoal(
        id: 'goal-1',
        objective: 'Ship the workflow state safely',
        tokenBudget: 12000,
        tokenUsage: 3000,
        turnBudget: 6,
        turnsUsed: 2,
        createdAt: DateTime(2026, 4, 15, 9, 0),
        updatedAt: DateTime(2026, 4, 15, 9, 5),
      ),
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
    expect(restored.goal?.objective, 'Ship the workflow state safely');
    expect(restored.goal?.tokenBudget, 12000);
    expect(restored.goal?.turnsUsed, 2);
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
