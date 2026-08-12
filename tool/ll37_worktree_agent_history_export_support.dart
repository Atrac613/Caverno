part of 'll37_worktree_agent_history_export.dart';

final class _WorktreeAgentEvidenceRedactor {
  _WorktreeAgentEvidenceRedactor._(this._literalReplacements);

  factory _WorktreeAgentEvidenceRedactor.fromTasks(
    List<Map<String, dynamic>> tasks,
  ) {
    final replacements = <String, String>{};
    for (final task in tasks) {
      final worktreePath = _string(task['worktreePath'])?.trim() ?? '';
      if (worktreePath.isNotEmpty) {
        replacements[worktreePath] = '<worktree-root>';
      }
    }
    return _WorktreeAgentEvidenceRedactor._(replacements);
  }

  static final _privateKeyPattern = RegExp(
    r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
    caseSensitive: false,
  );
  static final _authorizationHeaderPattern = RegExp(
    r'\b(authorization\s*[:=]\s*)(?:bearer|basic)\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final _bearerTokenPattern = RegExp(
    r'\bbearer\s+[A-Za-z0-9._~+/=-]{8,}',
    caseSensitive: false,
  );
  static final _openAiStyleKeyPattern = RegExp(r'\bsk-[A-Za-z0-9_-]{16,}\b');
  static final _githubTokenPattern = RegExp(
    r'\b(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,})\b',
  );
  static final _jwtPattern = RegExp(
    r'\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b',
  );
  static final _urlCredentialPattern = RegExp(
    r'\b(https?://)[^:\s/@]+:[^@\s]+@',
    caseSensitive: false,
  );
  static final _sensitiveQueryParamPattern = RegExp(
    r'([?&](?:access_token|refresh_token|id_token|api_key|apikey|token|secret|password|auth|authorization|key)=)[^&#\s]+',
    caseSensitive: false,
  );
  static final _envSecretLinePattern = RegExp(
    r'^(\s*(?:[A-Z][A-Z0-9_]*(?:TOKEN|SECRET|KEY|PASSWORD|PASS|PWD|AUTH)[A-Z0-9_]*|(?:TOKEN|SECRET|KEY|PASSWORD|PASS|PWD|AUTH))\s*=\s*)(.+)$',
    multiLine: true,
  );
  static final _macAddressPattern = RegExp(
    r'\b[0-9A-Fa-f]{1,2}(?::[0-9A-Fa-f]{1,2}){5}\b',
  );
  static final _networkIdentifierPattern = RegExp(
    r'\b(?:\d{1,3}\.){3}\d{1,3}\b',
  );

  final Map<String, String> _literalReplacements;

  String redact(String value) {
    var redacted = value;
    for (final entry in _literalReplacements.entries) {
      redacted = redacted.replaceAll(entry.key, entry.value);
    }
    redacted = redacted.replaceAll(
      _privateKeyPattern,
      '[redacted-private-key]',
    );
    redacted = redacted.replaceAllMapped(
      _authorizationHeaderPattern,
      (match) => '${match.group(1)}[redacted]',
    );
    redacted = redacted.replaceAllMapped(
      _bearerTokenPattern,
      (match) => '${match.group(0)!.split(RegExp(r'\s+')).first} [redacted]',
    );
    redacted = redacted.replaceAll(_openAiStyleKeyPattern, 'sk-[redacted]');
    redacted = redacted.replaceAll(
      _githubTokenPattern,
      '[redacted-github-token]',
    );
    redacted = redacted.replaceAll(_jwtPattern, '[redacted-jwt]');
    redacted = redacted.replaceAllMapped(
      _urlCredentialPattern,
      (match) => '${match.group(1)}[redacted]@',
    );
    redacted = redacted.replaceAllMapped(
      _sensitiveQueryParamPattern,
      (match) => '${match.group(1)}[redacted]',
    );
    redacted = redacted.replaceAllMapped(
      _envSecretLinePattern,
      (match) => '${match.group(1)}[redacted]',
    );
    redacted = redacted.replaceAll(_macAddressPattern, '<redacted-mac>');
    return redacted.replaceAll(_networkIdentifierPattern, '<redacted-host>');
  }
}

void _validateTask(Map<String, dynamic> task, {required String label}) {
  if (_string(task['status']) != 'completed') {
    throw FormatException('$label must be recorded as completed.');
  }
  if (task['verifiedGreen'] != true) {
    throw FormatException('$label must have verifiedGreen set to true.');
  }
  if (task['changedFileEvidenceTruncated'] == true) {
    throw FormatException('$label contains truncated changed-file evidence.');
  }
  _requiredString(task, 'id', label);
  _requiredString(task, 'prompt', label);
  _requiredString(task, 'verificationCommand', label);
  _requiredString(task, 'verificationSummary', label);
}

Map<String, dynamic> _findById(List<Map<String, dynamic>> tasks, String id) {
  final matches = tasks.where((task) => _string(task['id']) == id).toList();
  if (matches.length != 1) {
    throw FormatException(
      'Expected exactly one worktree-agent task with id $id.',
    );
  }
  return matches.single;
}

List<Map<String, dynamic>> _validatedChangedFiles(
  Map<String, dynamic> task,
  _WorktreeAgentEvidenceRedactor redactor,
) {
  final files = _objectList(task['changedFiles'], 'changed files');
  final seenPaths = <String>{};
  return files
      .map((file) {
        final rawPath = _requiredString(file, 'path', 'changed file');
        final normalizedPath = path.posix.normalize(
          rawPath.replaceAll('\\', '/'),
        );
        if (path.posix.isAbsolute(normalizedPath) ||
            normalizedPath == '..' ||
            normalizedPath.startsWith('../') ||
            RegExp(r'^[A-Za-z]:/').hasMatch(normalizedPath)) {
          throw FormatException('Unsafe changed-file path: $rawPath.');
        }
        if (!seenPaths.add(normalizedPath)) {
          throw FormatException(
            'Duplicate changed-file path: $normalizedPath.',
          );
        }

        final deleted = file['deleted'] == true;
        final truncated = file['truncated'] == true;
        if (truncated) {
          throw FormatException(
            'Changed-file evidence is truncated: $normalizedPath.',
          );
        }
        final content = _string(file['content']) ?? '';
        final byteSize = _integer(file['byteSize']) ?? -1;
        final contentHash = _string(file['contentHash'])?.trim() ?? '';
        if (deleted) {
          if (content.isNotEmpty || byteSize != 0 || contentHash.isNotEmpty) {
            throw FormatException(
              'Deleted changed-file evidence must not contain content: '
              '$normalizedPath.',
            );
          }
          return <String, dynamic>{
            'path': normalizedPath,
            'content': '',
            'byteSize': 0,
            'deleted': true,
          };
        }

        final sourceBytes = utf8.encode(content);
        final calculatedHash = sha256.convert(sourceBytes).toString();
        if (byteSize != sourceBytes.length || contentHash != calculatedHash) {
          throw FormatException(
            'Changed-file evidence hash or byte size does not match: '
            '$normalizedPath.',
          );
        }
        final redactedContent = redactor.redact(content);
        final redactedBytes = utf8.encode(redactedContent);
        final redactedHash = sha256.convert(redactedBytes).toString();
        return <String, dynamic>{
          'path': normalizedPath,
          'content': redactedContent,
          'contentHash': redactedHash,
          'byteSize': redactedBytes.length,
          'deleted': false,
          if (redactedHash != contentHash) 'sourceContentHash': contentHash,
          if (redactedHash != contentHash) 'redacted': true,
        };
      })
      .toList(growable: false);
}

int _durationMs(Map<String, dynamic> task) {
  final startedAt = DateTime.tryParse(_string(task['startedAt']) ?? '');
  final finishedAt = DateTime.tryParse(_string(task['finishedAt']) ?? '');
  if (startedAt == null || finishedAt == null) return 0;
  return finishedAt.difference(startedAt).inMilliseconds;
}

String _visibleText(String value, _WorktreeAgentEvidenceRedactor redactor) {
  final withoutThinking = value.replaceAll(
    RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
    '',
  );
  final normalized = redactor.redact(withoutThinking).trim();
  return normalized.length <= 4000 ? normalized : normalized.substring(0, 4000);
}

final class _WorktreeAgentHistorySelection {
  const _WorktreeAgentHistorySelection({
    required this.pairId,
    required this.correctTaskId,
    required this.brokenTaskId,
    required this.acceptanceCriteria,
    required this.evidenceClass,
    required this.correctCaptureProvenance,
    required this.brokenCaptureProvenance,
  });

  factory _WorktreeAgentHistorySelection.fromJson(
    Map<String, dynamic> json,
    String sourcePath,
  ) {
    if (_string(json['schemaName']) != _selectionSchemaName ||
        _integer(json['schemaVersion']) != _selectionSchemaVersion) {
      throw FormatException(
        'Invalid worktree-agent history selection in $sourcePath.',
      );
    }
    final consent = _object(json['consent'], 'selection consent');
    if (consent['explicitUserConsent'] != true ||
        _string(consent['scope']) != 'personal_eval_case_recording') {
      throw const FormatException(
        'Explicit personal-eval recording consent is required.',
      );
    }
    final criteria = _stringList(json['acceptanceCriteria'], 'criteria');
    if (criteria.isEmpty) {
      throw const FormatException('Acceptance criteria must not be empty.');
    }
    final evidenceClass = _requiredString(json, 'evidenceClass', sourcePath);
    if (evidenceClass != 'organic' &&
        evidenceClass != 'controlled_live_canary') {
      throw FormatException(
        'Unsupported worktree-agent evidence class: $evidenceClass.',
      );
    }
    return _WorktreeAgentHistorySelection(
      pairId: _requiredString(json, 'pairId', sourcePath),
      correctTaskId: _requiredString(json, 'correctTaskId', sourcePath),
      brokenTaskId: _requiredString(json, 'brokenTaskId', sourcePath),
      acceptanceCriteria: criteria,
      evidenceClass: evidenceClass,
      correctCaptureProvenance: _requiredString(
        json,
        'correctCaptureProvenance',
        sourcePath,
      ),
      brokenCaptureProvenance: _requiredString(
        json,
        'brokenCaptureProvenance',
        sourcePath,
      ),
    );
  }

  final String pairId;
  final String correctTaskId;
  final String brokenTaskId;
  final List<String> acceptanceCriteria;
  final String evidenceClass;
  final String correctCaptureProvenance;
  final String brokenCaptureProvenance;
}

final class _ExportCandidate {
  const _ExportCandidate({
    required this.suffix,
    required this.title,
    required this.expectedVerdict,
    required this.captureProvenance,
    required this.task,
    required this.changedFiles,
  });

  final String suffix;
  final String title;
  final String expectedVerdict;
  final String captureProvenance;
  final Map<String, dynamic> task;
  final List<Map<String, dynamic>> changedFiles;
}

final class Ll37WorktreeAgentHistoryExportResult {
  const Ll37WorktreeAgentHistoryExportResult({
    required this.pairId,
    required this.sourceSurface,
    required this.casePaths,
  });

  final String pairId;
  final String sourceSurface;
  final List<String> casePaths;

  Map<String, dynamic> toJson() => {
    'pairId': pairId,
    'sourceSurface': sourceSurface,
    'casePaths': casePaths,
  };
}

final class Ll37WorktreeAgentHistoryExportOptions {
  const Ll37WorktreeAgentHistoryExportOptions({
    required this.showHelp,
    this.tasksPath,
    this.selectionPath,
    this.outputDirectoryPath,
  });

  static const usage =
      'Usage: dart run tool/ll37_worktree_agent_history_export.dart '
      '--tasks-json PATH --selection PATH --out-dir PATH';

  final bool showHelp;
  final String? tasksPath;
  final String? selectionPath;
  final String? outputDirectoryPath;

  static Ll37WorktreeAgentHistoryExportOptions parse(List<String> args) {
    var showHelp = false;
    String? tasksPath;
    String? selectionPath;
    String? outputDirectoryPath;
    for (var index = 0; index < args.length; index += 1) {
      final argument = args[index];
      switch (argument) {
        case '--help' || '-h':
          showHelp = true;
        case '--tasks-json':
          tasksPath = _nextValue(args, ++index, argument);
        case '--selection':
          selectionPath = _nextValue(args, ++index, argument);
        case '--out-dir':
          outputDirectoryPath = _nextValue(args, ++index, argument);
        default:
          throw FormatException(
            'Unknown worktree-agent history option: $argument',
          );
      }
    }
    if (!showHelp &&
        (tasksPath == null ||
            selectionPath == null ||
            outputDirectoryPath == null)) {
      throw const FormatException(
        '--tasks-json, --selection, and --out-dir are required.',
      );
    }
    return Ll37WorktreeAgentHistoryExportOptions(
      showHelp: showHelp,
      tasksPath: tasksPath,
      selectionPath: selectionPath,
      outputDirectoryPath: outputDirectoryPath,
    );
  }
}

String _nextValue(List<String> args, int index, String option) {
  if (index >= args.length || args[index].startsWith('--')) {
    throw FormatException('Missing value for $option.');
  }
  return args[index];
}

Map<String, dynamic> _decodeObject(String contents, String sourcePath) {
  final decoded = jsonDecode(contents);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected a JSON object in $sourcePath.');
  }
  return decoded;
}

List<Map<String, dynamic>> _decodeObjectList(
  String contents,
  String sourcePath,
) => _objectList(jsonDecode(contents), sourcePath);

Map<String, dynamic> _object(Object? value, String sourcePath) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Expected a JSON object in $sourcePath.');
}

List<Map<String, dynamic>> _objectList(Object? value, String sourcePath) {
  if (value is! List) {
    throw FormatException('Expected a JSON list in $sourcePath.');
  }
  return value.map((item) => _object(item, sourcePath)).toList(growable: false);
}

List<String> _stringList(Object? value, String sourcePath) {
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('Expected a string list in $sourcePath.');
  }
  return value
      .cast<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String? _string(Object? value) => value is String ? value : null;

int? _integer(Object? value) => value is num ? value.toInt() : null;

String _requiredString(
  Map<String, dynamic> json,
  String key,
  String sourcePath,
) {
  final value = _string(json[key])?.trim() ?? '';
  if (value.isEmpty) throw FormatException('Missing `$key` in $sourcePath.');
  return value;
}
