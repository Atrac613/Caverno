import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_workflow_conflict_preservation_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_workflow_provenance_merge_service.dart';

void main() {
  const service = ConversationWorkflowConflictPreservationService();

  test('preserves orphan progress while requiring stage authority', () {
    final conversation = _conversation(
      planStage: ConversationWorkflowStage.review,
      executionProgress: [
        const ConversationExecutionTaskProgress(taskId: 'legacy-task'),
        ConversationExecutionTaskProgress(
          taskId: 'orphan-task',
          status: ConversationWorkflowTaskStatus.inProgress,
          summary: 'Preserve this progress exactly.',
        ),
      ],
    );
    final before = jsonEncode(conversation.toJson());

    final result = service.preserve(conversation: conversation);

    expect(result.isReady, isFalse);
    expect(result.blockers, [
      ConversationWorkflowConflictPreservationBlocker.stageAuthorityRequired,
    ]);
    expect(result.mergeBlockers, isEmpty);
    final envelope = result.envelope!;
    expect(envelope.workflowStage, ConversationWorkflowStage.implement);
    expect(envelope.approvedPlanStage, ConversationWorkflowStage.review);
    expect(envelope.selectedStage, isNull);
    expect(
      envelope.activeExecutionProgress.map((progress) => progress.taskId),
      ['legacy-task'],
    );
    expect(
      envelope.orphanExecutionProgress.map((progress) => progress.taskId),
      ['orphan-task'],
    );
    expect(envelope.workflowSpec.sources, hasLength(2));
    expect(
      envelope.workflowSpec.sources.last.kind,
      ConversationContractSourceKind.approvedPlan,
    );
    expect(
      () => envelope.orphanExecutionProgress.add(
        const ConversationExecutionTaskProgress(taskId: 'late-task'),
      ),
      throwsUnsupportedError,
    );
    expect(jsonEncode(conversation.toJson()), before);
  });

  test('uses only an explicit authority when stages differ', () {
    final conversation = _conversation(
      planStage: ConversationWorkflowStage.review,
    );

    final workflowResult = service.preserve(
      conversation: conversation,
      stageAuthority: ConversationWorkflowConflictStageAuthority.workflow,
    );
    final planResult = service.preserve(
      conversation: conversation,
      stageAuthority: ConversationWorkflowConflictStageAuthority.approvedPlan,
    );

    expect(workflowResult.isReady, isTrue);
    expect(
      workflowResult.envelope!.selectedStage,
      ConversationWorkflowStage.implement,
    );
    expect(planResult.isReady, isTrue);
    expect(
      planResult.envelope!.selectedStage,
      ConversationWorkflowStage.review,
    );
  });

  test('uses the shared stage without requiring authority', () {
    final result = service.preserve(
      conversation: _conversation(
        planStage: ConversationWorkflowStage.implement,
      ),
    );

    expect(result.isReady, isTrue);
    expect(result.blockers, isEmpty);
    expect(result.envelope!.selectedStage, ConversationWorkflowStage.implement);
  });

  test('blocks missing and invalid plan documents', () {
    final missing = service.preserve(
      conversation: _conversation(planArtifact: null),
    );
    final invalid = service.preserve(
      conversation: _conversation(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown: 'Invalid plan',
        ),
      ),
    );

    expect(missing.blockers, [
      ConversationWorkflowConflictPreservationBlocker.missingPlanDocument,
    ]);
    expect(invalid.blockers, [
      ConversationWorkflowConflictPreservationBlocker.planProjectionFailed,
    ]);
    expect(missing.envelope, isNull);
    expect(invalid.envelope, isNull);
  });

  test('blocks semantic workflow drift before building an envelope', () {
    final legacy = _legacyWorkflow();
    final divergent = legacy.copyWith(goal: 'Different goal');
    final result = service.preserve(
      conversation: _conversation(
        workflowSpec: legacy,
        planArtifact: _planArtifact(
          ConversationWorkflowStage.implement,
          divergent,
        ),
      ),
    );

    expect(result.blockers, [
      ConversationWorkflowConflictPreservationBlocker.semanticWorkflowMismatch,
    ]);
    expect(result.envelope, isNull);
  });

  test('reports exact provenance merge blockers', () {
    final semantic = _semanticWorkflow();
    final result = service.preserve(
      conversation: _conversation(
        workflowSpec: semantic,
        planArtifact: _planArtifact(
          ConversationWorkflowStage.implement,
          semantic,
        ),
      ),
    );

    expect(result.blockers, [
      ConversationWorkflowConflictPreservationBlocker.provenanceMergeBlocked,
    ]);
    expect(
      result.mergeBlockers,
      containsAll([
        ConversationWorkflowProvenanceMergeBlocker.invalidLegacySourceGraph,
        ConversationWorkflowProvenanceMergeBlocker.invalidLegacyItemGraph,
      ]),
    );
    expect(result.envelope, isNull);
  });

  test('fails closed when dangling progress belongs to the plan', () {
    final legacy = _legacyWorkflow();
    final anchoredMarkdown = _planArtifact(
      ConversationWorkflowStage.implement,
      legacy,
    ).approvedMarkdown;
    final unanchoredMarkdown = anchoredMarkdown
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('- Task ID:'))
        .join('\n');
    final projection =
        ConversationPlanProjectionService.deriveExecutionProjection(
          approvedMarkdown: unanchoredMarkdown,
        );
    final planTaskId = projection.workflowSpec.tasks.single.id;

    final result = service.preserve(
      conversation: _conversation(
        workflowSpec: legacy,
        planArtifact: ConversationPlanArtifact(
          approvedMarkdown: unanchoredMarkdown,
        ),
        executionProgress: [
          ConversationExecutionTaskProgress(taskId: planTaskId),
        ],
      ),
    );

    expect(
      result.blockers,
      containsAll([
        ConversationWorkflowConflictPreservationBlocker
            .progressOwnedByExistingPlan,
        ConversationWorkflowConflictPreservationBlocker.orphanProgressMissing,
      ]),
    );
    expect(result.isReady, isFalse);
  });

  test('fails closed when dangling progress belongs to a checkpoint', () {
    final result = service.preserve(
      conversation: _conversation(
        executionProgress: const [
          ConversationExecutionTaskProgress(taskId: 'checkpoint-task'),
        ],
        checkpoints: [
          ConversationCheckpoint(
            messageId: 'checkpoint-message',
            messageCount: 1,
            title: 'Checkpoint',
            createdAt: DateTime.utc(2026, 8, 2),
            workflowSpec: const ConversationWorkflowSpec(
              tasks: [
                ConversationWorkflowTask(
                  id: 'checkpoint-task',
                  title: 'Historical task',
                ),
              ],
            ),
          ),
        ],
      ),
    );

    expect(
      result.blockers,
      containsAll([
        ConversationWorkflowConflictPreservationBlocker
            .progressOwnedByCheckpoint,
        ConversationWorkflowConflictPreservationBlocker.orphanProgressMissing,
      ]),
    );
    expect(result.isReady, isFalse);
  });
}

ConversationWorkflowSpec _semanticWorkflow() {
  return const ConversationWorkflowSpec(
    goal: 'Preserve conflicting workflow state',
    constraints: ['Do not mutate persistence'],
    acceptanceCriteria: ['Retain orphan progress'],
    tasks: [
      ConversationWorkflowTask(
        id: 'legacy-task',
        title: 'Build the preservation envelope',
      ),
    ],
  );
}

ConversationWorkflowSpec _legacyWorkflow() {
  final semantic = _semanticWorkflow();
  final projected = const ConversationContractProvenanceService()
      .attachApprovedPlanSource(
        workflowSpec: semantic,
        sourceHash: 'fixture-source',
      );
  return semantic.copyWith(
    sources: const [
      ConversationContractSourceReference(
        id: 'legacy-source',
        kind: ConversationContractSourceKind.userMessage,
      ),
    ],
    provenance: projected.provenance
        .map((item) => item.copyWith(sourceIds: const ['legacy-source']))
        .toList(growable: false),
  );
}

ConversationPlanArtifact _planArtifact(
  ConversationWorkflowStage stage,
  ConversationWorkflowSpec workflowSpec,
) {
  return ConversationPlanDocumentBuilder.buildApprovedArtifact(
    workflowStage: stage,
    workflowSpec: workflowSpec,
    updatedAt: DateTime.utc(2026, 8, 2),
  );
}

Conversation _conversation({
  ConversationWorkflowStage planStage = ConversationWorkflowStage.implement,
  ConversationWorkflowSpec? workflowSpec,
  Object? planArtifact = _defaultPlanArtifact,
  List<ConversationExecutionTaskProgress>? executionProgress,
  List<ConversationCheckpoint> checkpoints = const [],
}) {
  final resolvedWorkflow = workflowSpec ?? _legacyWorkflow();
  final resolvedArtifact = identical(planArtifact, _defaultPlanArtifact)
      ? _planArtifact(planStage, resolvedWorkflow)
      : planArtifact as ConversationPlanArtifact?;
  return Conversation(
    id: 'legacy-conflict',
    title: 'Legacy conflict',
    messages: const [],
    createdAt: DateTime.utc(2026, 8, 2),
    updatedAt: DateTime.utc(2026, 8, 2),
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: resolvedWorkflow,
    executionProgress:
        executionProgress ??
        const [ConversationExecutionTaskProgress(taskId: 'orphan-task')],
    planArtifact: resolvedArtifact,
    checkpoints: checkpoints,
  );
}

const _defaultPlanArtifact = Object();
