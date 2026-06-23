import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_participant.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
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

  test('participant settings survive direct json roundtrip', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Participant discussion',
      messages: const [],
      createdAt: DateTime(2026, 6, 23, 12),
      updatedAt: DateTime(2026, 6, 23, 12),
      participants: const [
        ConversationParticipant(
          id: 'reviewer',
          displayName: 'Reviewer',
          roleLabel: 'Critic',
          roleSystemPrompt: 'Challenge weak assumptions.',
          endpointId: 'pc2',
          model: 'review-model',
          facilitatesTurns: true,
          colorValue: 0xFF006A6A,
          order: 1,
        ),
      ],
      participantTurnConfig: const ParticipantTurnConfig(
        depth: ParticipantTurnDepth.multiRound,
        maxRounds: 3,
      ),
    );

    final restored = Conversation.fromJson(conversation.toJson());

    expect(restored.participants, conversation.participants);
    expect(restored.participants.single.facilitatesTurns, isTrue);
    expect(restored.participants.single.isTurnFacilitator, isTrue);
    expect(restored.participantTurnConfig, conversation.participantTurnConfig);
  });

  test('participant facilitator fallback supports legacy role labels', () {
    const structured = ConversationParticipant(
      id: 'lead',
      roleLabel: 'Conversation Lead',
      facilitatesTurns: true,
    );
    const legacy = ConversationParticipant(
      id: 'legacy',
      roleLabel: 'Moderator',
    );
    const regular = ConversationParticipant(
      id: 'reviewer',
      roleLabel: 'Reviewer',
    );

    expect(structured.isTurnFacilitator, isTrue);
    expect(legacy.isTurnFacilitator, isTrue);
    expect(regular.isTurnFacilitator, isFalse);
  });

  test('participant speaker snapshot survives message json roundtrip', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Participant discussion',
      messages: [
        Message(
          id: 'message-1',
          content: 'I would keep the API surface small.',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 6, 23, 12, 1),
          participantId: 'reviewer',
          participantDisplayName: 'Reviewer',
          participantRoleLabel: 'Critic',
          participantColorValue: 0xFF006A6A,
        ),
      ],
      createdAt: DateTime(2026, 6, 23, 12),
      updatedAt: DateTime(2026, 6, 23, 12),
    );

    final restored = Conversation.fromJson(conversation.toJson());
    final restoredMessage = restored.messages.single;

    expect(restoredMessage.participantId, 'reviewer');
    expect(restoredMessage.participantDisplayName, 'Reviewer');
    expect(restoredMessage.participantRoleLabel, 'Critic');
    expect(restoredMessage.participantColorValue, 0xFF006A6A);
  });

  test('participant handoff snapshot survives message json roundtrip', () {
    final conversation = Conversation(
      id: 'conversation-1',
      title: 'Participant discussion',
      messages: [
        Message(
          id: 'message-1',
          content: 'Engineer, what do you think?',
          role: MessageRole.assistant,
          timestamp: DateTime(2026, 6, 23, 12, 1),
          participantId: 'primary',
          participantDisplayName: 'Primary',
          participantRoleLabel: 'Facilitator',
          handoffTargetParticipantId: 'engineer',
          handoffTargetDisplayName: 'Engineer',
          handoffTargetRoleLabel: 'Senior Engineer',
        ),
      ],
      createdAt: DateTime(2026, 6, 23, 12),
      updatedAt: DateTime(2026, 6, 23, 12),
    );

    final restored = Conversation.fromJson(conversation.toJson());
    final restoredMessage = restored.messages.single;

    expect(restoredMessage.handoffTargetParticipantId, 'engineer');
    expect(restoredMessage.handoffTargetDisplayName, 'Engineer');
    expect(restoredMessage.handoffTargetRoleLabel, 'Senior Engineer');
  });
}
