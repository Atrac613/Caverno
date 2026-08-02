import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_legacy_workflow_compatibility_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_hash.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_workflow_provenance_merge_service.dart';

const String auditSchemaName = 'caverno_legacy_workflow_compatibility_audit';
const int auditSchemaVersion = 4;

final class CompatibilityAuditException implements Exception {
  const CompatibilityAuditException(this.message);

  final String message;

  @override
  String toString() => message;
}

Map<String, Object> auditLegacyWorkflowCompatibility(File databaseFile) {
  if (!databaseFile.existsSync()) {
    throw const CompatibilityAuditException(
      'Conversation database file does not exist.',
    );
  }

  final Database database;
  try {
    database = sqlite3.open(databaseFile.path, mode: OpenMode.readOnly);
  } on SqliteException catch (_) {
    throw const CompatibilityAuditException(
      'Conversation database could not be opened read-only.',
    );
  }

  final List<Object?> payloads;
  try {
    database.execute('PRAGMA query_only = ON');
    payloads = database
        .select('SELECT payload FROM conversations ORDER BY id')
        .map((row) => row['payload'])
        .toList(growable: false);
  } on SqliteException catch (_) {
    throw const CompatibilityAuditException(
      'Conversation table could not be read.',
    );
  } finally {
    database.close();
  }

  return buildLegacyWorkflowCompatibilityReport(payloads);
}

Map<String, Object> buildLegacyWorkflowCompatibilityReport(
  Iterable<Object?> encodedPayloads,
) {
  var databaseRowCount = 0;
  var invalidRecordCount = 0;
  var legacyCandidateCount = 0;
  var compatibleRecordCount = 0;
  var blockedRecordCount = 0;
  var workflowCheckpointCount = 0;
  final blockerRecordCounts = _emptyBlockerCounts();
  final currentBlockerRecordCounts = _emptyBlockerCounts();
  final checkpointBlockerRecordCounts = _emptyBlockerCounts();
  final currentProvenanceShapes = _ProvenanceShapeAccumulator();
  final checkpointProvenanceShapes = _ProvenanceShapeAccumulator();
  var provenanceBlockedRecordCount = 0;
  var provenanceOnlyRecordCount = 0;
  var planProgressConflictRecordCount = 0;
  var danglingExecutionProgressRecordCount = 0;
  var existingPlanConflictRecordCount = 0;
  var combinedPlanProgressConflictRecordCount = 0;
  var legacyCheckpointSnapshotCount = 0;
  var freshCheckpointSnapshotCount = 0;
  var inconsistentCheckpointSnapshotCount = 0;
  var provenanceMergeCandidateRecordCount = 0;
  final currentMergeCandidates = _ProvenanceMergeCandidateAccumulator();
  final checkpointMergeCandidates = _ProvenanceMergeCandidateAccumulator();
  final planProgressConflicts = _PlanProgressConflictAccumulator();

  for (final encodedPayload in encodedPayloads) {
    databaseRowCount++;
    if (encodedPayload is! String) {
      invalidRecordCount++;
      continue;
    }
    final Conversation conversation;
    try {
      final decoded = jsonDecode(encodedPayload);
      if (decoded is! Map<String, dynamic>) {
        invalidRecordCount++;
        continue;
      }
      conversation = Conversation.fromJson(decoded);
    } on Object {
      invalidRecordCount++;
      continue;
    }

    if (!_isLegacyAuthoredWorkflow(conversation)) {
      continue;
    }
    legacyCandidateCount++;
    final result = ConversationLegacyWorkflowCompatibilityService.evaluate(
      conversation,
    );
    workflowCheckpointCount += result.workflowCheckpointCount;
    if (result.isCompatible) {
      compatibleRecordCount++;
      continue;
    }
    blockedRecordCount++;
    for (final blocker in result.blockers) {
      blockerRecordCounts[blocker.name] =
          blockerRecordCounts[blocker.name]! + 1;
    }
    for (final blocker in result.currentBlockers) {
      currentBlockerRecordCounts[blocker.name] =
          currentBlockerRecordCounts[blocker.name]! + 1;
    }
    for (final blocker in result.checkpointBlockers) {
      checkpointBlockerRecordCounts[blocker.name] =
          checkpointBlockerRecordCounts[blocker.name]! + 1;
    }
    final isProvenanceMergeCandidate = _isProvenanceMergeCandidate(result);
    if (isProvenanceMergeCandidate) {
      provenanceMergeCandidateRecordCount++;
      currentMergeCandidates.add(
        workflowStage: conversation.workflowStage,
        workflowSpec: conversation.effectiveWorkflowSpec,
      );
    }
    final hasProvenanceBlocker = result.currentBlockers.contains(
      ConversationLegacyWorkflowCompatibilityBlocker
          .contractProvenanceWouldChange,
    );
    if (hasProvenanceBlocker) {
      provenanceBlockedRecordCount++;
      currentProvenanceShapes.add(conversation.effectiveWorkflowSpec);
      final hasDanglingProgress = result.blockers.contains(
        ConversationLegacyWorkflowCompatibilityBlocker
            .danglingExecutionProgress,
      );
      final hasPlanConflict = result.blockers.contains(
        ConversationLegacyWorkflowCompatibilityBlocker
            .existingPlanDocumentConflict,
      );
      if (hasDanglingProgress) danglingExecutionProgressRecordCount++;
      if (hasPlanConflict) existingPlanConflictRecordCount++;
      if (hasDanglingProgress && hasPlanConflict) {
        combinedPlanProgressConflictRecordCount++;
        planProgressConflicts.add(conversation);
      }
      if (hasDanglingProgress || hasPlanConflict) {
        planProgressConflictRecordCount++;
      } else {
        provenanceOnlyRecordCount++;
      }

      for (final checkpoint in conversation.checkpoints) {
        final workflowSpec =
            checkpoint.workflowSpec ?? const ConversationWorkflowSpec();
        if (!_hasWorkflowContext(checkpoint.workflowStage, workflowSpec)) {
          continue;
        }
        final checkpointOrigin = _checkpointOrigin(checkpoint, workflowSpec);
        switch (checkpointOrigin) {
          case _CheckpointOrigin.legacy:
            legacyCheckpointSnapshotCount++;
            checkpointProvenanceShapes.add(workflowSpec);
            if (isProvenanceMergeCandidate) {
              checkpointMergeCandidates.add(
                workflowStage: checkpoint.workflowStage,
                workflowSpec: workflowSpec,
              );
            }
          case _CheckpointOrigin.freshProjection:
            freshCheckpointSnapshotCount++;
          case _CheckpointOrigin.inconsistentProjection:
            inconsistentCheckpointSnapshotCount++;
        }
      }
    }
  }

  final migrationCandidateReady =
      invalidRecordCount == 0 &&
      legacyCandidateCount > 0 &&
      blockedRecordCount == 0;
  final nextAction = invalidRecordCount > 0
      ? 'repair_invalid_records_before_migration_design'
      : legacyCandidateCount == 0
      ? 'verify_legacy_origin_selection'
      : blockedRecordCount > 0
      ? 'design_blocker_specific_preservation'
      : 'design_candidate_transformer';
  final allProvenanceMergeCandidatesMergeable =
      provenanceMergeCandidateRecordCount > 0 &&
      currentMergeCandidates.allMergeable &&
      checkpointMergeCandidates.allMergeable;
  final provenanceMergeNextAction = provenanceMergeCandidateRecordCount == 0
      ? 'verify_provenance_only_cohort_selection'
      : allProvenanceMergeCandidatesMergeable
      ? 'define_plan_progress_conflict_policy'
      : 'inspect_aggregate_provenance_merge_blockers';

  return {
    'schemaName': auditSchemaName,
    'schemaVersion': auditSchemaVersion,
    'summary': {
      'databaseRowCount': databaseRowCount,
      'invalidRecordCount': invalidRecordCount,
      'legacyCandidateCount': legacyCandidateCount,
      'compatibleRecordCount': compatibleRecordCount,
      'blockedRecordCount': blockedRecordCount,
      'workflowCheckpointCount': workflowCheckpointCount,
      'blockerRecordCounts': blockerRecordCounts,
      'currentBlockerRecordCounts': currentBlockerRecordCounts,
      'checkpointBlockerRecordCounts': checkpointBlockerRecordCounts,
    },
    'decision': {
      'migrationCandidateReady': migrationCandidateReady,
      'nextAction': nextAction,
    },
    'provenanceShapes': {
      'cohorts': {
        'provenanceBlockedRecordCount': provenanceBlockedRecordCount,
        'provenanceOnlyRecordCount': provenanceOnlyRecordCount,
        'planProgressConflictRecordCount': planProgressConflictRecordCount,
        'danglingExecutionProgressRecordCount':
            danglingExecutionProgressRecordCount,
        'existingPlanConflictRecordCount': existingPlanConflictRecordCount,
        'combinedPlanProgressConflictRecordCount':
            combinedPlanProgressConflictRecordCount,
      },
      'checkpointOrigins': {
        'legacySnapshotCount': legacyCheckpointSnapshotCount,
        'freshProjectionSnapshotCount': freshCheckpointSnapshotCount,
        'inconsistentProjectionSnapshotCount':
            inconsistentCheckpointSnapshotCount,
      },
      'currentWorkflows': currentProvenanceShapes.toJson(),
      'legacyCheckpoints': checkpointProvenanceShapes.toJson(),
    },
    'provenanceMergeCandidate': {
      'cohort': {
        'eligibleRecordCount': provenanceMergeCandidateRecordCount,
        'excludedProvenanceBlockedRecordCount':
            provenanceBlockedRecordCount - provenanceMergeCandidateRecordCount,
      },
      'currentWorkflows': currentMergeCandidates.toJson(),
      'legacyCheckpoints': checkpointMergeCandidates.toJson(),
      'decision': {
        'allEligibleSnapshotsMergeable': allProvenanceMergeCandidatesMergeable,
        'nextAction': provenanceMergeNextAction,
      },
    },
    'planProgressConflictPolicy': planProgressConflicts.toJson(),
    'privacy': {
      'includesDatabasePath': false,
      'includesRecordIdentifiers': false,
      'includesRecordContent': false,
      'includesIndividualResults': false,
      'includesSourceIdentifiers': false,
      'includesItemIdentifiers': false,
      'includesSourceLocators': false,
    },
  };
}

bool _isProvenanceMergeCandidate(
  ConversationLegacyWorkflowCompatibilityResult result,
) {
  const provenance = ConversationLegacyWorkflowCompatibilityBlocker
      .contractProvenanceWouldChange;
  const checkpointIncompatible =
      ConversationLegacyWorkflowCompatibilityBlocker.checkpointIncompatible;
  return result.currentBlockers.length == 1 &&
      result.currentBlockers.single == provenance &&
      result.blockers.every(
        (blocker) => blocker == provenance || blocker == checkpointIncompatible,
      );
}

final class _ProvenanceMergeCandidateAccumulator {
  static final DateTime _deterministicDerivedAt =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  var evaluatedSnapshotCount = 0;
  var mergeableSnapshotCount = 0;
  var blockedSnapshotCount = 0;
  var projectionFailureSnapshotCount = 0;
  final blockerSnapshotCounts = {
    for (final blocker in ConversationWorkflowProvenanceMergeBlocker.values)
      blocker.name: 0,
  };

  bool get allMergeable =>
      blockedSnapshotCount == 0 && projectionFailureSnapshotCount == 0;

  void add({
    required ConversationWorkflowStage workflowStage,
    required ConversationWorkflowSpec workflowSpec,
  }) {
    evaluatedSnapshotCount++;
    try {
      final artifact = ConversationPlanDocumentBuilder.buildApprovedArtifact(
        workflowStage: workflowStage,
        workflowSpec: workflowSpec,
        updatedAt: _deterministicDerivedAt,
      );
      final projection =
          ConversationPlanProjectionService.deriveExecutionProjection(
            approvedMarkdown: artifact.normalizedApprovedMarkdown!,
            derivedAt: _deterministicDerivedAt,
          );
      final stabilizedWorkflowSpec =
          ConversationPlanProjectionService.stabilizeTaskIds(
            previousTasks: workflowSpec.tasks,
            workflowSpec: projection.workflowSpec,
            anchoredTaskIndexes: projection.anchoredTaskIndexes,
          );
      final result = const ConversationWorkflowProvenanceMergeService().merge(
        legacyWorkflowSpec: workflowSpec,
        projectedWorkflowSpec: stabilizedWorkflowSpec,
      );
      if (result.isMergeable) {
        mergeableSnapshotCount++;
        return;
      }
      blockedSnapshotCount++;
      for (final blocker in result.blockers) {
        blockerSnapshotCounts[blocker.name] =
            blockerSnapshotCounts[blocker.name]! + 1;
      }
    } on FormatException {
      projectionFailureSnapshotCount++;
    }
  }

  Map<String, Object> toJson() => {
    'evaluatedSnapshotCount': evaluatedSnapshotCount,
    'mergeableSnapshotCount': mergeableSnapshotCount,
    'blockedSnapshotCount': blockedSnapshotCount,
    'projectionFailureSnapshotCount': projectionFailureSnapshotCount,
    'blockerSnapshotCounts': blockerSnapshotCounts,
  };
}

enum _ConflictPlanProjectionOutcome { parsed, failed }

enum _ConflictStageRelation { equivalent, divergent, unavailable }

enum _ConflictSemanticRelation { equivalent, divergent, unavailable }

enum _ConflictProgressOwnership {
  allOwnedByExistingPlan,
  partiallyOwnedByExistingPlan,
  noneOwnedByExistingPlan,
  unavailable,
}

enum _ConflictProgressState { passiveOnly, meaningful }

enum _ConflictCheckpointProgressOwnership {
  allOwnedBySingleCheckpoint,
  ownedAcrossMultipleCheckpoints,
  partiallyOwnedByCheckpoints,
  noneOwnedByCheckpoints,
}

enum _ConflictProvenanceMergeOutcome { mergeable, blocked, unavailable }

final class _PlanProgressConflictAccumulator {
  static final DateTime _deterministicDerivedAt =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  var evaluatedRecordCount = 0;
  var fullyConstrainedCandidateCount = 0;
  final projectionOutcomeRecordCounts = {
    for (final value in _ConflictPlanProjectionOutcome.values) value.name: 0,
  };
  final semanticRelationRecordCounts = {
    for (final value in _ConflictSemanticRelation.values) value.name: 0,
  };
  final stageRelationRecordCounts = {
    for (final value in _ConflictStageRelation.values) value.name: 0,
  };
  final progressOwnershipRecordCounts = {
    for (final value in _ConflictProgressOwnership.values) value.name: 0,
  };
  final progressStateRecordCounts = {
    for (final value in _ConflictProgressState.values) value.name: 0,
  };
  final checkpointProgressOwnershipRecordCounts = {
    for (final value in _ConflictCheckpointProgressOwnership.values)
      value.name: 0,
  };
  final provenanceMergeOutcomeRecordCounts = {
    for (final value in _ConflictProvenanceMergeOutcome.values) value.name: 0,
  };

  void add(Conversation conversation) {
    evaluatedRecordCount++;
    final workflowSpec = conversation.effectiveWorkflowSpec;
    final danglingProgress = conversation.executionProgress
        .where(
          (progress) => !workflowSpec.tasks.any(
            (task) => task.id.trim() == progress.taskId.trim(),
          ),
        )
        .toList(growable: false);
    final progressState =
        danglingProgress.any((progress) => progress.hasMeaningfulState)
        ? _ConflictProgressState.meaningful
        : _ConflictProgressState.passiveOnly;
    _increment(progressStateRecordCounts, progressState.name);
    final checkpointOwnership = _checkpointOwnership(
      conversation,
      danglingProgress.map((progress) => progress.taskId.trim()).toSet(),
    );
    _increment(
      checkpointProgressOwnershipRecordCounts,
      checkpointOwnership.name,
    );

    final existingMarkdown = conversation.planArtifact?.executionMarkdown;
    if (existingMarkdown == null) {
      _recordUnavailableProjection();
      return;
    }

    final ConversationPlanProjection projection;
    try {
      projection = ConversationPlanProjectionService.deriveExecutionProjection(
        approvedMarkdown: existingMarkdown,
        derivedAt: _deterministicDerivedAt,
      );
    } on FormatException {
      _recordUnavailableProjection();
      return;
    }
    _increment(
      projectionOutcomeRecordCounts,
      _ConflictPlanProjectionOutcome.parsed.name,
    );

    final projectedTaskIds = projection.workflowSpec.tasks
        .map((task) => task.id.trim())
        .where((taskId) => taskId.isNotEmpty)
        .toSet();
    final ownedProgressCount = danglingProgress
        .where((progress) => projectedTaskIds.contains(progress.taskId.trim()))
        .length;
    final progressOwnership = ownedProgressCount == danglingProgress.length
        ? _ConflictProgressOwnership.allOwnedByExistingPlan
        : ownedProgressCount == 0
        ? _ConflictProgressOwnership.noneOwnedByExistingPlan
        : _ConflictProgressOwnership.partiallyOwnedByExistingPlan;
    _increment(progressOwnershipRecordCounts, progressOwnership.name);

    final stabilizedWorkflowSpec =
        ConversationPlanProjectionService.stabilizeTaskIds(
          previousTasks: workflowSpec.tasks,
          workflowSpec: projection.workflowSpec,
          anchoredTaskIndexes: projection.anchoredTaskIndexes,
        );
    final stageRelation = projection.workflowStage == conversation.workflowStage
        ? _ConflictStageRelation.equivalent
        : _ConflictStageRelation.divergent;
    _increment(stageRelationRecordCounts, stageRelation.name);
    final semanticRelation =
        _withoutProvenance(stabilizedWorkflowSpec) ==
            _withoutProvenance(workflowSpec)
        ? _ConflictSemanticRelation.equivalent
        : _ConflictSemanticRelation.divergent;
    _increment(semanticRelationRecordCounts, semanticRelation.name);

    final mergeResult = const ConversationWorkflowProvenanceMergeService()
        .merge(
          legacyWorkflowSpec: workflowSpec,
          projectedWorkflowSpec: stabilizedWorkflowSpec,
        );
    final mergeOutcome = mergeResult.isMergeable
        ? _ConflictProvenanceMergeOutcome.mergeable
        : _ConflictProvenanceMergeOutcome.blocked;
    _increment(provenanceMergeOutcomeRecordCounts, mergeOutcome.name);

    if (stageRelation == _ConflictStageRelation.equivalent &&
        semanticRelation == _ConflictSemanticRelation.equivalent &&
        progressOwnership ==
            _ConflictProgressOwnership.allOwnedByExistingPlan &&
        mergeOutcome == _ConflictProvenanceMergeOutcome.mergeable) {
      fullyConstrainedCandidateCount++;
    }
  }

  void _recordUnavailableProjection() {
    _increment(
      projectionOutcomeRecordCounts,
      _ConflictPlanProjectionOutcome.failed.name,
    );
    _increment(
      semanticRelationRecordCounts,
      _ConflictSemanticRelation.unavailable.name,
    );
    _increment(
      stageRelationRecordCounts,
      _ConflictStageRelation.unavailable.name,
    );
    _increment(
      progressOwnershipRecordCounts,
      _ConflictProgressOwnership.unavailable.name,
    );
    _increment(
      provenanceMergeOutcomeRecordCounts,
      _ConflictProvenanceMergeOutcome.unavailable.name,
    );
  }

  Map<String, Object> toJson() {
    final manualReviewRecordCount =
        evaluatedRecordCount - fullyConstrainedCandidateCount;
    return {
      'cohort': {'eligibleRecordCount': evaluatedRecordCount},
      'currentWorkflows': {
        'evaluatedRecordCount': evaluatedRecordCount,
        'projectionOutcomeRecordCounts': projectionOutcomeRecordCounts,
        'stageRelationRecordCounts': stageRelationRecordCounts,
        'semanticRelationRecordCounts': semanticRelationRecordCounts,
        'progressOwnershipRecordCounts': progressOwnershipRecordCounts,
        'checkpointProgressOwnershipRecordCounts':
            checkpointProgressOwnershipRecordCounts,
        'progressStateRecordCounts': progressStateRecordCounts,
        'provenanceMergeOutcomeRecordCounts':
            provenanceMergeOutcomeRecordCounts,
      },
      'decision': {
        'fullyConstrainedCandidateCount': fullyConstrainedCandidateCount,
        'manualReviewRecordCount': manualReviewRecordCount,
        'nextAction': evaluatedRecordCount == 0
            ? 'verify_plan_progress_conflict_cohort_selection'
            : manualReviewRecordCount == 0
            ? 'design_conflict_transformer'
            : 'define_manual_conflict_preservation',
      },
    };
  }

  _ConflictCheckpointProgressOwnership _checkpointOwnership(
    Conversation conversation,
    Set<String> danglingTaskIds,
  ) {
    final checkpointTaskIdSets = conversation.checkpoints
        .map(
          (checkpoint) => (checkpoint.workflowSpec?.tasks ?? const [])
              .map((task) => task.id.trim())
              .where((taskId) => taskId.isNotEmpty)
              .toSet(),
        )
        .where((taskIds) => taskIds.isNotEmpty)
        .toList(growable: false);
    if (checkpointTaskIdSets.any(
      (taskIds) => taskIds.containsAll(danglingTaskIds),
    )) {
      return _ConflictCheckpointProgressOwnership.allOwnedBySingleCheckpoint;
    }
    final checkpointTaskIds = checkpointTaskIdSets
        .expand((taskIds) => taskIds)
        .toSet();
    final ownedCount = danglingTaskIds.intersection(checkpointTaskIds).length;
    if (ownedCount == danglingTaskIds.length) {
      return _ConflictCheckpointProgressOwnership
          .ownedAcrossMultipleCheckpoints;
    }
    if (ownedCount > 0) {
      return _ConflictCheckpointProgressOwnership.partiallyOwnedByCheckpoints;
    }
    return _ConflictCheckpointProgressOwnership.noneOwnedByCheckpoints;
  }
}

void _increment(Map<String, int> counts, String key) {
  counts[key] = counts[key]! + 1;
}

ConversationWorkflowSpec _withoutProvenance(
  ConversationWorkflowSpec workflowSpec,
) {
  return workflowSpec.copyWith(
    sources: const <ConversationContractSourceReference>[],
    provenance: const <ConversationContractItemProvenance>[],
  );
}

enum _CheckpointOrigin { legacy, freshProjection, inconsistentProjection }

_CheckpointOrigin _checkpointOrigin(
  ConversationCheckpoint checkpoint,
  ConversationWorkflowSpec workflowSpec,
) {
  final sourceHash = checkpoint.workflowSourceHash.trim();
  final executionDocument = checkpoint.planArtifact?.executionMarkdown;
  final hasAnyProjectionMetadata =
      sourceHash.isNotEmpty || checkpoint.workflowDerivedAt != null;
  if (sourceHash.isNotEmpty &&
      checkpoint.workflowDerivedAt != null &&
      workflowSpec.hasContent &&
      executionDocument != null &&
      sourceHash == computeConversationPlanHash(executionDocument)) {
    return _CheckpointOrigin.freshProjection;
  }
  return hasAnyProjectionMetadata
      ? _CheckpointOrigin.inconsistentProjection
      : _CheckpointOrigin.legacy;
}

bool _hasWorkflowContext(
  ConversationWorkflowStage workflowStage,
  ConversationWorkflowSpec workflowSpec,
) {
  return workflowStage != ConversationWorkflowStage.idle ||
      workflowSpec.hasContent;
}

final class _ProvenanceShapeAccumulator {
  var snapshotCount = 0;
  final sourceKindSnapshotCounts = {
    for (final kind in ConversationContractSourceKind.values) kind.name: 0,
  };
  final itemKindSnapshotCounts = {
    for (final kind in ConversationContractItemKind.values) kind.name: 0,
  };
  final conditionSnapshotCounts = {
    for (final condition in _ProvenanceCondition.values) condition.name: 0,
  };

  void add(ConversationWorkflowSpec workflowSpec) {
    snapshotCount++;
    for (final kind
        in workflowSpec.sources.map((source) => source.kind).toSet()) {
      sourceKindSnapshotCounts[kind.name] =
          sourceKindSnapshotCounts[kind.name]! + 1;
    }
    for (final kind
        in workflowSpec.provenance.map((item) => item.kind).toSet()) {
      itemKindSnapshotCounts[kind.name] =
          itemKindSnapshotCounts[kind.name]! + 1;
    }

    final sourceIds = workflowSpec.sources
        .map((source) => source.id.trim())
        .toList();
    final itemIds = workflowSpec.provenance
        .map((item) => item.itemId.trim())
        .toList();
    final definedSourceIds = sourceIds.where((id) => id.isNotEmpty).toSet();
    final referencedSourceIds = workflowSpec.provenance
        .expand((item) => item.sourceIds)
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final conditions = <_ProvenanceCondition>{};
    if (workflowSpec.sources.isEmpty) {
      conditions.add(_ProvenanceCondition.noSources);
    }
    if (workflowSpec.provenance.isEmpty) {
      conditions.add(_ProvenanceCondition.noProvenance);
    }
    if (sourceIds.any((id) => id.isEmpty)) {
      conditions.add(_ProvenanceCondition.emptySourceId);
    }
    if (_hasDuplicates(sourceIds.where((id) => id.isNotEmpty))) {
      conditions.add(_ProvenanceCondition.duplicateSourceId);
    }
    if (itemIds.any((id) => id.isEmpty)) {
      conditions.add(_ProvenanceCondition.emptyItemId);
    }
    if (_hasDuplicates(itemIds.where((id) => id.isNotEmpty))) {
      conditions.add(_ProvenanceCondition.duplicateItemId);
    }
    if (workflowSpec.provenance.any(
      (item) =>
          item.sourceIds.isEmpty ||
          item.sourceIds.any((id) => id.trim().isEmpty),
    )) {
      conditions.add(_ProvenanceCondition.emptySourceReferences);
    }
    if (workflowSpec.provenance.any(
      (item) => item.sourceIds.where((id) => id.trim().isNotEmpty).length > 1,
    )) {
      conditions.add(_ProvenanceCondition.multipleSourceReferences);
    }
    if (referencedSourceIds.difference(definedSourceIds).isNotEmpty) {
      conditions.add(_ProvenanceCondition.orphanSourceReference);
    }
    if (definedSourceIds.difference(referencedSourceIds).isNotEmpty) {
      conditions.add(_ProvenanceCondition.unreferencedSource);
    }
    if (workflowSpec.provenance.any((item) => item.blocksExecution)) {
      conditions.add(_ProvenanceCondition.blockingAssumption);
    }
    if (workflowSpec.provenance.any(
      (item) => item.assumption && item.material,
    )) {
      conditions.add(_ProvenanceCondition.materialAssumption);
    }
    if (workflowSpec.provenance.any(
      (item) => item.assumption && item.confirmed,
    )) {
      conditions.add(_ProvenanceCondition.confirmedAssumption);
    }
    if (workflowSpec.provenance.any(
      (item) => item.normalizedClarificationQuestion != null,
    )) {
      conditions.add(_ProvenanceCondition.clarificationQuestionPresent);
    }
    for (final condition in conditions) {
      conditionSnapshotCounts[condition.name] =
          conditionSnapshotCounts[condition.name]! + 1;
    }
  }

  Map<String, Object> toJson() => {
    'snapshotCount': snapshotCount,
    'sourceKindSnapshotCounts': sourceKindSnapshotCounts,
    'itemKindSnapshotCounts': itemKindSnapshotCounts,
    'conditionSnapshotCounts': conditionSnapshotCounts,
  };
}

enum _ProvenanceCondition {
  noSources,
  noProvenance,
  emptySourceId,
  duplicateSourceId,
  emptyItemId,
  duplicateItemId,
  emptySourceReferences,
  multipleSourceReferences,
  orphanSourceReference,
  unreferencedSource,
  blockingAssumption,
  materialAssumption,
  confirmedAssumption,
  clarificationQuestionPresent,
}

bool _hasDuplicates(Iterable<String> values) {
  final seen = <String>{};
  return values.any((value) => !seen.add(value));
}

Map<String, int> _emptyBlockerCounts() {
  return {
    for (final blocker in ConversationLegacyWorkflowCompatibilityBlocker.values)
      blocker.name: 0,
  };
}

bool _isLegacyAuthoredWorkflow(Conversation conversation) {
  if (!conversation.hasWorkflowContext ||
      conversation.workflowSourceHash.trim().isNotEmpty ||
      conversation.workflowDerivedAt != null) {
    return false;
  }
  return !conversation.effectiveWorkflowSpec.sources.any(
    (source) => source.kind == ConversationContractSourceKind.approvedPlan,
  );
}

int runAudit(List<String> arguments, {IOSink? output, IOSink? errorOutput}) {
  final resolvedOutput = output ?? stdout;
  final resolvedErrorOutput = errorOutput ?? stderr;
  if (arguments.length != 2 || arguments.first != '--database') {
    resolvedErrorOutput.writeln(
      'Usage: dart run tool/audit_legacy_workflow_compatibility.dart '
      '--database <path>',
    );
    return 64;
  }

  try {
    final report = auditLegacyWorkflowCompatibility(File(arguments[1]));
    resolvedOutput.writeln(const JsonEncoder.withIndent('  ').convert(report));
    return 0;
  } on CompatibilityAuditException catch (error) {
    resolvedErrorOutput.writeln(error.message);
    return 2;
  }
}

void main(List<String> arguments) {
  exitCode = runAudit(arguments);
}
