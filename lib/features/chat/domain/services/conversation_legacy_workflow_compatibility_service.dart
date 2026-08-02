import '../entities/conversation.dart';
import '../entities/conversation_plan_artifact.dart';
import '../entities/conversation_workflow.dart';
import 'conversation_plan_document_builder.dart';
import 'conversation_plan_projection_service.dart';

enum ConversationLegacyWorkflowCompatibilityBlocker {
  contractProvenanceWouldChange,
  emptyTaskId,
  existingPlanDocumentConflict,
  workflowRoundTripMismatch,
  danglingExecutionProgress,
  danglingOpenQuestionProgress,
  projectionFailed,
  checkpointIncompatible,
}

class ConversationLegacyWorkflowCompatibilityResult {
  const ConversationLegacyWorkflowCompatibilityResult({
    required this.blockers,
    required this.workflowCheckpointCount,
  });

  final List<ConversationLegacyWorkflowCompatibilityBlocker> blockers;
  final int workflowCheckpointCount;

  bool get isCompatible => blockers.isEmpty;
}

class ConversationLegacyWorkflowCompatibilityService {
  ConversationLegacyWorkflowCompatibilityService._();

  static final DateTime _deterministicDerivedAt =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static ConversationLegacyWorkflowCompatibilityResult evaluate(
    Conversation conversation,
  ) {
    final blockers = <ConversationLegacyWorkflowCompatibilityBlocker>{};
    blockers.addAll(
      _evaluateSnapshot(
        workflowStage: conversation.workflowStage,
        workflowSpec: conversation.effectiveWorkflowSpec,
        executionProgress: conversation.executionProgress,
        openQuestionProgress: conversation.openQuestionProgress,
        planArtifact: conversation.planArtifact,
      ),
    );

    var workflowCheckpointCount = 0;
    for (final checkpoint in conversation.checkpoints) {
      final workflowSpec =
          checkpoint.workflowSpec ?? const ConversationWorkflowSpec();
      if (!_hasWorkflowContext(checkpoint.workflowStage, workflowSpec)) {
        continue;
      }
      workflowCheckpointCount++;
      final checkpointBlockers = _evaluateSnapshot(
        workflowStage: checkpoint.workflowStage,
        workflowSpec: workflowSpec,
        executionProgress: checkpoint.executionProgress,
        openQuestionProgress: checkpoint.openQuestionProgress,
        planArtifact: checkpoint.planArtifact,
      );
      if (checkpointBlockers.isNotEmpty) {
        blockers
          ..addAll(checkpointBlockers)
          ..add(
            ConversationLegacyWorkflowCompatibilityBlocker
                .checkpointIncompatible,
          );
      }
    }

    return ConversationLegacyWorkflowCompatibilityResult(
      blockers: ConversationLegacyWorkflowCompatibilityBlocker.values
          .where(blockers.contains)
          .toList(growable: false),
      workflowCheckpointCount: workflowCheckpointCount,
    );
  }

  static Set<ConversationLegacyWorkflowCompatibilityBlocker> _evaluateSnapshot({
    required ConversationWorkflowStage workflowStage,
    required ConversationWorkflowSpec workflowSpec,
    required List<ConversationExecutionTaskProgress> executionProgress,
    required List<ConversationOpenQuestionProgress> openQuestionProgress,
    required ConversationPlanArtifact? planArtifact,
  }) {
    final blockers = <ConversationLegacyWorkflowCompatibilityBlocker>{};
    if (workflowSpec.sources.isNotEmpty || workflowSpec.provenance.isNotEmpty) {
      blockers.add(
        ConversationLegacyWorkflowCompatibilityBlocker
            .contractProvenanceWouldChange,
      );
    }
    if (workflowSpec.tasks.any((task) => task.id.trim().isEmpty)) {
      blockers.add(ConversationLegacyWorkflowCompatibilityBlocker.emptyTaskId);
    }

    final taskIds = workflowSpec.tasks
        .map((task) => task.id.trim())
        .where((taskId) => taskId.isNotEmpty)
        .toSet();
    if (executionProgress.any(
      (progress) => !taskIds.contains(progress.taskId.trim()),
    )) {
      blockers.add(
        ConversationLegacyWorkflowCompatibilityBlocker
            .danglingExecutionProgress,
      );
    }

    final openQuestionIds = workflowSpec.openQuestions
        .map(Conversation.openQuestionIdFor)
        .where((questionId) => questionId.isNotEmpty)
        .toSet();
    if (openQuestionProgress.any(
      (progress) => !openQuestionIds.contains(progress.questionId.trim()),
    )) {
      blockers.add(
        ConversationLegacyWorkflowCompatibilityBlocker
            .danglingOpenQuestionProgress,
      );
    }

    try {
      final generatedArtifact =
          ConversationPlanDocumentBuilder.buildApprovedArtifact(
            workflowStage: workflowStage,
            workflowSpec: workflowSpec,
            updatedAt: _deterministicDerivedAt,
          );
      final generatedMarkdown = generatedArtifact.normalizedApprovedMarkdown!;
      final existingMarkdown = planArtifact?.executionMarkdown;
      if (existingMarkdown != null &&
          existingMarkdown.trim() != generatedMarkdown.trim()) {
        blockers.add(
          ConversationLegacyWorkflowCompatibilityBlocker
              .existingPlanDocumentConflict,
        );
      }

      final projection =
          ConversationPlanProjectionService.deriveExecutionProjection(
            approvedMarkdown: generatedMarkdown,
            derivedAt: _deterministicDerivedAt,
          );
      final stabilizedWorkflowSpec =
          ConversationPlanProjectionService.stabilizeTaskIds(
            previousTasks: workflowSpec.tasks,
            workflowSpec: projection.workflowSpec,
            anchoredTaskIndexes: projection.anchoredTaskIndexes,
          );
      if (projection.workflowStage != workflowStage ||
          _withoutProvenance(stabilizedWorkflowSpec) !=
              _withoutProvenance(workflowSpec)) {
        blockers.add(
          ConversationLegacyWorkflowCompatibilityBlocker
              .workflowRoundTripMismatch,
        );
      }
    } on FormatException {
      blockers.add(
        ConversationLegacyWorkflowCompatibilityBlocker.projectionFailed,
      );
    }

    return blockers;
  }

  static bool _hasWorkflowContext(
    ConversationWorkflowStage workflowStage,
    ConversationWorkflowSpec workflowSpec,
  ) {
    return workflowStage != ConversationWorkflowStage.idle ||
        workflowSpec.hasContent;
  }

  static ConversationWorkflowSpec _withoutProvenance(
    ConversationWorkflowSpec workflowSpec,
  ) {
    return workflowSpec.copyWith(
      sources: const <ConversationContractSourceReference>[],
      provenance: const <ConversationContractItemProvenance>[],
    );
  }
}
