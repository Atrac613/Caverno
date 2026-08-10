part of 'll37_routine_history_export.dart';

Map<String, dynamic> _manifestJson({
  required String caseId,
  required String title,
  required Map<String, dynamic> routine,
  required Map<String, dynamic> run,
  required String expectedVerdict,
  required DateTime generatedAt,
  required _RoutineEvidenceRedactor redactor,
}) {
  final routineId = _requiredString(routine, 'id', 'routine');
  final runId = _requiredString(run, 'id', 'routine run');
  return {
    'schemaName': _manifestSchemaName,
    'schemaVersion': _schemaVersion,
    'generatedAt': generatedAt.toIso8601String(),
    'caseId': caseId,
    'title': title,
    'readiness': 'ready',
    'split': expectedVerdict == 'refuted' ? 'heldOut' : 'heldIn',
    'task': {
      'prompt': redactor.redact(_requiredString(routine, 'prompt', 'routine')),
      'repoStateRef': 'routine-history:$routineId:$runId',
      'verificationCommand': 'routine_history_objective_audit',
      'verificationResult': expectedVerdict == 'refuted' ? 'failed' : 'passed',
      'workspaceMode': 'routines',
    },
    'source': {
      'sessionLogPath': 'routine-history:$routineId:$runId',
      'sessionLogSummary': {
        'result': 'completed',
        'turnCount': 1,
        'toolCallCount': _toolCalls(run).length,
        'totalDurationMs': _durationMs(run),
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
      'anonymization': 'network_identifiers',
      'exportPolicy': 'excluded_by_default',
    },
  };
}

Map<String, dynamic> _caseJson({
  required String caseId,
  required String pairId,
  required String title,
  required String expectedVerdict,
  required String manifestName,
  required List<String> acceptanceCriteria,
  required List<Map<String, dynamic>> changedFiles,
  required Map<String, dynamic> run,
  required _RoutineEvidenceRedactor redactor,
}) {
  return {
    'schemaName': _caseSchemaName,
    'schemaVersion': _schemaVersion,
    'caseId': caseId,
    'pairId': pairId,
    'title': title,
    'sourceSurface': 'routine',
    'expectedVerdict': expectedVerdict,
    'personalEvalManifestPath': manifestName,
    'acceptanceCriteria': acceptanceCriteria,
    'changedFiles': changedFiles,
    'verificationEvidence': [
      {
        'command': 'routine_history_objective_audit',
        'exitCode': 0,
        'recordedStatus': _requiredString(run, 'status', 'routine run'),
        'trigger': _requiredString(run, 'trigger', 'routine run'),
        'toolCalls': _toolCalls(
          run,
        ).map((call) => _promptToolCall(call, redactor)).toList(),
        'finalOutput': _visibleOutput(
          redactor.redact(_string(run['output']) ?? ''),
        ),
        'recordedError': redactor.redact(_string(run['error']) ?? ''),
      },
    ],
  };
}

Map<String, dynamic> _promptToolCall(
  Map<String, dynamic> call,
  _RoutineEvidenceRedactor redactor,
) => {
  'name': _requiredString(call, 'name', 'routine tool call'),
  'arguments': redactor.redact(_string(call['arguments']) ?? ''),
  'result': redactor.redact(_string(call['result']) ?? ''),
};

List<Map<String, dynamic>> _changedFiles(
  Map<String, dynamic> run,
  _RoutineEvidenceRedactor redactor,
) {
  final files = <Map<String, dynamic>>[];
  for (final call in _toolCalls(run)) {
    if (_string(call['name']) != 'write_file') continue;
    final arguments = _decodeObject(
      _requiredString(call, 'arguments', 'write_file call'),
      'write_file arguments',
    );
    final path = _string(arguments['path'])?.trim() ?? '';
    final content = arguments['content'] ?? arguments['contents'];
    if (path.isEmpty || content is! String) {
      throw const FormatException(
        'Captured write_file call lacks a path or string content.',
      );
    }
    files.add({'path': path, 'content': redactor.redact(content)});
  }
  return files;
}

String _visibleOutput(String output) {
  final withoutThinking = output.replaceAll(
    RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
    '',
  );
  final normalized = withoutThinking.trim();
  return normalized.length <= 4000 ? normalized : normalized.substring(0, 4000);
}

Future<void> _writeJson(File file, Map<String, dynamic> json) async {
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
}
