import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/conversation_workflow_conflict_preservation_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_workflow_stage_confirmation_contract.dart';

void main() {
  const preservationService = ConversationWorkflowConflictPreservationService();
  const contract = ConversationWorkflowStageConfirmationContract();

  test('builds a content-free request from exact authority context', () {
    final conversation = _conversation();
    final before = jsonEncode(conversation.toJson());

    final build = contract.buildRequest(
      requestId: 'confirmation-request',
      requestedAt: DateTime.utc(2026, 8, 2, 10),
      preservationResult: preservationService.preserve(
        conversation: conversation,
      ),
    );

    expect(build.isBuilt, isTrue);
    expect(build.blockers, isEmpty);
    final request = build.request!;
    expect(request.requestId, 'confirmation-request');
    expect(request.contextSchemaVersion, 1);
    expect(request.contextDigest, hasLength(64));
    expect(request.workflowStage, ConversationWorkflowStage.implement);
    expect(request.approvedPlanStage, ConversationWorkflowStage.review);
    expect(request.activeProgressCount, 1);
    expect(request.orphanProgressCount, 1);
    expect(request.requestedAt.isUtc, isTrue);
    expect(jsonEncode(conversation.toJson()), before);
  });

  for (final authority in ConversationWorkflowConflictStageAuthority.values) {
    test('resolves ${authority.name} confirmation into a valid decision', () {
      final conversation = _conversation();
      final current = preservationService.preserve(conversation: conversation);
      final request = _request(current);
      final resolution = contract.resolve(
        request: request,
        result: ConversationWorkflowStageConfirmed(
          requestId: request.requestId,
          contextDigest: request.contextDigest,
          respondedAt: DateTime.utc(2026, 8, 2, 10, 1),
          decisionId: 'confirmed-${authority.name}',
          authority: authority,
        ),
        currentPreservationResult: current,
      );

      expect(resolution.isConfirmed, isTrue);
      expect(resolution.blockers, isEmpty);
      expect(resolution.decision!.authority, authority);
      expect(
        resolution.decision!.source,
        ConversationWorkflowConflictStageDecisionSource.manualUserConfirmation,
      );
      final accepted = preservationService.preserve(
        conversation: conversation,
        stageDecision: resolution.decision,
      );
      expect(accepted.isReady, isTrue);
      expect(
        accepted.envelope!.selectedStage,
        authority == ConversationWorkflowConflictStageAuthority.workflow
            ? ConversationWorkflowStage.implement
            : ConversationWorkflowStage.review,
      );
    });
  }

  test('rejects contexts that do not require stage authority', () {
    final equalStages = preservationService.preserve(
      conversation: _conversation(
        planStage: ConversationWorkflowStage.implement,
      ),
    );
    final missingPlan = preservationService.preserve(
      conversation: _conversation().copyWith(planArtifact: null),
    );

    for (final result in [equalStages, missingPlan]) {
      final build = contract.buildRequest(
        requestId: 'confirmation-request',
        requestedAt: DateTime.utc(2026, 8, 2, 10),
        preservationResult: result,
      );
      expect(build.blockers, [
        ConversationWorkflowStageConfirmationBlocker.confirmationUnavailable,
      ]);
      expect(build.request, isNull);
    }
  });

  test('rejects invalid request identity and creation time', () {
    final current = preservationService.preserve(conversation: _conversation());

    final blankId = contract.buildRequest(
      requestId: ' ',
      requestedAt: DateTime.utc(2026, 8, 2, 10),
      preservationResult: current,
    );
    final localTime = contract.buildRequest(
      requestId: 'confirmation-request',
      requestedAt: DateTime(2026, 8, 2, 10),
      preservationResult: current,
    );

    for (final result in [blankId, localTime]) {
      expect(result.blockers, [
        ConversationWorkflowStageConfirmationBlocker.invalidRequestFields,
      ]);
      expect(result.request, isNull);
    }
  });

  test('returns a typed blocker when confirmation is declined', () {
    final current = preservationService.preserve(conversation: _conversation());
    final request = _request(current);

    final resolution = contract.resolve(
      request: request,
      result: ConversationWorkflowStageConfirmationDeclined(
        requestId: request.requestId,
        contextDigest: request.contextDigest,
        respondedAt: DateTime.utc(2026, 8, 2, 10, 1),
      ),
      currentPreservationResult: current,
    );

    expect(resolution.blockers, [
      ConversationWorkflowStageConfirmationBlocker.confirmationDeclined,
    ]);
    expect(resolution.decision, isNull);
  });

  test('rejects confirmation identity and context mismatches', () {
    final current = preservationService.preserve(conversation: _conversation());
    final request = _request(current);
    final mismatches = [
      ConversationWorkflowStageConfirmed(
        requestId: 'different-request',
        contextDigest: request.contextDigest,
        respondedAt: DateTime.utc(2026, 8, 2, 10, 1),
        decisionId: 'confirmed-workflow',
        authority: ConversationWorkflowConflictStageAuthority.workflow,
      ),
      ConversationWorkflowStageConfirmed(
        requestId: request.requestId,
        contextDigest: List.filled(64, '0').join(),
        respondedAt: DateTime.utc(2026, 8, 2, 10, 1),
        decisionId: 'confirmed-workflow',
        authority: ConversationWorkflowConflictStageAuthority.workflow,
      ),
    ];

    for (final result in mismatches) {
      final resolution = contract.resolve(
        request: request,
        result: result,
        currentPreservationResult: current,
      );
      expect(resolution.blockers, [
        ConversationWorkflowStageConfirmationBlocker.confirmationResultMismatch,
      ]);
      expect(resolution.decision, isNull);
    }
  });

  test('rejects invalid decision identity and response times', () {
    final current = preservationService.preserve(conversation: _conversation());
    final request = _request(current);
    final invalid = [
      ConversationWorkflowStageConfirmed(
        requestId: request.requestId,
        contextDigest: request.contextDigest,
        respondedAt: DateTime.utc(2026, 8, 2, 10, 1),
        decisionId: ' ',
        authority: ConversationWorkflowConflictStageAuthority.workflow,
      ),
      ConversationWorkflowStageConfirmed(
        requestId: request.requestId,
        contextDigest: request.contextDigest,
        respondedAt: DateTime(2026, 8, 2, 10, 1),
        decisionId: 'confirmed-workflow',
        authority: ConversationWorkflowConflictStageAuthority.workflow,
      ),
      ConversationWorkflowStageConfirmed(
        requestId: request.requestId,
        contextDigest: request.contextDigest,
        respondedAt: DateTime.utc(2026, 8, 2, 9, 59),
        decisionId: 'confirmed-workflow',
        authority: ConversationWorkflowConflictStageAuthority.workflow,
      ),
    ];

    for (final result in invalid) {
      final resolution = contract.resolve(
        request: request,
        result: result,
        currentPreservationResult: current,
      );
      expect(resolution.blockers, [
        ConversationWorkflowStageConfirmationBlocker.invalidConfirmationFields,
      ]);
      expect(resolution.decision, isNull);
    }
  });

  test('rejects confirmation after current context changes', () {
    final conversation = _conversation();
    final request = _request(
      preservationService.preserve(conversation: conversation),
    );
    final changed = conversation.copyWith(
      executionProgress: [
        const ConversationExecutionTaskProgress(
          taskId: 'active-task',
          status: ConversationWorkflowTaskStatus.completed,
        ),
        ConversationExecutionTaskProgress(
          taskId: 'orphan-task',
          status: ConversationWorkflowTaskStatus.inProgress,
          summary: 'Changed while confirmation was pending.',
        ),
      ],
    );

    final resolution = contract.resolve(
      request: request,
      result: ConversationWorkflowStageConfirmed(
        requestId: request.requestId,
        contextDigest: request.contextDigest,
        respondedAt: DateTime.utc(2026, 8, 2, 10, 1),
        decisionId: 'confirmed-workflow',
        authority: ConversationWorkflowConflictStageAuthority.workflow,
      ),
      currentPreservationResult: preservationService.preserve(
        conversation: changed,
      ),
    );

    expect(resolution.blockers, [
      ConversationWorkflowStageConfirmationBlocker.currentContextMismatch,
    ]);
    expect(resolution.decision, isNull);
  });
}

ConversationWorkflowStageConfirmationRequest _request(
  ConversationWorkflowConflictPreservationResult preservationResult,
) {
  return const ConversationWorkflowStageConfirmationContract()
      .buildRequest(
        requestId: 'confirmation-request',
        requestedAt: DateTime.utc(2026, 8, 2, 10),
        preservationResult: preservationResult,
      )
      .request!;
}

Conversation _conversation({
  ConversationWorkflowStage planStage = ConversationWorkflowStage.review,
}) {
  const semantic = ConversationWorkflowSpec(
    goal: 'Private workflow goal',
    constraints: ['Private constraint'],
    acceptanceCriteria: ['Private acceptance criterion'],
    tasks: [ConversationWorkflowTask(id: 'active-task', title: 'Private task')],
  );
  final projected = const ConversationContractProvenanceService()
      .attachApprovedPlanSource(
        workflowSpec: semantic,
        sourceHash: 'fixture-source',
      );
  final legacy = semantic.copyWith(
    sources: const [
      ConversationContractSourceReference(
        id: 'private-legacy-source',
        kind: ConversationContractSourceKind.userMessage,
      ),
    ],
    provenance: projected.provenance
        .map(
          (item) => item.copyWith(sourceIds: const ['private-legacy-source']),
        )
        .toList(growable: false),
  );
  return Conversation(
    id: 'private-conversation',
    title: 'Private conversation',
    messages: const [],
    createdAt: DateTime.utc(2026, 8, 2),
    updatedAt: DateTime.utc(2026, 8, 2),
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: legacy,
    executionProgress: [
      const ConversationExecutionTaskProgress(taskId: 'active-task'),
      ConversationExecutionTaskProgress(
        taskId: 'orphan-task',
        status: ConversationWorkflowTaskStatus.inProgress,
        summary: 'Private orphan progress',
      ),
    ],
    planArtifact: ConversationPlanDocumentBuilder.buildApprovedArtifact(
      workflowStage: planStage,
      workflowSpec: legacy,
      updatedAt: DateTime.utc(2026, 8, 2),
    ),
  );
}
