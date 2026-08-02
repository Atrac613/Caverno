import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_legacy_workflow_compatibility_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_hash.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';

void main() {
  const workflowSpec = ConversationWorkflowSpec(
    goal: 'Preserve legacy execution state',
    constraints: ['Keep the migration deterministic'],
    acceptanceCriteria: ['Retain every task field'],
    openQuestions: ['Should rollout require a backup?'],
    tasks: [
      ConversationWorkflowTask(
        id: 'legacy-task-1',
        title: 'Build the compatibility fixture',
        status: ConversationWorkflowTaskStatus.inProgress,
        targetFiles: ['lib/compatibility.dart', 'test/compatibility_test.dart'],
        validationCommand: 'flutter test',
        notes: 'Keep task IDs stable',
      ),
    ],
  );
  final planArtifact = ConversationPlanDocumentBuilder.buildApprovedArtifact(
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: workflowSpec,
    updatedAt: DateTime.utc(2026, 8, 2),
  );

  test('accepts a lossless legacy workflow including checkpoint state', () {
    final question = workflowSpec.openQuestions.single;
    final progress = ConversationExecutionTaskProgress(
      taskId: 'legacy-task-1',
      status: ConversationWorkflowTaskStatus.inProgress,
      validationStatus: ConversationExecutionValidationStatus.failed,
      updatedAt: DateTime.utc(2026, 8, 2, 1),
      lastRunAt: DateTime.utc(2026, 8, 2, 1),
      lastValidationAt: DateTime.utc(2026, 8, 2, 1, 1),
      summary: 'Implementation is in progress.',
      blockedReason: 'The focused test still fails.',
      lastValidationCommand: 'flutter test',
      lastValidationSummary: 'One focused assertion failed.',
      events: [
        ConversationExecutionTaskEvent(
          type: ConversationExecutionTaskEventType.validated,
          createdAt: DateTime.utc(2026, 8, 2, 1, 1),
          summary: 'Recorded the failing validation.',
          status: ConversationWorkflowTaskStatus.inProgress,
          validationStatus: ConversationExecutionValidationStatus.failed,
          validationCommand: 'flutter test',
          validationSummary: 'One focused assertion failed.',
        ),
      ],
    );
    final questionProgress = ConversationOpenQuestionProgress(
      questionId: Conversation.openQuestionIdFor(question),
      question: question,
      status: ConversationOpenQuestionStatus.deferred,
      note: 'Decide before live migration.',
      updatedAt: DateTime.utc(2026, 8, 2, 1, 2),
    );
    final projectedCheckpoint =
        ConversationPlanProjectionService.deriveExecutionProjection(
          approvedMarkdown: planArtifact.normalizedApprovedMarkdown!,
          derivedAt: DateTime.utc(2026, 8, 2),
        );
    final conversation = _conversation(
      executionProgress: [progress],
      openQuestionProgress: [questionProgress],
      checkpoints: [
        ConversationCheckpoint(
          messageId: 'assistant-1',
          messageCount: 2,
          title: 'Legacy checkpoint',
          createdAt: DateTime.utc(2026, 8, 2),
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: workflowSpec,
          executionProgress: [progress],
          openQuestionProgress: [questionProgress],
          planArtifact: planArtifact,
        ),
        ConversationCheckpoint(
          messageId: 'assistant-2',
          messageCount: 4,
          title: 'Plan-derived checkpoint',
          createdAt: DateTime.utc(2026, 8, 2, 2),
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: projectedCheckpoint.workflowSpec,
          workflowSourceHash: computeConversationPlanHash(
            planArtifact.normalizedApprovedMarkdown!,
          ),
          workflowDerivedAt: DateTime.utc(2026, 8, 2, 2),
          executionProgress: [progress],
          openQuestionProgress: [questionProgress],
          planArtifact: planArtifact,
        ),
      ],
    );
    final before = jsonEncode(conversation.toJson());

    final result = ConversationLegacyWorkflowCompatibilityService.evaluate(
      conversation,
    );

    expect(result.isCompatible, isTrue);
    expect(result.blockers, isEmpty);
    expect(result.currentBlockers, isEmpty);
    expect(result.checkpointBlockers, isEmpty);
    expect(result.workflowCheckpointCount, 2);
    expect(jsonEncode(conversation.toJson()), before);
  });

  test('blocks provenance that projection would replace', () {
    final conversation = _conversation(
      workflowSpec: workflowSpec.copyWith(
        sources: const [
          ConversationContractSourceReference(
            id: 'user-source',
            kind: ConversationContractSourceKind.userMessage,
          ),
        ],
      ),
    );

    final result = ConversationLegacyWorkflowCompatibilityService.evaluate(
      conversation,
    );

    expect(
      result.blockers,
      contains(
        ConversationLegacyWorkflowCompatibilityBlocker
            .contractProvenanceWouldChange,
      ),
    );
    expect(result.currentBlockers, result.blockers);
    expect(result.checkpointBlockers, isEmpty);
  });

  test('blocks dangling task and open-question progress', () {
    final conversation = _conversation(
      executionProgress: const [
        ConversationExecutionTaskProgress(taskId: 'removed-task'),
      ],
      openQuestionProgress: const [
        ConversationOpenQuestionProgress(
          questionId: 'removed-question',
          question: 'Removed question?',
        ),
      ],
    );

    final result = ConversationLegacyWorkflowCompatibilityService.evaluate(
      conversation,
    );

    expect(
      result.blockers,
      containsAll([
        ConversationLegacyWorkflowCompatibilityBlocker
            .danglingExecutionProgress,
        ConversationLegacyWorkflowCompatibilityBlocker
            .danglingOpenQuestionProgress,
      ]),
    );
    expect(result.currentBlockers, result.blockers);
    expect(result.checkpointBlockers, isEmpty);
  });

  test('blocks empty task IDs and conflicting plan documents', () {
    final conversation = _conversation(
      workflowSpec: workflowSpec.copyWith(
        tasks: [workflowSpec.tasks.single.copyWith(id: '')],
      ),
      planArtifact: const ConversationPlanArtifact(
        approvedMarkdown:
            '# Plan\n\n## Stage\nimplement\n\n## Goal\nDifferent plan',
      ),
    );

    final result = ConversationLegacyWorkflowCompatibilityService.evaluate(
      conversation,
    );

    expect(
      result.blockers,
      containsAll([
        ConversationLegacyWorkflowCompatibilityBlocker.emptyTaskId,
        ConversationLegacyWorkflowCompatibilityBlocker
            .existingPlanDocumentConflict,
      ]),
    );
  });

  test('blocks malformed projections and incompatible checkpoints', () {
    final malformedSpec = workflowSpec.copyWith(
      tasks: [
        workflowSpec.tasks.single.copyWith(notes: 'First line\nSecond line'),
      ],
    );
    final conversation = _conversation(
      checkpoints: [
        ConversationCheckpoint(
          messageId: 'assistant-1',
          messageCount: 2,
          title: 'Malformed checkpoint',
          createdAt: DateTime.utc(2026, 8, 2),
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: malformedSpec,
        ),
      ],
    );

    final result = ConversationLegacyWorkflowCompatibilityService.evaluate(
      conversation,
    );

    expect(
      result.blockers,
      containsAll([
        ConversationLegacyWorkflowCompatibilityBlocker.projectionFailed,
        ConversationLegacyWorkflowCompatibilityBlocker.checkpointIncompatible,
      ]),
    );
    expect(result.currentBlockers, isEmpty);
    expect(result.checkpointBlockers, result.blockers);
    expect(result.workflowCheckpointCount, 1);
  });

  test('blocks checkpoints with inconsistent projection metadata', () {
    final conversation = _conversation(
      checkpoints: [
        ConversationCheckpoint(
          messageId: 'assistant-1',
          messageCount: 2,
          title: 'Stale checkpoint',
          createdAt: DateTime.utc(2026, 8, 2),
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: workflowSpec,
          workflowSourceHash: 'stale-source-hash',
          workflowDerivedAt: DateTime.utc(2026, 8, 2),
          planArtifact: planArtifact,
        ),
      ],
    );

    final result = ConversationLegacyWorkflowCompatibilityService.evaluate(
      conversation,
    );

    expect(
      result.blockers,
      containsAll([
        ConversationLegacyWorkflowCompatibilityBlocker
            .checkpointProjectionInconsistent,
        ConversationLegacyWorkflowCompatibilityBlocker.checkpointIncompatible,
      ]),
    );
    expect(result.currentBlockers, isEmpty);
    expect(result.checkpointBlockers, result.blockers);
  });
}

Conversation _conversation({
  ConversationWorkflowSpec? workflowSpec,
  List<ConversationExecutionTaskProgress> executionProgress = const [],
  List<ConversationOpenQuestionProgress> openQuestionProgress = const [],
  List<ConversationCheckpoint> checkpoints = const [],
  ConversationPlanArtifact? planArtifact,
}) {
  final resolvedWorkflowSpec =
      workflowSpec ??
      const ConversationWorkflowSpec(
        goal: 'Preserve legacy execution state',
        constraints: ['Keep the migration deterministic'],
        acceptanceCriteria: ['Retain every task field'],
        openQuestions: ['Should rollout require a backup?'],
        tasks: [
          ConversationWorkflowTask(
            id: 'legacy-task-1',
            title: 'Build the compatibility fixture',
            status: ConversationWorkflowTaskStatus.inProgress,
            targetFiles: [
              'lib/compatibility.dart',
              'test/compatibility_test.dart',
            ],
            validationCommand: 'flutter test',
            notes: 'Keep task IDs stable',
          ),
        ],
      );
  return Conversation(
    id: 'legacy-conversation',
    title: 'Legacy workflow',
    messages: const [],
    createdAt: DateTime.utc(2026, 8, 2),
    updatedAt: DateTime.utc(2026, 8, 2),
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: resolvedWorkflowSpec,
    executionProgress: executionProgress,
    openQuestionProgress: openQuestionProgress,
    planArtifact:
        planArtifact ??
        ConversationPlanDocumentBuilder.buildApprovedArtifact(
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: resolvedWorkflowSpec,
          updatedAt: DateTime.utc(2026, 8, 2),
        ),
    checkpoints: checkpoints,
  );
}
