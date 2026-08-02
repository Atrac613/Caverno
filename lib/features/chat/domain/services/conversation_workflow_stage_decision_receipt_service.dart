import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import 'conversation_workflow_conflict_preservation_service.dart';

enum ConversationWorkflowStageDecisionReceiptBlocker {
  preservationNotReady,
  acceptedDecisionMissing,
  invalidReceiptSchema,
  invalidReceiptFields,
  receiptDigestMismatch,
  currentContextUnavailable,
  contextMismatch,
  decisionRejected,
  selectedStageMismatch,
}

final class ConversationWorkflowStageDecisionReceipt {
  const ConversationWorkflowStageDecisionReceipt({
    required this.schemaName,
    required this.schemaVersion,
    required this.decisionId,
    required this.contextSchemaVersion,
    required this.contextDigest,
    required this.authority,
    required this.source,
    required this.decidedAt,
    required this.workflowStage,
    required this.approvedPlanStage,
    required this.selectedStage,
    required this.receiptDigest,
  });

  static const currentSchemaName =
      'caverno_workflow_stage_authority_decision_receipt';
  static const currentSchemaVersion = 1;

  final String schemaName;
  final int schemaVersion;
  final String decisionId;
  final int contextSchemaVersion;
  final String contextDigest;
  final ConversationWorkflowConflictStageAuthority authority;
  final ConversationWorkflowConflictStageDecisionSource source;
  final DateTime decidedAt;
  final ConversationWorkflowStage workflowStage;
  final ConversationWorkflowStage approvedPlanStage;
  final ConversationWorkflowStage selectedStage;
  final String receiptDigest;

  Map<String, Object> toJson() => {
    'schemaName': schemaName,
    'schemaVersion': schemaVersion,
    'decisionId': decisionId,
    'contextSchemaVersion': contextSchemaVersion,
    'contextDigest': contextDigest,
    'authority': authority.name,
    'source': source.name,
    'decidedAt': decidedAt.toIso8601String(),
    'workflowStage': workflowStage.name,
    'approvedPlanStage': approvedPlanStage.name,
    'selectedStage': selectedStage.name,
    'receiptDigest': receiptDigest,
  };

  factory ConversationWorkflowStageDecisionReceipt.fromJson(
    Map<String, dynamic> json,
  ) {
    try {
      return ConversationWorkflowStageDecisionReceipt(
        schemaName: json['schemaName'] as String,
        schemaVersion: json['schemaVersion'] as int,
        decisionId: json['decisionId'] as String,
        contextSchemaVersion: json['contextSchemaVersion'] as int,
        contextDigest: json['contextDigest'] as String,
        authority: ConversationWorkflowConflictStageAuthority.values.byName(
          json['authority'] as String,
        ),
        source: ConversationWorkflowConflictStageDecisionSource.values.byName(
          json['source'] as String,
        ),
        decidedAt: DateTime.parse(json['decidedAt'] as String),
        workflowStage: ConversationWorkflowStage.values.byName(
          json['workflowStage'] as String,
        ),
        approvedPlanStage: ConversationWorkflowStage.values.byName(
          json['approvedPlanStage'] as String,
        ),
        selectedStage: ConversationWorkflowStage.values.byName(
          json['selectedStage'] as String,
        ),
        receiptDigest: json['receiptDigest'] as String,
      );
    } on Object {
      throw const FormatException(
        'workflow stage decision receipt is malformed',
      );
    }
  }

  ConversationWorkflowStageDecisionReceipt copyWith({
    String? schemaName,
    int? schemaVersion,
    String? decisionId,
    int? contextSchemaVersion,
    String? contextDigest,
    ConversationWorkflowConflictStageAuthority? authority,
    ConversationWorkflowConflictStageDecisionSource? source,
    DateTime? decidedAt,
    ConversationWorkflowStage? workflowStage,
    ConversationWorkflowStage? approvedPlanStage,
    ConversationWorkflowStage? selectedStage,
    String? receiptDigest,
  }) {
    return ConversationWorkflowStageDecisionReceipt(
      schemaName: schemaName ?? this.schemaName,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      decisionId: decisionId ?? this.decisionId,
      contextSchemaVersion: contextSchemaVersion ?? this.contextSchemaVersion,
      contextDigest: contextDigest ?? this.contextDigest,
      authority: authority ?? this.authority,
      source: source ?? this.source,
      decidedAt: decidedAt ?? this.decidedAt,
      workflowStage: workflowStage ?? this.workflowStage,
      approvedPlanStage: approvedPlanStage ?? this.approvedPlanStage,
      selectedStage: selectedStage ?? this.selectedStage,
      receiptDigest: receiptDigest ?? this.receiptDigest,
    );
  }
}

final class ConversationWorkflowStageDecisionReceiptBuildResult {
  ConversationWorkflowStageDecisionReceiptBuildResult({
    required List<ConversationWorkflowStageDecisionReceiptBlocker> blockers,
    this.receipt,
  }) : blockers = List.unmodifiable(blockers);

  final List<ConversationWorkflowStageDecisionReceiptBlocker> blockers;
  final ConversationWorkflowStageDecisionReceipt? receipt;

  bool get isBuilt => blockers.isEmpty && receipt != null;
}

final class ConversationWorkflowStageDecisionReceiptReplayResult {
  ConversationWorkflowStageDecisionReceiptReplayResult({
    required List<ConversationWorkflowStageDecisionReceiptBlocker> blockers,
    this.selectedStage,
  }) : blockers = List.unmodifiable(blockers);

  final List<ConversationWorkflowStageDecisionReceiptBlocker> blockers;
  final ConversationWorkflowStage? selectedStage;

  bool get isValid => blockers.isEmpty && selectedStage != null;
}

final class ConversationWorkflowStageDecisionReceiptService {
  const ConversationWorkflowStageDecisionReceiptService();

  ConversationWorkflowStageDecisionReceiptBuildResult build({
    required ConversationWorkflowConflictPreservationResult preservationResult,
  }) {
    if (!preservationResult.isReady || preservationResult.envelope == null) {
      return _buildBlocked(
        ConversationWorkflowStageDecisionReceiptBlocker.preservationNotReady,
      );
    }
    final envelope = preservationResult.envelope!;
    final decision = envelope.stageDecision;
    if (decision == null) {
      return _buildBlocked(
        ConversationWorkflowStageDecisionReceiptBlocker.acceptedDecisionMissing,
      );
    }
    final selectedStage = envelope.selectedStage!;
    final fields = <String, Object>{
      'schemaName': ConversationWorkflowStageDecisionReceipt.currentSchemaName,
      'schemaVersion':
          ConversationWorkflowStageDecisionReceipt.currentSchemaVersion,
      'decisionId': decision.decisionId,
      'contextSchemaVersion': envelope.decisionContext.schemaVersion,
      'contextDigest': envelope.decisionContext.contextDigest,
      'authority': decision.authority.name,
      'source': decision.source.name,
      'decidedAt': decision.decidedAt.toIso8601String(),
      'workflowStage': envelope.workflowStage.name,
      'approvedPlanStage': envelope.approvedPlanStage.name,
      'selectedStage': selectedStage.name,
    };
    return ConversationWorkflowStageDecisionReceiptBuildResult(
      blockers: const [],
      receipt: ConversationWorkflowStageDecisionReceipt(
        schemaName: fields['schemaName']! as String,
        schemaVersion: fields['schemaVersion']! as int,
        decisionId: decision.decisionId,
        contextSchemaVersion: envelope.decisionContext.schemaVersion,
        contextDigest: envelope.decisionContext.contextDigest,
        authority: decision.authority,
        source: decision.source,
        decidedAt: decision.decidedAt,
        workflowStage: envelope.workflowStage,
        approvedPlanStage: envelope.approvedPlanStage,
        selectedStage: selectedStage,
        receiptDigest: _digest(fields),
      ),
    );
  }

  ConversationWorkflowStageDecisionReceiptReplayResult replay({
    required ConversationWorkflowStageDecisionReceipt receipt,
    required Conversation conversation,
  }) {
    final structuralBlocker = _validateStructure(receipt);
    if (structuralBlocker != null) return _replayBlocked(structuralBlocker);
    if (_digest(_receiptFields(receipt)) != receipt.receiptDigest) {
      return _replayBlocked(
        ConversationWorkflowStageDecisionReceiptBlocker.receiptDigestMismatch,
      );
    }

    final authorityFree =
        const ConversationWorkflowConflictPreservationService().preserve(
          conversation: conversation,
        );
    final currentEnvelope = authorityFree.envelope;
    if (currentEnvelope == null) {
      return _replayBlocked(
        ConversationWorkflowStageDecisionReceiptBlocker
            .currentContextUnavailable,
      );
    }
    if (receipt.contextSchemaVersion !=
            currentEnvelope.decisionContext.schemaVersion ||
        receipt.contextDigest !=
            currentEnvelope.decisionContext.contextDigest ||
        receipt.workflowStage != currentEnvelope.workflowStage ||
        receipt.approvedPlanStage != currentEnvelope.approvedPlanStage) {
      return _replayBlocked(
        ConversationWorkflowStageDecisionReceiptBlocker.contextMismatch,
      );
    }

    final replayed = const ConversationWorkflowConflictPreservationService()
        .preserve(
          conversation: conversation,
          stageDecision: ConversationWorkflowConflictStageDecision(
            decisionId: receipt.decisionId,
            contextDigest: receipt.contextDigest,
            authority: receipt.authority,
            source: receipt.source,
            decidedAt: receipt.decidedAt,
          ),
        );
    if (!replayed.isReady || replayed.envelope?.stageDecision == null) {
      return _replayBlocked(
        ConversationWorkflowStageDecisionReceiptBlocker.decisionRejected,
      );
    }
    if (replayed.envelope!.selectedStage != receipt.selectedStage) {
      return _replayBlocked(
        ConversationWorkflowStageDecisionReceiptBlocker.selectedStageMismatch,
      );
    }
    return ConversationWorkflowStageDecisionReceiptReplayResult(
      blockers: const [],
      selectedStage: receipt.selectedStage,
    );
  }

  ConversationWorkflowStageDecisionReceiptBlocker? _validateStructure(
    ConversationWorkflowStageDecisionReceipt receipt,
  ) {
    if (receipt.schemaName !=
            ConversationWorkflowStageDecisionReceipt.currentSchemaName ||
        receipt.schemaVersion !=
            ConversationWorkflowStageDecisionReceipt.currentSchemaVersion ||
        receipt.contextSchemaVersion != 1) {
      return ConversationWorkflowStageDecisionReceiptBlocker
          .invalidReceiptSchema;
    }
    if (receipt.decisionId.trim().isEmpty ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(receipt.contextDigest) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(receipt.receiptDigest) ||
        receipt.source !=
            ConversationWorkflowConflictStageDecisionSource
                .manualUserConfirmation ||
        !receipt.decidedAt.isUtc) {
      return ConversationWorkflowStageDecisionReceiptBlocker
          .invalidReceiptFields;
    }
    final expectedSelectedStage = switch (receipt.authority) {
      ConversationWorkflowConflictStageAuthority.workflow =>
        receipt.workflowStage,
      ConversationWorkflowConflictStageAuthority.approvedPlan =>
        receipt.approvedPlanStage,
    };
    if (receipt.selectedStage != expectedSelectedStage) {
      return ConversationWorkflowStageDecisionReceiptBlocker
          .selectedStageMismatch;
    }
    return null;
  }

  Map<String, Object> _receiptFields(
    ConversationWorkflowStageDecisionReceipt receipt,
  ) {
    return {
      'schemaName': receipt.schemaName,
      'schemaVersion': receipt.schemaVersion,
      'decisionId': receipt.decisionId,
      'contextSchemaVersion': receipt.contextSchemaVersion,
      'contextDigest': receipt.contextDigest,
      'authority': receipt.authority.name,
      'source': receipt.source.name,
      'decidedAt': receipt.decidedAt.toIso8601String(),
      'workflowStage': receipt.workflowStage.name,
      'approvedPlanStage': receipt.approvedPlanStage.name,
      'selectedStage': receipt.selectedStage.name,
    };
  }

  String _digest(Map<String, Object> fields) {
    final sortedKeys = fields.keys.toList(growable: false)..sort();
    final canonical = <String, Object>{
      for (final key in sortedKeys) key: fields[key]!,
    };
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  ConversationWorkflowStageDecisionReceiptBuildResult _buildBlocked(
    ConversationWorkflowStageDecisionReceiptBlocker blocker,
  ) {
    return ConversationWorkflowStageDecisionReceiptBuildResult(
      blockers: [blocker],
    );
  }

  ConversationWorkflowStageDecisionReceiptReplayResult _replayBlocked(
    ConversationWorkflowStageDecisionReceiptBlocker blocker,
  ) {
    return ConversationWorkflowStageDecisionReceiptReplayResult(
      blockers: [blocker],
    );
  }
}
