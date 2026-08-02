import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/conversation_workflow_conflict_preservation_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_workflow_stage_decision_receipt_service.dart';

void main() {
  const preservationService = ConversationWorkflowConflictPreservationService();
  const receiptService = ConversationWorkflowStageDecisionReceiptService();

  for (final authority in ConversationWorkflowConflictStageAuthority.values) {
    test('builds, round-trips, and replays ${authority.name} authority', () {
      final conversation = _conversation();
      final before = jsonEncode(conversation.toJson());
      final ready = _readyResult(conversation, authority);

      final build = receiptService.build(preservationResult: ready);

      expect(build.isBuilt, isTrue);
      expect(build.blockers, isEmpty);
      final receipt = build.receipt!;
      expect(receipt.schemaName, contains('stage_authority'));
      expect(receipt.schemaVersion, 1);
      expect(receipt.contextSchemaVersion, 1);
      expect(receipt.contextDigest, hasLength(64));
      expect(receipt.receiptDigest, hasLength(64));
      expect(receipt.authority, authority);
      expect(
        receipt.selectedStage,
        authority == ConversationWorkflowConflictStageAuthority.workflow
            ? ConversationWorkflowStage.implement
            : ConversationWorkflowStage.review,
      );
      final decoded = ConversationWorkflowStageDecisionReceipt.fromJson(
        jsonDecode(jsonEncode(receipt.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.toJson(), receipt.toJson());

      final replay = receiptService.replay(
        receipt: decoded,
        conversation: conversation,
      );

      expect(replay.isValid, isTrue);
      expect(replay.blockers, isEmpty);
      expect(replay.selectedStage, receipt.selectedStage);
      expect(jsonEncode(conversation.toJson()), before);
      expect(jsonEncode(receipt.toJson()), isNot(contains('Private')));
      expect(jsonEncode(receipt.toJson()), isNot(contains('orphan-task')));
    });
  }

  test('requires a ready result with an accepted decision', () {
    final divergent = _conversation();
    final authorityFree = preservationService.preserve(conversation: divergent);
    final equalStage = _conversation(
      planStage: ConversationWorkflowStage.implement,
    );
    final implicitlyReady = preservationService.preserve(
      conversation: equalStage,
    );

    final blocked = receiptService.build(preservationResult: authorityFree);
    final missingDecision = receiptService.build(
      preservationResult: implicitlyReady,
    );

    expect(blocked.blockers, [
      ConversationWorkflowStageDecisionReceiptBlocker.preservationNotReady,
    ]);
    expect(missingDecision.blockers, [
      ConversationWorkflowStageDecisionReceiptBlocker.acceptedDecisionMissing,
    ]);
    expect(blocked.receipt, isNull);
    expect(missingDecision.receipt, isNull);
  });

  test('rejects unsupported schemas and malformed receipt fields', () {
    final receipt = _receipt(_conversation());
    final invalidSchema = receipt.copyWith(schemaVersion: 2);
    final invalidFields = receipt.copyWith(decisionId: ' ');

    expect(
      receiptService
          .replay(receipt: invalidSchema, conversation: _conversation())
          .blockers,
      [ConversationWorkflowStageDecisionReceiptBlocker.invalidReceiptSchema],
    );
    expect(
      receiptService
          .replay(receipt: invalidFields, conversation: _conversation())
          .blockers,
      [ConversationWorkflowStageDecisionReceiptBlocker.invalidReceiptFields],
    );
    expect(
      () =>
          ConversationWorkflowStageDecisionReceipt.fromJson({'schemaName': 42}),
      throwsFormatException,
    );
  });

  test('rejects receipt tampering before current-state replay', () {
    final conversation = _conversation();
    final receipt = _receipt(conversation);
    final tampered = receipt.copyWith(decisionId: 'tampered-decision');

    final result = receiptService.replay(
      receipt: tampered,
      conversation: conversation,
    );

    expect(result.blockers, [
      ConversationWorkflowStageDecisionReceiptBlocker.receiptDigestMismatch,
    ]);
    expect(result.selectedStage, isNull);
  });

  test('rejects a stale receipt after current context changes', () {
    final conversation = _conversation();
    final receipt = _receipt(conversation);
    final changedConversation = conversation.copyWith(
      executionProgress: [
        ConversationExecutionTaskProgress(
          taskId: 'orphan-task',
          status: ConversationWorkflowTaskStatus.inProgress,
          summary: 'Private state changed after receipt creation.',
        ),
      ],
    );

    final result = receiptService.replay(
      receipt: receipt,
      conversation: changedConversation,
    );

    expect(result.blockers, [
      ConversationWorkflowStageDecisionReceiptBlocker.contextMismatch,
    ]);
    expect(result.selectedStage, isNull);
  });

  test('rejects selected-stage claims that contradict authority', () {
    final conversation = _conversation();
    final receipt = _receipt(conversation);
    final contradictory = receipt.copyWith(
      selectedStage: receipt.approvedPlanStage,
    );

    final result = receiptService.replay(
      receipt: contradictory,
      conversation: conversation,
    );

    expect(result.blockers, [
      ConversationWorkflowStageDecisionReceiptBlocker.selectedStageMismatch,
    ]);
  });

  test('rejects replay when the current context cannot be rebuilt', () {
    final receipt = _receipt(_conversation());
    final unavailable = _conversation().copyWith(planArtifact: null);

    final result = receiptService.replay(
      receipt: receipt,
      conversation: unavailable,
    );

    expect(result.blockers, [
      ConversationWorkflowStageDecisionReceiptBlocker.currentContextUnavailable,
    ]);
  });
}

ConversationWorkflowStageDecisionReceipt _receipt(Conversation conversation) {
  const service = ConversationWorkflowStageDecisionReceiptService();
  return service
      .build(
        preservationResult: _readyResult(
          conversation,
          ConversationWorkflowConflictStageAuthority.workflow,
        ),
      )
      .receipt!;
}

ConversationWorkflowConflictPreservationResult _readyResult(
  Conversation conversation,
  ConversationWorkflowConflictStageAuthority authority,
) {
  const service = ConversationWorkflowConflictPreservationService();
  final context = service
      .preserve(conversation: conversation)
      .envelope!
      .decisionContext;
  return service.preserve(
    conversation: conversation,
    stageDecision: ConversationWorkflowConflictStageDecision(
      decisionId: 'manual-decision-${authority.name}',
      contextDigest: context.contextDigest,
      authority: authority,
      source: ConversationWorkflowConflictStageDecisionSource
          .manualUserConfirmation,
      decidedAt: DateTime.utc(2026, 8, 2),
    ),
  );
}

Conversation _conversation({
  ConversationWorkflowStage planStage = ConversationWorkflowStage.review,
}) {
  const semantic = ConversationWorkflowSpec(
    goal: 'Private workflow goal',
    constraints: ['Private constraint'],
    acceptanceCriteria: ['Private acceptance criterion'],
    tasks: [
      ConversationWorkflowTask(id: 'active-task', title: 'Private active task'),
    ],
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
