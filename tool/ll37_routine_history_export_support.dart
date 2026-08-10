part of 'll37_routine_history_export.dart';

final class _RoutineEvidenceRedactor {
  _RoutineEvidenceRedactor._(this._identifierReplacements);

  factory _RoutineEvidenceRedactor.fromRuns(List<Map<String, dynamic>> runs) {
    final source = jsonEncode(runs);
    final identifiers =
        _networkIdentifierPattern
            .allMatches(source)
            .map((match) => match.group(0)!)
            .toSet()
            .toList()
          ..sort();
    final replacements = <String, String>{};
    var fallbackIndex = 1;
    for (final identifier in identifiers) {
      final segments = identifier.split('.');
      final lastSegment = int.tryParse(segments.last);
      final base = lastSegment == null
          ? 'device-${(fallbackIndex++).toString().padLeft(3, '0')}'
          : 'device-${lastSegment.toString().padLeft(3, '0')}';
      final isMalformed = segments.any(
        (segment) => int.tryParse(segment) == null,
      );
      replacements[identifier] = isMalformed ? '$base-malformed' : base;
    }
    return _RoutineEvidenceRedactor._(replacements);
  }

  static final _networkIdentifierPattern = RegExp(
    r'\b[A-Za-z0-9]+(?:\.[A-Za-z0-9]+){3}\b',
  );
  static final _macAddressPattern = RegExp(
    r'\b[0-9A-Fa-f]{1,2}(?::[0-9A-Fa-f]{1,2}){5}\b',
  );

  final Map<String, String> _identifierReplacements;

  String redact(String value) {
    final withoutMacs = value.replaceAll(_macAddressPattern, '<redacted-mac>');
    return withoutMacs.replaceAllMapped(_networkIdentifierPattern, (match) {
      return _identifierReplacements[match.group(0)!] ?? '<redacted-host>';
    });
  }
}

void _validateRun(Map<String, dynamic> run, {required String label}) {
  if (_string(run['status']) != 'completed') {
    throw FormatException('$label must be recorded as completed.');
  }
  if (_string(run['trigger']) != 'scheduled') {
    throw FormatException('$label must be a scheduled unattended run.');
  }
}

Set<String> _toolNames(Map<String, dynamic> run) => _toolCalls(run)
    .map((call) => _string(call['name']) ?? '')
    .where((name) => name.isNotEmpty)
    .toSet();

List<Map<String, dynamic>> _toolCalls(Map<String, dynamic> run) =>
    _objectList(run['toolCalls'], 'routine tool calls');

int _durationMs(Map<String, dynamic> run) {
  final startedAt = DateTime.tryParse(_string(run['startedAt']) ?? '');
  final finishedAt = DateTime.tryParse(_string(run['finishedAt']) ?? '');
  if (startedAt == null || finishedAt == null) return 0;
  return finishedAt.difference(startedAt).inMilliseconds;
}

Map<String, dynamic> _findById(
  List<Map<String, dynamic>> entries,
  String id, {
  required String collectionName,
}) {
  final matches = entries.where((entry) => _string(entry['id']) == id).toList();
  if (matches.length != 1) {
    throw FormatException('Expected exactly one $collectionName with id $id.');
  }
  return matches.single;
}

final class _RoutineHistorySelection {
  const _RoutineHistorySelection({
    required this.routineId,
    required this.pairId,
    required this.correctRunId,
    required this.brokenRunId,
    required this.acceptanceCriteria,
    required this.requiredTools,
  });

  factory _RoutineHistorySelection.fromJson(
    Map<String, dynamic> json,
    String path,
  ) {
    if (_string(json['schemaName']) != _selectionSchemaName ||
        _integer(json['schemaVersion']) != _schemaVersion) {
      throw FormatException('Invalid Routine history selection in $path.');
    }
    final consent = _object(json['consent'], 'selection consent');
    if (consent['explicitUserConsent'] != true ||
        _string(consent['scope']) != 'personal_eval_case_recording') {
      throw const FormatException(
        'Explicit personal-eval recording consent is required.',
      );
    }
    final criteria = _stringList(json['acceptanceCriteria'], 'criteria');
    final requiredTools = _stringList(json['requiredTools'], 'required tools');
    if (criteria.isEmpty || requiredTools.isEmpty) {
      throw const FormatException(
        'Acceptance criteria and required tools must not be empty.',
      );
    }
    return _RoutineHistorySelection(
      routineId: _requiredString(json, 'routineId', path),
      pairId: _requiredString(json, 'pairId', path),
      correctRunId: _requiredString(json, 'correctRunId', path),
      brokenRunId: _requiredString(json, 'brokenRunId', path),
      acceptanceCriteria: criteria,
      requiredTools: requiredTools,
    );
  }

  final String routineId;
  final String pairId;
  final String correctRunId;
  final String brokenRunId;
  final List<String> acceptanceCriteria;
  final List<String> requiredTools;
}

final class _ExportCandidate {
  const _ExportCandidate({
    required this.suffix,
    required this.title,
    required this.expectedVerdict,
    required this.run,
    required this.changedFiles,
  });

  final String suffix;
  final String title;
  final String expectedVerdict;
  final Map<String, dynamic> run;
  final List<Map<String, dynamic>> changedFiles;
}

final class Ll37RoutineHistoryExportResult {
  const Ll37RoutineHistoryExportResult({
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

final class Ll37RoutineHistoryExportOptions {
  const Ll37RoutineHistoryExportOptions({
    required this.showHelp,
    this.routinesPath,
    this.selectionPath,
    this.outputDirectoryPath,
  });

  static const usage =
      'Usage: dart run tool/ll37_routine_history_export.dart '
      '--routines-json PATH --selection PATH --out-dir PATH';

  final bool showHelp;
  final String? routinesPath;
  final String? selectionPath;
  final String? outputDirectoryPath;

  static Ll37RoutineHistoryExportOptions parse(List<String> args) {
    var showHelp = false;
    String? routinesPath;
    String? selectionPath;
    String? outputDirectoryPath;
    for (var index = 0; index < args.length; index += 1) {
      final argument = args[index];
      switch (argument) {
        case '--help' || '-h':
          showHelp = true;
        case '--routines-json':
          routinesPath = _nextValue(args, ++index, argument);
        case '--selection':
          selectionPath = _nextValue(args, ++index, argument);
        case '--out-dir':
          outputDirectoryPath = _nextValue(args, ++index, argument);
        default:
          throw FormatException('Unknown Routine history option: $argument');
      }
    }
    if (!showHelp &&
        (routinesPath == null ||
            selectionPath == null ||
            outputDirectoryPath == null)) {
      throw const FormatException(
        '--routines-json, --selection, and --out-dir are required.',
      );
    }
    return Ll37RoutineHistoryExportOptions(
      showHelp: showHelp,
      routinesPath: routinesPath,
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

Map<String, dynamic> _decodeObject(String contents, String path) {
  final decoded = jsonDecode(contents);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected a JSON object in $path.');
  }
  return decoded;
}

List<Map<String, dynamic>> _decodeObjectList(String contents, String path) =>
    _objectList(jsonDecode(contents), path);

Map<String, dynamic> _object(Object? value, String path) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Expected a JSON object in $path.');
}

List<Map<String, dynamic>> _objectList(Object? value, String path) {
  if (value is! List) throw FormatException('Expected a JSON list in $path.');
  return value.map((item) => _object(item, path)).toList(growable: false);
}

List<String> _stringList(Object? value, String path) {
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('Expected a string list in $path.');
  }
  return value
      .cast<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String? _string(Object? value) => value is String ? value : null;

int? _integer(Object? value) => value is num ? value.toInt() : null;

String _requiredString(Map<String, dynamic> json, String key, String path) {
  final value = _string(json[key])?.trim() ?? '';
  if (value.isEmpty) throw FormatException('Missing `$key` in $path.');
  return value;
}
