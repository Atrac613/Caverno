import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import 'conversation_plan_projection_service.dart';
import 'conversation_workflow_provenance_merge_service.dart';

enum ConversationWorkflowConflictStageAuthority { workflow, approvedPlan }

enum ConversationWorkflowConflictPreservationBlocker {
  missingPlanDocument,
  planProjectionFailed,
  semanticWorkflowMismatch,
  provenanceMergeBlocked,
  progressOwnedByExistingPlan,
  progressOwnedByCheckpoint,
  orphanProgressMissing,
  stageAuthorityRequired,
}

final class ConversationWorkflowConflictPreservationEnvelope {
  ConversationWorkflowConflictPreservationEnvelope({
    required this.workflowStage,
    required this.approvedPlanStage,
    required this.selectedStage,
    required this.workflowSpec,
    required List<ConversationExecutionTaskProgress> activeExecutionProgress,
    required List<ConversationExecutionTaskProgress> orphanExecutionProgress,
  }) : activeExecutionProgress = List.unmodifiable(activeExecutionProgress),
       orphanExecutionProgress = List.unmodifiable(orphanExecutionProgress);

  final ConversationWorkflowStage workflowStage;
  final ConversationWorkflowStage approvedPlanStage;
  final ConversationWorkflowStage? selectedStage;
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
    ConversationWorkflowConflictStageAuthority? stageAuthority,
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

    final stagesDiffer = conversation.workflowStage != projection.workflowStage;
    final selectedStage = switch (stageAuthority) {
      ConversationWorkflowConflictStageAuthority.workflow =>
        conversation.workflowStage,
      ConversationWorkflowConflictStageAuthority.approvedPlan =>
        projection.workflowStage,
      null => stagesDiffer ? null : conversation.workflowStage,
    };
    if (selectedStage == null) {
      blockers.add(
        ConversationWorkflowConflictPreservationBlocker.stageAuthorityRequired,
      );
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
        workflowSpec: mergeResult.workflowSpec!,
        activeExecutionProgress: activeProgress,
        orphanExecutionProgress: orphanProgress,
      ),
    );
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
