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
    test('rehearses ${authority.name} authority end to end', () {
      final conversation = _syntheticConflict();
      final conversationBefore = jsonEncode(conversation.toJson());
      final progressBefore = _progressMultiset(conversation.executionProgress);

      final authorityFree = preservationService.preserve(
        conversation: conversation,
      );

      expect(authorityFree.envelope, isNotNull);
      expect(authorityFree.isReady, isFalse);
      expect(authorityFree.blockers, [
        ConversationWorkflowConflictPreservationBlocker.stageAuthorityRequired,
      ]);
      expect(authorityFree.mergeBlockers, isEmpty);
      expect(authorityFree.envelope!.selectedStage, isNull);
      expect(authorityFree.envelope!.stageDecision, isNull);
      expect(
        _envelopeProgressMultiset(authorityFree.envelope!),
        progressBefore,
      );

      final accepted = preservationService.preserve(
        conversation: conversation,
        stageDecision: ConversationWorkflowConflictStageDecision(
          decisionId: 'synthetic-${authority.name}-decision',
          contextDigest: authorityFree.envelope!.decisionContext.contextDigest,
          authority: authority,
          source: ConversationWorkflowConflictStageDecisionSource
              .manualUserConfirmation,
          decidedAt: DateTime.utc(2026, 8, 2, 12),
        ),
      );

      final expectedStage = switch (authority) {
        ConversationWorkflowConflictStageAuthority.workflow =>
          ConversationWorkflowStage.implement,
        ConversationWorkflowConflictStageAuthority.approvedPlan =>
          ConversationWorkflowStage.review,
      };
      expect(accepted.isReady, isTrue);
      expect(accepted.blockers, isEmpty);
      expect(accepted.mergeBlockers, isEmpty);
      expect(accepted.envelope!.selectedStage, expectedStage);
      expect(accepted.envelope!.stageDecision!.authority, authority);
      expect(
        accepted.envelope!.decisionContext.contextDigest,
        authorityFree.envelope!.decisionContext.contextDigest,
      );
      expect(_envelopeProgressMultiset(accepted.envelope!), progressBefore);

      final build = receiptService.build(preservationResult: accepted);

      expect(build.isBuilt, isTrue);
      expect(build.blockers, isEmpty);
      final encodedReceipt = jsonEncode(build.receipt!.toJson());
      final decodedReceipt = ConversationWorkflowStageDecisionReceipt.fromJson(
        jsonDecode(encodedReceipt) as Map<String, dynamic>,
      );
      expect(decodedReceipt.toJson().keys.toSet(), {
        'schemaName',
        'schemaVersion',
        'decisionId',
        'contextSchemaVersion',
        'contextDigest',
        'authority',
        'source',
        'decidedAt',
        'workflowStage',
        'approvedPlanStage',
        'selectedStage',
        'receiptDigest',
      });
      expect(encodedReceipt, isNot(contains('Synthetic workflow goal')));
      expect(encodedReceipt, isNot(contains('Synthetic active task')));
      expect(encodedReceipt, isNot(contains('synthetic-orphan-task')));
      expect(encodedReceipt, isNot(contains('Synthetic orphan progress')));

      final replay = receiptService.replay(
        receipt: decodedReceipt,
        conversation: conversation,
      );

      expect(replay.isValid, isTrue);
      expect(replay.blockers, isEmpty);
      expect(replay.selectedStage, expectedStage);
      expect(jsonEncode(conversation.toJson()), conversationBefore);
      expect(_progressMultiset(conversation.executionProgress), progressBefore);
    });
  }
}

List<String> _envelopeProgressMultiset(
  ConversationWorkflowConflictPreservationEnvelope envelope,
) {
  return _progressMultiset([
    ...envelope.activeExecutionProgress,
    ...envelope.orphanExecutionProgress,
  ]);
}

List<String> _progressMultiset(
  Iterable<ConversationExecutionTaskProgress> progress,
) {
  return progress.map((item) => jsonEncode(item.toJson())).toList()..sort();
}

Conversation _syntheticConflict() {
  const semantic = ConversationWorkflowSpec(
    goal: 'Synthetic workflow goal',
    constraints: ['Synthetic constraint'],
    acceptanceCriteria: ['Synthetic acceptance criterion'],
    tasks: [
      ConversationWorkflowTask(
        id: 'synthetic-active-task',
        title: 'Synthetic active task',
      ),
    ],
  );
  final projected = const ConversationContractProvenanceService()
      .attachApprovedPlanSource(
        workflowSpec: semantic,
        sourceHash: 'synthetic-plan-source',
      );
  final legacy = semantic.copyWith(
    sources: const [
      ConversationContractSourceReference(
        id: 'synthetic-legacy-source',
        kind: ConversationContractSourceKind.userMessage,
      ),
    ],
    provenance: projected.provenance
        .map(
          (item) => item.copyWith(sourceIds: const ['synthetic-legacy-source']),
        )
        .toList(growable: false),
  );
  return Conversation(
    id: 'synthetic-conflict-conversation',
    title: 'Synthetic conflict conversation',
    messages: const [],
    createdAt: DateTime.utc(2026, 8, 2),
    updatedAt: DateTime.utc(2026, 8, 2),
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: legacy,
    executionProgress: [
      const ConversationExecutionTaskProgress(taskId: 'synthetic-active-task'),
      ConversationExecutionTaskProgress(
        taskId: 'synthetic-orphan-task',
        status: ConversationWorkflowTaskStatus.inProgress,
        summary: 'Synthetic orphan progress',
      ),
    ],
    planArtifact: ConversationPlanDocumentBuilder.buildApprovedArtifact(
      workflowStage: ConversationWorkflowStage.review,
      workflowSpec: legacy,
      updatedAt: DateTime.utc(2026, 8, 2),
    ),
  );
}
