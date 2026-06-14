import 'dart:convert';
import 'dart:io';

import 'caverno_session_log_summary.dart';
import 'personal_eval_case_manifest.dart';

const _schemaName = 'caverno_personal_eval_replay_run';
const _schemaVersion = 1;
const _manifestSchemaName = 'caverno_personal_eval_case_manifest';

Future<void> main(List<String> args) async {
  final options = PersonalEvalReplayRunOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/personal_eval_replay_run.dart '
      '--label LABEL --manifest PATH [--manifest PATH ...] '
      '--case-log CASE_ID=PATH '
      '--verification-result CASE_ID=passed|failed|inconclusive '
      '--out PATH [--model MODEL] [--base-url URL]',
    );
    exitCode = 64;
    return;
  }

  final PersonalEvalReplayRunArtifact run;
  try {
    run = await buildPersonalEvalReplayRun(
      label: options.label,
      manifestFiles: options.manifestPaths.map(File.new).toList(),
      caseLogFiles: options.caseLogPaths.map(
        (caseId, path) => MapEntry(caseId, File(path)),
      ),
      verificationResults: options.verificationResults,
      model: options.model,
      baseUrl: options.baseUrl,
    );
  } on FileSystemException catch (error) {
    stderr.writeln(error.message);
    if (error.path != null) {
      stderr.writeln(error.path);
    }
    exitCode = 66;
    return;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 65;
    return;
  }

  final outputFile = File(options.outPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(run.toJson())}\n',
  );

  stdout.writeln('Personal eval replay run written to ${outputFile.path}');
  stdout.writeln(run.toMarkdown());
}

Future<PersonalEvalReplayRunArtifact> buildPersonalEvalReplayRun({
  required String label,
  required List<File> manifestFiles,
  required Map<String, File> caseLogFiles,
  required Map<String, PersonalEvalVerificationResult> verificationResults,
  String? model,
  String? baseUrl,
  DateTime? generatedAt,
}) async {
  final normalizedLabel = label.trim();
  if (normalizedLabel.isEmpty) {
    throw const FormatException('Replay run label must not be empty.');
  }
  if (manifestFiles.isEmpty) {
    throw const FormatException('At least one eval case manifest is required.');
  }

  final manifests = <PersonalEvalReplayCaseManifest>[];
  final seenCaseIds = <String>{};
  for (final file in manifestFiles) {
    final manifest = PersonalEvalReplayCaseManifest.fromJson(
      await _readJsonObject(file),
      path: file.path,
    );
    if (!seenCaseIds.add(manifest.caseId)) {
      throw FormatException('Duplicate eval case id: ${manifest.caseId}');
    }
    manifests.add(manifest);
  }

  _validateCaseMap(
    mapName: 'case log',
    knownCaseIds: seenCaseIds,
    values: caseLogFiles,
  );
  _validateCaseMap(
    mapName: 'verification result',
    knownCaseIds: seenCaseIds,
    values: verificationResults,
  );

  final cases = <PersonalEvalReplayCaseArtifact>[];
  for (final manifest in manifests) {
    if (manifest.readiness == PersonalEvalCaseReadiness.blocked.jsonValue) {
      throw FormatException(
        'Blocked eval case cannot be replayed: ${manifest.caseId}',
      );
    }
    final logFile = caseLogFiles[manifest.caseId];
    if (logFile == null) {
      throw FormatException('Missing replay log for case ${manifest.caseId}.');
    }
    if (!logFile.existsSync()) {
      throw FileSystemException('Replay log file not found.', logFile.path);
    }
    final verificationResult = verificationResults[manifest.caseId];
    if (verificationResult == null) {
      throw FormatException(
        'Missing verification result for case ${manifest.caseId}.',
      );
    }

    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);
    cases.add(
      PersonalEvalReplayCaseArtifact.fromSummary(
        manifest: manifest,
        logFile: logFile,
        verificationResult: verificationResult,
        summary: summary,
      ),
    );
  }

  return PersonalEvalReplayRunArtifact(
    schemaName: _schemaName,
    schemaVersion: _schemaVersion,
    generatedAt: generatedAt ?? DateTime.now(),
    label: normalizedLabel,
    model: _trimToNull(model),
    baseUrl: _trimToNull(baseUrl),
    manifestPaths: manifestFiles.map((file) => file.path).toList(),
    cases: List.unmodifiable(cases),
  );
}

void _validateCaseMap<T>({
  required String mapName,
  required Set<String> knownCaseIds,
  required Map<String, T> values,
}) {
  for (final caseId in values.keys) {
    if (!knownCaseIds.contains(caseId)) {
      throw FormatException('Unknown $mapName case id: $caseId');
    }
  }
}

final class PersonalEvalReplayRunOptions {
  const PersonalEvalReplayRunOptions({
    required this.label,
    required this.manifestPaths,
    required this.caseLogPaths,
    required this.verificationResults,
    required this.outPath,
    this.model,
    this.baseUrl,
  });

  final String label;
  final List<String> manifestPaths;
  final Map<String, String> caseLogPaths;
  final Map<String, PersonalEvalVerificationResult> verificationResults;
  final String outPath;
  final String? model;
  final String? baseUrl;

  static PersonalEvalReplayRunOptions? parse(List<String> args) {
    String? label;
    final manifests = <String>[];
    final caseLogs = <String, String>{};
    final verificationResults = <String, PersonalEvalVerificationResult>{};
    String? outPath;
    String? model;
    String? baseUrl;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--label':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          label = value;
        case '--manifest':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          manifests.add(value);
        case '--case-log':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          final parsed = _parseKeyValue(value);
          if (parsed == null) return null;
          caseLogs[parsed.key] = parsed.value;
        case '--verification-result':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          final parsed = _parseKeyValue(value);
          if (parsed == null) return null;
          final result = PersonalEvalVerificationResult.parse(parsed.value);
          if (result == null) return null;
          verificationResults[parsed.key] = result;
        case '--out':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          outPath = value;
        case '--model':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          model = value;
        case '--base-url':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          baseUrl = value;
        default:
          return null;
      }
    }

    if (label == null ||
        manifests.isEmpty ||
        caseLogs.isEmpty ||
        verificationResults.isEmpty ||
        outPath == null) {
      return null;
    }

    return PersonalEvalReplayRunOptions(
      label: label,
      manifestPaths: List.unmodifiable(manifests),
      caseLogPaths: Map.unmodifiable(caseLogs),
      verificationResults: Map.unmodifiable(verificationResults),
      outPath: outPath,
      model: model,
      baseUrl: baseUrl,
    );
  }

  static String? _nextValue(List<String> args, int index) {
    if (index >= args.length) {
      return null;
    }
    final value = args[index];
    return value.startsWith('--') ? null : value;
  }
}

final class PersonalEvalReplayRunArtifact {
  const PersonalEvalReplayRunArtifact({
    required this.schemaName,
    required this.schemaVersion,
    required this.generatedAt,
    required this.label,
    required this.model,
    required this.baseUrl,
    required this.manifestPaths,
    required this.cases,
  });

  final String schemaName;
  final int schemaVersion;
  final DateTime generatedAt;
  final String label;
  final String? model;
  final String? baseUrl;
  final List<String> manifestPaths;
  final List<PersonalEvalReplayCaseArtifact> cases;

  bool get isSuccessful => failedCount == 0 && inconclusiveCount == 0;

  int get passedCount => cases
      .where(
        (entry) =>
            entry.verificationResult == PersonalEvalVerificationResult.passed,
      )
      .length;

  int get failedCount => cases
      .where(
        (entry) =>
            entry.verificationResult == PersonalEvalVerificationResult.failed,
      )
      .length;

  int get inconclusiveCount => cases
      .where(
        (entry) =>
            entry.verificationResult ==
            PersonalEvalVerificationResult.inconclusive,
      )
      .length;

  int get totalDurationMs =>
      cases.fold(0, (total, entry) => total + entry.durationMs);

  int get totalToolCallCount =>
      cases.fold(0, (total, entry) => total + entry.toolCallCount);

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'label': label,
      if (model != null) 'model': model,
      if (baseUrl != null) 'baseUrl': baseUrl,
      'manifestPaths': manifestPaths,
      'caseCount': cases.length,
      'passedCount': passedCount,
      'failedCount': failedCount,
      'inconclusiveCount': inconclusiveCount,
      'totalDurationMs': totalDurationMs,
      'totalToolCallCount': totalToolCallCount,
      'cases': cases.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Personal Eval Replay Run')
      ..writeln()
      ..writeln('- Label: `$label`')
      ..writeln('- Cases: `${cases.length}`')
      ..writeln('- Passed: `$passedCount`')
      ..writeln('- Failed: `$failedCount`')
      ..writeln('- Inconclusive: `$inconclusiveCount`')
      ..writeln('- Duration: `$totalDurationMs ms`')
      ..writeln('- Tool calls: `$totalToolCallCount`')
      ..writeln()
      ..writeln('| Case | Result | Duration | Tool Calls | Turns | Summary |')
      ..writeln('|------|--------|----------|------------|-------|---------|');

    for (final entry in cases) {
      buffer.writeln(
        '| ${_markdownCell(entry.caseId)} '
        '| `${entry.verificationResult.name}` '
        '| `${entry.durationMs} ms` '
        '| `${entry.toolCallCount}` '
        '| `${entry.turnCount}` '
        '| ${_markdownCell(entry.summaryResult)} |',
      );
    }
    return buffer.toString();
  }
}

final class PersonalEvalReplayCaseArtifact {
  const PersonalEvalReplayCaseArtifact({
    required this.caseId,
    required this.title,
    required this.logPath,
    required this.verificationResult,
    required this.durationMs,
    required this.toolCallCount,
    required this.turnCount,
    required this.summaryResult,
    required this.warningCodes,
    required this.error,
  });

  final String caseId;
  final String title;
  final String logPath;
  final PersonalEvalVerificationResult verificationResult;
  final int durationMs;
  final int toolCallCount;
  final int turnCount;
  final String summaryResult;
  final List<String> warningCodes;
  final String? error;

  factory PersonalEvalReplayCaseArtifact.fromSummary({
    required PersonalEvalReplayCaseManifest manifest,
    required File logFile,
    required PersonalEvalVerificationResult verificationResult,
    required CavernoLlmSessionLogSummary summary,
  }) {
    return PersonalEvalReplayCaseArtifact(
      caseId: manifest.caseId,
      title: manifest.title,
      logPath: logFile.path,
      verificationResult: verificationResult,
      durationMs: _totalDurationMs(summary),
      toolCallCount: summary.toolCallCount,
      turnCount: _turnCount(summary),
      summaryResult: summary.result,
      warningCodes: List.unmodifiable(
        summary.warnings.map((warning) => warning.code),
      ),
      error: _summaryError(summary),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'caseId': caseId,
      'title': title,
      'logPath': logPath,
      'verificationResult': verificationResult.name,
      'durationMs': durationMs,
      'toolCallCount': toolCallCount,
      'turnCount': turnCount,
      'summaryResult': summaryResult,
      'warningCodes': warningCodes,
      if (error != null) 'error': error,
    };
  }
}

final class PersonalEvalReplayCaseManifest {
  const PersonalEvalReplayCaseManifest({
    required this.path,
    required this.caseId,
    required this.title,
    required this.readiness,
    required this.expectedVerificationResult,
  });

  final String path;
  final String caseId;
  final String title;
  final String readiness;
  final PersonalEvalVerificationResult expectedVerificationResult;

  factory PersonalEvalReplayCaseManifest.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final schemaName = _asString(json['schemaName']);
    if (schemaName != _manifestSchemaName) {
      throw FormatException('Invalid personal eval manifest schema in $path.');
    }
    final task = _asStringMap(json['task']);
    final verificationResult = PersonalEvalVerificationResult.parse(
      _asString(task?['verificationResult']) ?? '',
    );
    if (task == null || verificationResult == null) {
      throw FormatException('Incomplete personal eval manifest in $path.');
    }
    return PersonalEvalReplayCaseManifest(
      path: path,
      caseId: _requiredString(json, 'caseId', path),
      title: _requiredString(json, 'title', path),
      readiness: _asString(json['readiness']) ?? 'unknown',
      expectedVerificationResult: verificationResult,
    );
  }
}

int _totalDurationMs(CavernoLlmSessionLogSummary summary) {
  return summary.entries.fold(
    0,
    (total, entry) => total + (entry.durationMs ?? 0),
  );
}

int _turnCount(CavernoLlmSessionLogSummary summary) {
  return summary.entries
      .where((entry) => !entry.isMemoryExtraction && !entry.isAutoReview)
      .length;
}

String? _summaryError(CavernoLlmSessionLogSummary summary) {
  if (summary.errorEntries.isNotEmpty) {
    return summary.errorEntries.first.message;
  }
  if (summary.finalAnswer == null) {
    return 'Session summary result: ${summary.result}';
  }
  return null;
}

Future<Map<String, dynamic>> _readJsonObject(File file) async {
  final decoded = jsonDecode(await file.readAsString());
  final object = _asStringMap(decoded);
  if (object == null) {
    throw FormatException('Expected a JSON object in ${file.path}.');
  }
  return object;
}

MapEntry<String, String>? _parseKeyValue(String value) {
  final separator = value.indexOf('=');
  if (separator <= 0 || separator == value.length - 1) {
    return null;
  }
  final key = value.substring(0, separator).trim();
  final parsedValue = value.substring(separator + 1).trim();
  if (key.isEmpty || parsedValue.isEmpty) {
    return null;
  }
  return MapEntry(key, parsedValue);
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is Map) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  return null;
}

String? _asString(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

String _requiredString(Map<String, dynamic> json, String key, String path) {
  final value = _asString(json[key])?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('Missing `$key` in $path.');
  }
  return value;
}

String? _trimToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _markdownCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}
