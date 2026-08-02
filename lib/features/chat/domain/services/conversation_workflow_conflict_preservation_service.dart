import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import 'conversation_plan_projection_service.dart';
import 'conversation_workflow_provenance_merge_service.dart';

enum ConversationWorkflowConflictStageAuthority { workflow, approvedPlan }

enum ConversationWorkflowConflictStageDecisionSource {
  manualUserConfirmation,
  automatedInference,
}

final class ConversationWorkflowConflictStageDecisionContext {
  const ConversationWorkflowConflictStageDecisionContext({
    required this.schemaVersion,
    required this.contextDigest,
    required this.workflowStage,
    required this.approvedPlanStage,
  });

  final int schemaVersion;
  final String contextDigest;
  final ConversationWorkflowStage workflowStage;
  final ConversationWorkflowStage approvedPlanStage;
}

final class ConversationWorkflowConflictStageDecision {
  const ConversationWorkflowConflictStageDecision({
    required this.decisionId,
    required this.contextDigest,
    required this.authority,
    required this.source,
    required this.decidedAt,
  });

  final String decisionId;
  final String contextDigest;
  final ConversationWorkflowConflictStageAuthority authority;
  final ConversationWorkflowConflictStageDecisionSource source;
  final DateTime decidedAt;
}

enum ConversationWorkflowConflictPreservationBlocker {
  missingPlanDocument,
  planProjectionFailed,
  semanticWorkflowMismatch,
  provenanceMergeBlocked,
  progressOwnedByExistingPlan,
  progressOwnedByCheckpoint,
  orphanProgressMissing,
  invalidStageDecision,
  stageDecisionContextMismatch,
  stageAuthorityRequired,
}

final class ConversationWorkflowConflictPreservationEnvelope {
  ConversationWorkflowConflictPreservationEnvelope({
    required this.workflowStage,
    required this.approvedPlanStage,
    required this.selectedStage,
    required this.decisionContext,
    required this.stageDecision,
    required this.workflowSpec,
    required List<ConversationExecutionTaskProgress> activeExecutionProgress,
    required List<ConversationExecutionTaskProgress> orphanExecutionProgress,
  }) : activeExecutionProgress = List.unmodifiable(activeExecutionProgress),
       orphanExecutionProgress = List.unmodifiable(orphanExecutionProgress);

  final ConversationWorkflowStage workflowStage;
  final ConversationWorkflowStage approvedPlanStage;
  final ConversationWorkflowStage? selectedStage;
  final ConversationWorkflowConflictStageDecisionContext decisionContext;
  final ConversationWorkflowConflictStageDecision? stageDecision;
  final ConversationWorkflowSpec workflowSpec;
  final List<ConversationExecutionTaskProgress> activeExecutionProgress;
  final List<ConversationExecutionTaskProgress> orphanExecutionProgress;
}

final class ConversationWorkflowConflictPreservationResult {
  ConversationWorkflowConflictPreservationResult({
    required List<ConversationWorkflowConflictPreservationBlocker> blockers,
    required List<ConversationWorkflowProvenanceMergeBlocker> mergeBlockers,
    this.envelope,
  }) : blockers = List.unmodifiable(blockers),
       mergeBlockers = List.unmodifiable(mergeBlockers);

  final List<ConversationWorkflowConflictPreservationBlocker> blockers;
  final List<ConversationWorkflowProvenanceMergeBlocker> mergeBlockers;
  final ConversationWorkflowConflictPreservationEnvelope? envelope;

  bool get isReady => blockers.isEmpty && envelope?.selectedStage != null;
}

final class ConversationWorkflowConflictPreservationService {
  const ConversationWorkflowConflictPreservationService();

  ConversationWorkflowConflictPreservationResult preserve({
    required Conversation conversation,
    ConversationWorkflowConflictStageDecision? stageDecision,
  }) {
    final existingMarkdown = conversation.planArtifact?.executionMarkdown;
    if (existingMarkdown == null) {
      return _blocked(const [
        ConversationWorkflowConflictPreservationBlocker.missingPlanDocument,
      ]);
    }

    final ConversationPlanProjection projection;
    try {
      projection = ConversationPlanProjectionService.deriveExecutionProjection(
        approvedMarkdown: existingMarkdown,
        derivedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    } on FormatException {
      return _blocked(const [
        ConversationWorkflowConflictPreservationBlocker.planProjectionFailed,
      ]);
    }

    final legacyWorkflowSpec = conversation.effectiveWorkflowSpec;
    final stabilizedWorkflowSpec =
        ConversationPlanProjectionService.stabilizeTaskIds(
          previousTasks: legacyWorkflowSpec.tasks,
          workflowSpec: projection.workflowSpec,
          anchoredTaskIndexes: projection.anchoredTaskIndexes,
        );
    if (_withoutProvenance(legacyWorkflowSpec) !=
        _withoutProvenance(stabilizedWorkflowSpec)) {
      return _blocked(const [
        ConversationWorkflowConflictPreservationBlocker
            .semanticWorkflowMismatch,
      ]);
    }

    final mergeResult = const ConversationWorkflowProvenanceMergeService()
        .merge(
          legacyWorkflowSpec: legacyWorkflowSpec,
          projectedWorkflowSpec: stabilizedWorkflowSpec,
        );

    final currentTaskIds = legacyWorkflowSpec.tasks
        .map((task) => task.id.trim())
        .where((taskId) => taskId.isNotEmpty)
        .toSet();
    final planTaskIds = projection.workflowSpec.tasks
        .map((task) => task.id.trim())
        .where((taskId) => taskId.isNotEmpty)
        .toSet();
    final checkpointTaskIds = conversation.checkpoints
        .expand((checkpoint) => checkpoint.workflowSpec?.tasks ?? const [])
        .map((task) => task.id.trim())
        .where((taskId) => taskId.isNotEmpty)
        .toSet();
    final activeProgress = <ConversationExecutionTaskProgress>[];
    final orphanProgress = <ConversationExecutionTaskProgress>[];
    var hasPlanOwnedProgress = false;
    var hasCheckpointOwnedProgress = false;
    for (final progress in conversation.executionProgress) {
      final taskId = progress.taskId.trim();
      if (currentTaskIds.contains(taskId)) {
        activeProgress.add(progress);
      } else if (planTaskIds.contains(taskId)) {
        hasPlanOwnedProgress = true;
      } else if (checkpointTaskIds.contains(taskId)) {
        hasCheckpointOwnedProgress = true;
      } else {
        orphanProgress.add(progress);
      }
    }

    final blockers = <ConversationWorkflowConflictPreservationBlocker>{};
    if (hasPlanOwnedProgress) {
      blockers.add(
        ConversationWorkflowConflictPreservationBlocker
            .progressOwnedByExistingPlan,
      );
    }
    if (hasCheckpointOwnedProgress) {
      blockers.add(
        ConversationWorkflowConflictPreservationBlocker
            .progressOwnedByCheckpoint,
      );
    }
    if (orphanProgress.isEmpty) {
      blockers.add(
        ConversationWorkflowConflictPreservationBlocker.orphanProgressMissing,
      );
    }
    if (!mergeResult.isMergeable) {
      blockers.add(
        ConversationWorkflowConflictPreservationBlocker.provenanceMergeBlocked,
      );
      return _blocked(
        ConversationWorkflowConflictPreservationBlocker.values
            .where(blockers.contains)
            .toList(growable: false),
        mergeBlockers: mergeResult.blockers,
      );
    }

    final decisionContext = _decisionContext(
      workflowStage: conversation.workflowStage,
      approvedPlanStage: projection.workflowStage,
      approvedPlanMarkdown: existingMarkdown,
      workflowSpec: mergeResult.workflowSpec!,
      activeExecutionProgress: activeProgress,
      orphanExecutionProgress: orphanProgress,
    );
    final stagesDiffer = conversation.workflowStage != projection.workflowStage;
    ConversationWorkflowStage? selectedStage;
    ConversationWorkflowConflictStageDecision? acceptedDecision;
    if (stageDecision == null) {
      if (stagesDiffer) {
        blockers.add(
          ConversationWorkflowConflictPreservationBlocker
              .stageAuthorityRequired,
        );
      } else {
        selectedStage = conversation.workflowStage;
      }
    } else if (!_isValidDecision(stageDecision)) {
      blockers.add(
        ConversationWorkflowConflictPreservationBlocker.invalidStageDecision,
      );
    } else if (stageDecision.contextDigest != decisionContext.contextDigest) {
      blockers.add(
        ConversationWorkflowConflictPreservationBlocker
            .stageDecisionContextMismatch,
      );
    } else {
      acceptedDecision = stageDecision;
      selectedStage = switch (stageDecision.authority) {
        ConversationWorkflowConflictStageAuthority.workflow =>
          conversation.workflowStage,
        ConversationWorkflowConflictStageAuthority.approvedPlan =>
          projection.workflowStage,
      };
    }

    return ConversationWorkflowConflictPreservationResult(
      blockers: ConversationWorkflowConflictPreservationBlocker.values
          .where(blockers.contains)
          .toList(growable: false),
      mergeBlockers: const [],
      envelope: ConversationWorkflowConflictPreservationEnvelope(
        workflowStage: conversation.workflowStage,
        approvedPlanStage: projection.workflowStage,
        selectedStage: selectedStage,
        decisionContext: decisionContext,
        stageDecision: acceptedDecision,
        workflowSpec: mergeResult.workflowSpec!,
        activeExecutionProgress: activeProgress,
        orphanExecutionProgress: orphanProgress,
      ),
    );
  }

  ConversationWorkflowConflictStageDecisionContext _decisionContext({
    required ConversationWorkflowStage workflowStage,
    required ConversationWorkflowStage approvedPlanStage,
    required String approvedPlanMarkdown,
    required ConversationWorkflowSpec workflowSpec,
    required List<ConversationExecutionTaskProgress> activeExecutionProgress,
    required List<ConversationExecutionTaskProgress> orphanExecutionProgress,
  }) {
    const schemaVersion = 1;
    final canonical = jsonEncode({
      'schemaVersion': schemaVersion,
      'workflowStage': workflowStage.name,
      'approvedPlanStage': approvedPlanStage.name,
      'approvedPlanMarkdown': approvedPlanMarkdown,
      'workflowSpec': workflowSpec.toJson(),
      'activeExecutionProgress': activeExecutionProgress
          .map((progress) => progress.toJson())
          .toList(growable: false),
      'orphanExecutionProgress': orphanExecutionProgress
          .map((progress) => progress.toJson())
          .toList(growable: false),
    });
    return ConversationWorkflowConflictStageDecisionContext(
      schemaVersion: schemaVersion,
      contextDigest: sha256.convert(utf8.encode(canonical)).toString(),
      workflowStage: workflowStage,
      approvedPlanStage: approvedPlanStage,
    );
  }

  bool _isValidDecision(ConversationWorkflowConflictStageDecision decision) {
    return decision.decisionId.trim().isNotEmpty &&
        RegExp(r'^[0-9a-f]{64}$').hasMatch(decision.contextDigest) &&
        decision.source ==
            ConversationWorkflowConflictStageDecisionSource
                .manualUserConfirmation &&
        decision.decidedAt.isUtc;
  }

  ConversationWorkflowConflictPreservationResult _blocked(
    List<ConversationWorkflowConflictPreservationBlocker> blockers, {
    List<ConversationWorkflowProvenanceMergeBlocker> mergeBlockers = const [],
  }) {
    return ConversationWorkflowConflictPreservationResult(
      blockers: blockers,
      mergeBlockers: mergeBlockers,
    );
  }

  ConversationWorkflowSpec _withoutProvenance(
    ConversationWorkflowSpec workflowSpec,
  ) {
    return workflowSpec.copyWith(
      sources: const <ConversationContractSourceReference>[],
      provenance: const <ConversationContractItemProvenance>[],
    );
  }
}
