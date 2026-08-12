part of 'll37_worktree_agent_history_export.dart';

Map<String, dynamic> _manifestJson({
  required String caseId,
  required String title,
  required Map<String, dynamic> task,
  required String expectedVerdict,
  required String evidenceClass,
  required String captureProvenance,
  required DateTime generatedAt,
  required _WorktreeAgentEvidenceRedactor redactor,
}) {
  final taskId = _requiredString(task, 'id', 'worktree-agent task');
  return {
    'schemaName': _manifestSchemaName,
    'schemaVersion': _manifestSchemaVersion,
    'generatedAt': generatedAt.toIso8601String(),
    'caseId': caseId,
    'title': title,
    'readiness': 'ready',
    'split': expectedVerdict == 'refuted' ? 'heldOut' : 'heldIn',
    'task': {
      'prompt': redactor.redact(
        _requiredString(task, 'prompt', 'worktree-agent task'),
      ),
      'repoStateRef': 'worktree-agent-history:$taskId',
      'verificationCommand': redactor.redact(
        _requiredString(task, 'verificationCommand', 'worktree-agent task'),
      ),
      'verificationResult': 'passed',
      'workspaceMode': 'coding',
    },
    'source': {
      'sessionLogPath': 'worktree-agent-history:$taskId',
      'evidenceClass': evidenceClass,
      'captureProvenance': redactor.redact(captureProvenance),
      'sessionLogSummary': {
        'result': 'completed',
        'turnCount': 1,
        'toolCallCount': _objectList(
          task['changedFiles'],
          'changed files',
        ).length,
        'totalDurationMs': _durationMs(task),
        'warningCodes': <String>[],
      },
    },
    'consent': {
      'explicitUserConsent': true,
      'recordedAt': generatedAt.toIso8601String(),
      'scope': 'personal_eval_case_recording',
    },
    'privacy': const {
      'localOnly': true,
      'anonymization': 'secrets_network_identifiers_and_worktree_paths',
      'exportPolicy': 'excluded_by_default',
    },
  };
}

Map<String, dynamic> _caseJson({
  required String caseId,
  required String pairId,
  required String title,
  required String expectedVerdict,
  required String evidenceClass,
  required String captureProvenance,
  required String manifestName,
  required List<String> acceptanceCriteria,
  required List<Map<String, dynamic>> changedFiles,
  required Map<String, dynamic> task,
  required _WorktreeAgentEvidenceRedactor redactor,
}) {
  return {
    'schemaName': _caseSchemaName,
    'schemaVersion': _caseSchemaVersion,
    'caseId': caseId,
    'pairId': pairId,
    'title': title,
    'sourceSurface': 'worktree_agent',
    'expectedVerdict': expectedVerdict,
    'mechanicalVerificationPassed': true,
    'personalEvalManifestPath': manifestName,
    'acceptanceCriteria': acceptanceCriteria,
    'changedFiles': changedFiles,
    'verificationEvidence': [
      {
        'command': redactor.redact(
          _requiredString(task, 'verificationCommand', 'worktree-agent task'),
        ),
        'recordedVerifiedGreen': task['verifiedGreen'] == true,
        'evidenceClass': evidenceClass,
        'captureProvenance': redactor.redact(captureProvenance),
        'summary': _visibleText(
          _requiredString(task, 'verificationSummary', 'worktree-agent task'),
          redactor,
        ),
        'implementerSummary': _visibleText(
          _string(task['resultSummary']) ?? '',
          redactor,
        ),
      },
    ],
  };
}

Future<void> _writeJson(File file, Map<String, dynamic> json) async {
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
}
