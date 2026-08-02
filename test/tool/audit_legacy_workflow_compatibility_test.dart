import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_contract_provenance_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_legacy_workflow_compatibility_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_document_builder.dart';
import 'package:caverno/features/chat/domain/services/conversation_workflow_provenance_merge_service.dart';

import '../../tool/audit_legacy_workflow_compatibility.dart' as audit;

void main() {
  test('audits only legacy workflows and keeps database bytes unchanged', () {
    final directory = Directory.systemTemp.createTempSync(
      'caverno-legacy-compatibility-audit-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final databaseFile = File('${directory.path}/caverno.sqlite');
    _writeDatabase(databaseFile, [
      _conversation().toJson(),
      _conversation(
        id: 'blocked-legacy',
        workflowSpec: _workflowSpec.copyWith(
          sources: const [
            ConversationContractSourceReference(
              id: 'user-source',
              kind: ConversationContractSourceKind.userMessage,
            ),
          ],
        ),
      ).toJson(),
      _conversation(
        id: 'plan-derived',
        workflowSourceHash: 'source-hash',
        workflowDerivedAt: DateTime.utc(2026, 8, 2),
      ).toJson(),
      _conversation(
        id: 'no-workflow',
        workflowStage: ConversationWorkflowStage.idle,
        workflowSpec: const ConversationWorkflowSpec(),
      ).toJson(),
      'not-json',
    ]);
    final before = databaseFile.readAsBytesSync();

    final report = audit.auditLegacyWorkflowCompatibility(databaseFile);

    expect(databaseFile.readAsBytesSync(), before);
    expect(report['schemaName'], audit.auditSchemaName);
    expect(report['summary'], {
      'databaseRowCount': 5,
      'invalidRecordCount': 1,
      'legacyCandidateCount': 2,
      'compatibleRecordCount': 1,
      'blockedRecordCount': 1,
      'workflowCheckpointCount': 0,
      'blockerRecordCounts': {
        for (final blocker
            in ConversationLegacyWorkflowCompatibilityBlocker.values)
          blocker.name:
              blocker ==
                  ConversationLegacyWorkflowCompatibilityBlocker
                      .contractProvenanceWouldChange
              ? 1
              : 0,
      },
      'currentBlockerRecordCounts': {
        for (final blocker
            in ConversationLegacyWorkflowCompatibilityBlocker.values)
          blocker.name:
              blocker ==
                  ConversationLegacyWorkflowCompatibilityBlocker
                      .contractProvenanceWouldChange
              ? 1
              : 0,
      },
      'checkpointBlockerRecordCounts': {
        for (final blocker
            in ConversationLegacyWorkflowCompatibilityBlocker.values)
          blocker.name: 0,
      },
    });
    expect(report['decision'], {
      'migrationCandidateReady': false,
      'nextAction': 'repair_invalid_records_before_migration_design',
    });
    expect(report['privacy'], {
      'includesDatabasePath': false,
      'includesRecordIdentifiers': false,
      'includesRecordContent': false,
      'includesIndividualResults': false,
      'includesSourceIdentifiers': false,
      'includesItemIdentifiers': false,
      'includesSourceLocators': false,
    });
  });

  test('aggregates provenance graphs without exposing identifiers', () {
    final shapedSpec = _workflowSpec.copyWith(
      sources: const [
        ConversationContractSourceReference(
          id: 'private-source-a',
          kind: ConversationContractSourceKind.userMessage,
        ),
        ConversationContractSourceReference(
          id: 'private-source-b',
          kind: ConversationContractSourceKind.legacy,
        ),
        ConversationContractSourceReference(
          id: 'private-source-b',
          kind: ConversationContractSourceKind.legacy,
        ),
      ],
      provenance: const [
        ConversationContractItemProvenance(
          itemId: 'private-item-a',
          kind: ConversationContractItemKind.goal,
          sourceIds: ['private-source-a', 'missing-source'],
          assumption: true,
          material: true,
          clarificationQuestion: 'Private clarification?',
        ),
        ConversationContractItemProvenance(
          itemId: 'private-item-a',
          kind: ConversationContractItemKind.task,
        ),
      ],
    );
    final conversation = _conversation(
      workflowSpec: shapedSpec,
      checkpoints: [
        ConversationCheckpoint(
          messageId: 'private-message',
          messageCount: 2,
          title: 'Private checkpoint',
          createdAt: DateTime.utc(2026, 8, 2),
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: shapedSpec,
        ),
      ],
    );

    final report = audit.buildLegacyWorkflowCompatibilityReport([
      jsonEncode(conversation.toJson()),
    ]);
    final shapes = report['provenanceShapes']! as Map<String, Object>;
    final cohorts = shapes['cohorts']! as Map<String, int>;
    final current = shapes['currentWorkflows']! as Map<String, Object>;
    final sourceKinds =
        current['sourceKindSnapshotCounts']! as Map<String, int>;
    final itemKinds = current['itemKindSnapshotCounts']! as Map<String, int>;
    final conditions = current['conditionSnapshotCounts']! as Map<String, int>;

    expect(cohorts['provenanceBlockedRecordCount'], 1);
    expect(cohorts['provenanceOnlyRecordCount'], 1);
    expect(cohorts['planProgressConflictRecordCount'], 0);
    expect(sourceKinds[ConversationContractSourceKind.userMessage.name], 1);
    expect(sourceKinds[ConversationContractSourceKind.legacy.name], 1);
    expect(itemKinds[ConversationContractItemKind.goal.name], 1);
    expect(itemKinds[ConversationContractItemKind.task.name], 1);
    expect(conditions['duplicateSourceId'], 1);
    expect(conditions['duplicateItemId'], 1);
    expect(conditions['emptySourceReferences'], 1);
    expect(conditions['multipleSourceReferences'], 1);
    expect(conditions['orphanSourceReference'], 1);
    expect(conditions['unreferencedSource'], 1);
    expect(conditions['blockingAssumption'], 1);
    expect(conditions['materialAssumption'], 1);
    expect(conditions['clarificationQuestionPresent'], 1);
    expect(shapes['legacyCheckpoints'], current);
    final candidate =
        report['provenanceMergeCandidate']! as Map<String, Object>;
    final candidateCurrent =
        candidate['currentWorkflows']! as Map<String, Object>;
    final candidateBlockers =
        candidateCurrent['blockerSnapshotCounts']! as Map<String, int>;
    expect(candidateCurrent['evaluatedSnapshotCount'], 1);
    expect(candidateCurrent['blockedSnapshotCount'], 1);
    expect(candidateBlockers['invalidLegacySourceGraph'], 1);
    expect(candidateBlockers['invalidLegacyItemGraph'], 1);
    final encodedReport = jsonEncode(report);
    expect(encodedReport, isNot(contains('private-source')));
    expect(encodedReport, isNot(contains('private-item')));
    expect(encodedReport, isNot(contains('Private clarification')));
  });

  test('counts each blocker once per blocked record', () {
    final report = audit.buildLegacyWorkflowCompatibilityReport([
      jsonEncode(
        _conversation(
          executionProgress: const [
            ConversationExecutionTaskProgress(taskId: 'missing-task'),
          ],
          openQuestionProgress: const [
            ConversationOpenQuestionProgress(
              questionId: 'missing-question',
              question: 'Missing question?',
            ),
          ],
        ).toJson(),
      ),
    ]);
    final summary = report['summary']! as Map<String, Object>;
    final blockerCounts = summary['blockerRecordCounts']! as Map<String, int>;

    expect(summary['blockedRecordCount'], 1);
    expect(
      blockerCounts[ConversationLegacyWorkflowCompatibilityBlocker
          .danglingExecutionProgress
          .name],
      1,
    );
    expect(
      blockerCounts[ConversationLegacyWorkflowCompatibilityBlocker
          .danglingOpenQuestionProgress
          .name],
      1,
    );
  });

  test('validates merge candidates only for the provenance-only cohort', () {
    final provenanceWorkflowSpec = _provenanceWorkflowSpec();
    final cleanConversation = _conversation(
      workflowSpec: provenanceWorkflowSpec,
      checkpoints: [
        ConversationCheckpoint(
          messageId: 'checkpoint-message',
          messageCount: 2,
          title: 'Checkpoint',
          createdAt: DateTime.utc(2026, 8, 2),
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: provenanceWorkflowSpec,
        ),
      ],
    );
    final conflictConversation = _conversation(
      id: 'conflict-legacy',
      workflowSpec: provenanceWorkflowSpec,
      executionProgress: const [
        ConversationExecutionTaskProgress(taskId: 'missing-task'),
      ],
    );

    final report = audit.buildLegacyWorkflowCompatibilityReport([
      jsonEncode(cleanConversation.toJson()),
      jsonEncode(conflictConversation.toJson()),
    ]);
    final candidate =
        report['provenanceMergeCandidate']! as Map<String, Object>;

    expect(candidate['cohort'], {
      'eligibleRecordCount': 1,
      'excludedProvenanceBlockedRecordCount': 1,
    });
    expect(candidate['currentWorkflows'], {
      'evaluatedSnapshotCount': 1,
      'mergeableSnapshotCount': 1,
      'blockedSnapshotCount': 0,
      'projectionFailureSnapshotCount': 0,
      'blockerSnapshotCounts': _emptyMergeBlockerCounts(),
    });
    expect(candidate['legacyCheckpoints'], {
      'evaluatedSnapshotCount': 1,
      'mergeableSnapshotCount': 1,
      'blockedSnapshotCount': 0,
      'projectionFailureSnapshotCount': 0,
      'blockerSnapshotCounts': _emptyMergeBlockerCounts(),
    });
    expect(candidate['decision'], {
      'allEligibleSnapshotsMergeable': true,
      'nextAction': 'define_plan_progress_conflict_policy',
    });
  });

  test('classifies plan progress conflicts without exposing record data', () {
    final provenanceWorkflowSpec = _provenanceWorkflowSpec();
    final equivalentPlan =
        ConversationPlanDocumentBuilder.buildApprovedArtifact(
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: provenanceWorkflowSpec,
          updatedAt: DateTime.utc(2026, 8, 2),
        ).approvedMarkdown;
    final divergentPlan = ConversationPlanDocumentBuilder.buildApprovedArtifact(
      workflowStage: ConversationWorkflowStage.implement,
      workflowSpec: provenanceWorkflowSpec.copyWith(
        tasks: [provenanceWorkflowSpec.tasks.single.copyWith(id: 'plan-task')],
      ),
      updatedAt: DateTime.utc(2026, 8, 2),
    ).approvedMarkdown;
    final report = audit.buildLegacyWorkflowCompatibilityReport([
      jsonEncode(
        _conversation(
          id: 'plan-owned-private-record',
          workflowSpec: provenanceWorkflowSpec,
          executionProgress: [
            ConversationExecutionTaskProgress(
              taskId: 'plan-task',
              status: ConversationWorkflowTaskStatus.inProgress,
              summary: 'Private progress summary',
            ),
          ],
          planArtifact: ConversationPlanArtifact(
            approvedMarkdown: divergentPlan,
          ),
          checkpoints: [
            ConversationCheckpoint(
              messageId: 'private-checkpoint',
              messageCount: 1,
              title: 'Private checkpoint',
              createdAt: DateTime.utc(2026, 8, 2),
              workflowStage: ConversationWorkflowStage.implement,
              workflowSpec: provenanceWorkflowSpec.copyWith(
                tasks: [
                  provenanceWorkflowSpec.tasks.single.copyWith(id: 'plan-task'),
                ],
              ),
            ),
          ],
        ).toJson(),
      ),
      jsonEncode(
        _conversation(
          id: 'unowned-private-record',
          workflowSpec: provenanceWorkflowSpec,
          executionProgress: const [
            ConversationExecutionTaskProgress(taskId: 'missing-task'),
          ],
          planArtifact: ConversationPlanArtifact(
            approvedMarkdown: '$equivalentPlan\n\n## Notes\nPrivate note',
          ),
        ).toJson(),
      ),
      jsonEncode(
        _conversation(
          id: 'invalid-plan-private-record',
          workflowSpec: provenanceWorkflowSpec,
          executionProgress: const [
            ConversationExecutionTaskProgress(taskId: 'missing-task'),
          ],
          planArtifact: const ConversationPlanArtifact(
            approvedMarkdown: 'Private invalid plan',
          ),
        ).toJson(),
      ),
    ]);

    expect(report['schemaVersion'], 4);
    expect(report['planProgressConflictPolicy'], {
      'cohort': {'eligibleRecordCount': 3},
      'currentWorkflows': {
        'evaluatedRecordCount': 3,
        'projectionOutcomeRecordCounts': {'parsed': 2, 'failed': 1},
        'stageRelationRecordCounts': {
          'equivalent': 2,
          'divergent': 0,
          'unavailable': 1,
        },
        'semanticRelationRecordCounts': {
          'equivalent': 1,
          'divergent': 1,
          'unavailable': 1,
        },
        'progressOwnershipRecordCounts': {
          'allOwnedByExistingPlan': 1,
          'partiallyOwnedByExistingPlan': 0,
          'noneOwnedByExistingPlan': 1,
          'unavailable': 1,
        },
        'checkpointProgressOwnershipRecordCounts': {
          'allOwnedBySingleCheckpoint': 1,
          'ownedAcrossMultipleCheckpoints': 0,
          'partiallyOwnedByCheckpoints': 0,
          'noneOwnedByCheckpoints': 2,
        },
        'progressStateRecordCounts': {'passiveOnly': 2, 'meaningful': 1},
        'provenanceMergeOutcomeRecordCounts': {
          'mergeable': 1,
          'blocked': 1,
          'unavailable': 1,
        },
      },
      'decision': {
        'fullyConstrainedCandidateCount': 0,
        'manualReviewRecordCount': 3,
        'nextAction': 'define_manual_conflict_preservation',
      },
    });
    final encodedReport = jsonEncode(report);
    expect(encodedReport, isNot(contains('private-record')));
    expect(encodedReport, isNot(contains('Private progress')));
    expect(encodedReport, isNot(contains('Private note')));
    expect(encodedReport, isNot(contains('Private invalid')));
  });

  test('reports migration readiness only for compatible legacy candidates', () {
    final report = audit.buildLegacyWorkflowCompatibilityReport([
      jsonEncode(_conversation().toJson()),
    ]);

    expect(report['decision'], {
      'migrationCandidateReady': true,
      'nextAction': 'design_candidate_transformer',
    });
    expect(report['provenanceMergeCandidate'], {
      'cohort': {
        'eligibleRecordCount': 0,
        'excludedProvenanceBlockedRecordCount': 0,
      },
      'currentWorkflows': {
        'evaluatedSnapshotCount': 0,
        'mergeableSnapshotCount': 0,
        'blockedSnapshotCount': 0,
        'projectionFailureSnapshotCount': 0,
        'blockerSnapshotCounts': _emptyMergeBlockerCounts(),
      },
      'legacyCheckpoints': {
        'evaluatedSnapshotCount': 0,
        'mergeableSnapshotCount': 0,
        'blockedSnapshotCount': 0,
        'projectionFailureSnapshotCount': 0,
        'blockerSnapshotCounts': _emptyMergeBlockerCounts(),
      },
      'decision': {
        'allEligibleSnapshotsMergeable': false,
        'nextAction': 'verify_provenance_only_cohort_selection',
      },
    });
  });

  test('counts non-text payloads as invalid instead of dropping rows', () {
    final report = audit.buildLegacyWorkflowCompatibilityReport([
      jsonEncode(_conversation().toJson()),
      42,
    ]);
    final summary = report['summary']! as Map<String, Object>;

    expect(summary['databaseRowCount'], 2);
    expect(summary['legacyCandidateCount'], 1);
    expect(summary['invalidRecordCount'], 1);
    expect(report['decision'], {
      'migrationCandidateReady': false,
      'nextAction': 'repair_invalid_records_before_migration_design',
    });
  });

  test('keeps missing database failures path-free', () {
    final directory = Directory.systemTemp.createTempSync(
      'caverno-missing-compatibility-audit-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final missingPath = '${directory.path}/private-name.sqlite';

    expect(
      () => audit.auditLegacyWorkflowCompatibility(File(missingPath)),
      throwsA(
        isA<audit.CompatibilityAuditException>().having(
          (error) => error.message,
          'message',
          allOf(contains('does not exist'), isNot(contains(missingPath))),
        ),
      ),
    );
  });

  test('rejects databases without the conversation table', () {
    final directory = Directory.systemTemp.createTempSync(
      'caverno-empty-compatibility-audit-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final databaseFile = File('${directory.path}/empty.sqlite');
    sqlite3.open(databaseFile.path).close();

    expect(
      () => audit.auditLegacyWorkflowCompatibility(databaseFile),
      throwsA(
        isA<audit.CompatibilityAuditException>().having(
          (error) => error.message,
          'message',
          'Conversation table could not be read.',
        ),
      ),
    );
  });
}

const _workflowSpec = ConversationWorkflowSpec(
  goal: 'Preserve legacy execution state',
  openQuestions: ['Should rollout require a backup?'],
  tasks: [
    ConversationWorkflowTask(
      id: 'legacy-task-1',
      title: 'Build the compatibility fixture',
      validationCommand: 'flutter test',
    ),
  ],
);

ConversationWorkflowSpec _provenanceWorkflowSpec() {
  final projected = const ConversationContractProvenanceService()
      .attachApprovedPlanSource(
        workflowSpec: _workflowSpec,
        sourceHash: 'fixture-plan-hash',
      );
  return _workflowSpec.copyWith(
    sources: const [
      ConversationContractSourceReference(
        id: 'legacy-user-source',
        kind: ConversationContractSourceKind.userMessage,
      ),
    ],
    provenance: projected.provenance
        .map((item) => item.copyWith(sourceIds: const ['legacy-user-source']))
        .toList(growable: false),
  );
}

Map<String, int> _emptyMergeBlockerCounts() => {
  for (final blocker in ConversationWorkflowProvenanceMergeBlocker.values)
    blocker.name: 0,
};

Conversation _conversation({
  String id = 'compatible-legacy',
  ConversationWorkflowStage workflowStage = ConversationWorkflowStage.implement,
  ConversationWorkflowSpec workflowSpec = _workflowSpec,
  String workflowSourceHash = '',
  DateTime? workflowDerivedAt,
  List<ConversationExecutionTaskProgress> executionProgress = const [],
  List<ConversationOpenQuestionProgress> openQuestionProgress = const [],
  List<ConversationCheckpoint> checkpoints = const [],
  ConversationPlanArtifact? planArtifact,
}) {
  return Conversation(
    id: id,
    title: 'Fixture',
    messages: const [],
    createdAt: DateTime.utc(2026, 8, 2),
    updatedAt: DateTime.utc(2026, 8, 2),
    workflowStage: workflowStage,
    workflowSpec: workflowSpec,
    workflowSourceHash: workflowSourceHash,
    workflowDerivedAt: workflowDerivedAt,
    executionProgress: executionProgress,
    openQuestionProgress: openQuestionProgress,
    planArtifact: planArtifact,
    checkpoints: checkpoints,
  );
}

void _writeDatabase(File file, List<Object> payloads) {
  final database = sqlite3.open(file.path);
  try {
    database.execute(
      'CREATE TABLE conversations (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
    );
    final statement = database.prepare(
      'INSERT INTO conversations (id, payload) VALUES (?, ?)',
    );
    try {
      for (final entry in payloads.indexed) {
        final encoded = entry.$2 is String
            ? entry.$2 as String
            : jsonEncode(entry.$2);
        statement.execute(['conversation-${entry.$1}', encoded]);
      }
    } finally {
      statement.close();
    }
  } finally {
    database.close();
  }
}
