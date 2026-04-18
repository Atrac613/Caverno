import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_hash.dart';

void main() {
  test('workflow projection freshness follows the approved markdown hash', () {
    const approvedMarkdown = '# Plan\n\n## Goal\nShip execution handoff';
    final baseConversation = Conversation(
      id: 'conversation-1',
      title: 'Execution handoff',
      messages: const [],
      createdAt: DateTime(2026, 4, 18, 12, 0),
      updatedAt: DateTime(2026, 4, 18, 12, 0),
      workspaceMode: WorkspaceMode.coding,
      projectId: 'project-1',
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: const ConversationWorkflowSpec(
        tasks: [
          ConversationWorkflowTask(id: 'task-1', title: 'Run the handoff'),
        ],
      ),
      workflowSourceHash: computeConversationPlanHash(approvedMarkdown),
      workflowDerivedAt: DateTime(2026, 4, 18, 12, 5),
      planArtifact: const ConversationPlanArtifact(
        approvedMarkdown: approvedMarkdown,
      ),
      executionProgress: const [
        ConversationExecutionTaskProgress(
          taskId: 'task-1',
          status: ConversationWorkflowTaskStatus.completed,
          summary: 'Completed during a smoke run.',
        ),
      ],
    );

    expect(baseConversation.isWorkflowProjectionFresh, isTrue);
    expect(baseConversation.isWorkflowProjectionStale, isFalse);
    expect(baseConversation.needsWorkflowProjectionRefresh, isFalse);
    expect(
      baseConversation.projectedExecutionTasks.single.status,
      ConversationWorkflowTaskStatus.completed,
    );

    final staleConversation = baseConversation.copyWith(
      planArtifact: const ConversationPlanArtifact(
        approvedMarkdown: '# Plan\n\n## Goal\nChanged approved plan',
      ),
    );

    expect(staleConversation.isWorkflowProjectionFresh, isFalse);
    expect(staleConversation.isWorkflowProjectionStale, isTrue);
    expect(staleConversation.needsWorkflowProjectionRefresh, isTrue);
  });

  test('execution progress exposes validation and blocked metadata', () {
    const progress = ConversationExecutionTaskProgress(
      taskId: 'task-1',
      status: ConversationWorkflowTaskStatus.blocked,
      validationStatus: ConversationExecutionValidationStatus.failed,
      summary: 'Validation failed during review.',
      blockedReason: 'Waiting for the failing test to be fixed.',
      lastValidationCommand: 'flutter test',
      lastValidationSummary: 'The smoke test failed on macOS.',
    );

    expect(progress.hasMeaningfulState, isTrue);
    expect(progress.normalizedSummary, 'Validation failed during review.');
    expect(
      progress.normalizedBlockedReason,
      'Waiting for the failing test to be fixed.',
    );
    expect(progress.normalizedValidationCommand, 'flutter test');
    expect(
      progress.normalizedValidationSummary,
      'The smoke test failed on macOS.',
    );
  });
}
