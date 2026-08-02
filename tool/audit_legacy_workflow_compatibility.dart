import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_legacy_workflow_compatibility_service.dart';

const String auditSchemaName = 'caverno_legacy_workflow_compatibility_audit';
const int auditSchemaVersion = 1;

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
    'privacy': {
      'includesDatabasePath': false,
      'includesRecordIdentifiers': false,
      'includesRecordContent': false,
      'includesIndividualResults': false,
    },
  };
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
