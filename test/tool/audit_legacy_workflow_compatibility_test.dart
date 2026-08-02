import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_legacy_workflow_compatibility_service.dart';

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
    });
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

  test('reports migration readiness only for compatible legacy candidates', () {
    final report = audit.buildLegacyWorkflowCompatibilityReport([
      jsonEncode(_conversation().toJson()),
    ]);

    expect(report['decision'], {
      'migrationCandidateReady': true,
      'nextAction': 'design_candidate_transformer',
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

Conversation _conversation({
  String id = 'compatible-legacy',
  ConversationWorkflowStage workflowStage = ConversationWorkflowStage.implement,
  ConversationWorkflowSpec workflowSpec = _workflowSpec,
  String workflowSourceHash = '',
  DateTime? workflowDerivedAt,
  List<ConversationExecutionTaskProgress> executionProgress = const [],
  List<ConversationOpenQuestionProgress> openQuestionProgress = const [],
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
