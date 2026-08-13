part of 'll37_routine_history_export.dart';

Map<String, dynamic> _manifestJson({
  required String caseId,
  required String title,
  required Map<String, dynamic> routine,
  required Map<String, dynamic> run,
  required _MechanicalVerification mechanicalVerification,
  required String expectedVerdict,
  required DateTime generatedAt,
  required _RoutineEvidenceRedactor redactor,
}) {
  final routineId = _requiredString(routine, 'id', 'routine');
  final runId = _requiredString(run, 'id', 'routine run');
  return {
    'schemaName': _manifestSchemaName,
    'schemaVersion': _manifestSchemaVersion,
    'generatedAt': generatedAt.toIso8601String(),
    'caseId': caseId,
    'title': title,
    'readiness': 'ready',
    'split': expectedVerdict == 'refuted' ? 'heldOut' : 'heldIn',
    'task': {
      'prompt': redactor.redact(_requiredString(routine, 'prompt', 'routine')),
      'repoStateRef': 'routine-history:$routineId:$runId',
      'verificationCommand': redactor.redact(mechanicalVerification.command),
      'verificationResult': 'passed',
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
  required _MechanicalVerification mechanicalVerification,
  required _RoutineEvidenceRedactor redactor,
}) {
  return {
    'schemaName': _caseSchemaName,
    'schemaVersion': _caseSchemaVersion,
    'caseId': caseId,
    'pairId': pairId,
    'title': title,
    'sourceSurface': 'routine',
    'expectedVerdict': expectedVerdict,
    'mechanicalVerificationPassed': true,
    'personalEvalManifestPath': manifestName,
    'acceptanceCriteria': acceptanceCriteria,
    'changedFiles': changedFiles,
    'verificationEvidence': [
      {
        'command': redactor.redact(mechanicalVerification.command),
        'exitCode': mechanicalVerification.exitCode,
        'mechanicalOutput': _visibleOutput(
          redactor.redact(mechanicalVerification.output),
        ),
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
  Map<String, dynamic> routine,
  _RoutineEvidenceRedactor redactor,
) {
  final files = <Map<String, dynamic>>[];
  final seenPaths = <String>{};
  final workspaceDirectory = _requiredString(
    routine,
    'workspaceDirectory',
    'routine',
  );
  for (final call in _toolCalls(run)) {
    if (_string(call['name']) != 'write_file') continue;
    final arguments = _decodeObject(
      _requiredString(call, 'arguments', 'write_file call'),
      'write_file arguments',
    );
    final rawPath = _string(arguments['path'])?.trim() ?? '';
    final content = arguments['content'] ?? arguments['contents'];
    if (rawPath.isEmpty || content is! String) {
      throw const FormatException(
        'Captured write_file call lacks a path or string content.',
      );
    }
    final normalizedPath = _workspaceRelativePath(
      rawPath,
      workspaceDirectory: workspaceDirectory,
    );
    if (!seenPaths.add(normalizedPath)) {
      throw FormatException('Duplicate changed-file path: $normalizedPath.');
    }
    files.add({'path': normalizedPath, 'content': redactor.redact(content)});
  }
  return files;
}

String _workspaceRelativePath(
  String rawPath, {
  required String workspaceDirectory,
}) {
  final normalizedWorkspace = path.posix.normalize(
    workspaceDirectory.replaceAll('\\', '/'),
  );
  final normalizedRawPath = path.posix.normalize(rawPath.replaceAll('\\', '/'));
  final relativePath = path.posix.isAbsolute(normalizedRawPath)
      ? path.posix.relative(normalizedRawPath, from: normalizedWorkspace)
      : normalizedRawPath;
  if (path.posix.isAbsolute(relativePath) ||
      relativePath == '..' ||
      relativePath.startsWith('../') ||
      RegExp(r'^[A-Za-z]:/').hasMatch(relativePath)) {
    throw FormatException(
      'Changed-file path escapes the Routine workspace: $rawPath.',
    );
  }
  return relativePath;
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
