import 'dart:convert';
import 'dart:io';

import 'caverno_session_log_summary.dart';
import 'personal_eval_case_manifest.dart';

const _schemaName = 'caverno_personal_eval_replay_run';
const _schemaVersion = 5;
const _manifestSchemaName = 'caverno_personal_eval_case_manifest';
const _defaultTrialId = 'trial-1';

Future<void> main(List<String> args) async {
  final options = PersonalEvalReplayRunOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/personal_eval_replay_run.dart '
      '--label LABEL --manifest PATH [--manifest PATH ...] '
      '--case-log CASE_ID[#TRIAL_ID]=PATH '
      '--verification-result CASE_ID[#TRIAL_ID]='
      'passed|failed|inconclusive '
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

  final trialInputs = _buildTrialInputs(
    knownCaseIds: seenCaseIds,
    caseLogFiles: caseLogFiles,
    verificationResults: verificationResults,
  );
  final manifestByCaseId = {
    for (final manifest in manifests) manifest.caseId: manifest,
  };
  final observedCaseIds = trialInputs.map((input) => input.key.caseId).toSet();

  final cases = <PersonalEvalReplayCaseArtifact>[];
  for (final manifest in manifests) {
    if (manifest.readiness == PersonalEvalCaseReadiness.blocked.jsonValue) {
      throw FormatException(
        'Blocked eval case cannot be replayed: ${manifest.caseId}',
      );
    }
    if (!observedCaseIds.contains(manifest.caseId)) {
      throw FormatException('Missing replay log for case ${manifest.caseId}.');
    }
  }

  for (var index = 0; index < trialInputs.length; index += 1) {
    final input = trialInputs[index];
    final manifest = manifestByCaseId[input.key.caseId]!;
    final logFile = input.logFile;
    if (!logFile.existsSync()) {
      throw FileSystemException('Replay log file not found.', logFile.path);
    }
    final summary = await buildCavernoLlmSessionLogSummary(logFile: logFile);
    cases.add(
      PersonalEvalReplayCaseArtifact.fromSummary(
        manifest: manifest,
        logFile: logFile,
        trialId: input.key.trialId,
        executionOrder: index + 1,
        verificationResult: input.verificationResult,
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

List<_PersonalEvalReplayTrialInput> _buildTrialInputs({
  required Set<String> knownCaseIds,
  required Map<String, File> caseLogFiles,
  required Map<String, PersonalEvalVerificationResult> verificationResults,
}) {
  final logsByKey = <String, MapEntry<PersonalEvalReplayTrialKey, File>>{};
  for (final entry in caseLogFiles.entries) {
    final key = PersonalEvalReplayTrialKey.parse(entry.key);
    if (!knownCaseIds.contains(key.caseId)) {
      throw FormatException('Unknown case log case id: ${key.caseId}');
    }
    if (logsByKey.containsKey(key.normalized)) {
      throw FormatException('Duplicate replay trial: ${key.normalized}');
    }
    logsByKey[key.normalized] = MapEntry(key, entry.value);
  }

  final resultsByKey = <String, PersonalEvalVerificationResult>{};
  for (final entry in verificationResults.entries) {
    final key = PersonalEvalReplayTrialKey.parse(entry.key);
    if (!knownCaseIds.contains(key.caseId)) {
      throw FormatException(
        'Unknown verification result case id: ${key.caseId}',
      );
    }
    if (resultsByKey.containsKey(key.normalized)) {
      throw FormatException('Duplicate verification trial: ${key.normalized}');
    }
    resultsByKey[key.normalized] = entry.value;
  }

  for (final key in logsByKey.keys) {
    if (!resultsByKey.containsKey(key)) {
      throw FormatException('Missing verification result for trial $key.');
    }
  }
  for (final key in resultsByKey.keys) {
    if (!logsByKey.containsKey(key)) {
      throw FormatException('Missing replay log for trial $key.');
    }
  }

  return [
    for (final entry in logsByKey.entries)
      _PersonalEvalReplayTrialInput(
        key: entry.value.key,
        logFile: entry.value.value,
        verificationResult: resultsByKey[entry.key]!,
      ),
  ];
}

final class PersonalEvalReplayTrialKey {
  const PersonalEvalReplayTrialKey({
    required this.caseId,
    required this.trialId,
  });

  final String caseId;
  final String trialId;

  String get normalized => '$caseId#$trialId';

  factory PersonalEvalReplayTrialKey.parse(String value) {
    final normalized = value.trim();
    final separator = normalized.indexOf('#');
    final caseId =
        (separator < 0 ? normalized : normalized.substring(0, separator))
            .trim();
    final trialId =
        (separator < 0 ? _defaultTrialId : normalized.substring(separator + 1))
            .trim();
    if (caseId.isEmpty || trialId.isEmpty || trialId.contains('#')) {
      throw FormatException('Invalid replay trial key: $value');
    }
    return PersonalEvalReplayTrialKey(caseId: caseId, trialId: trialId);
  }
}

final class _PersonalEvalReplayTrialInput {
  const _PersonalEvalReplayTrialInput({
    required this.key,
    required this.logFile,
    required this.verificationResult,
  });

  final PersonalEvalReplayTrialKey key;
  final File logFile;
  final PersonalEvalVerificationResult verificationResult;
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

  int get distinctCaseCount =>
      cases.map((entry) => entry.caseId).toSet().length;

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
      'distinctCaseCount': distinctCaseCount,
      'trialCount': cases.length,
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
      ..writeln('- Distinct cases: `$distinctCaseCount`')
      ..writeln('- Trials: `${cases.length}`')
      ..writeln('- Passed: `$passedCount`')
      ..writeln('- Failed: `$failedCount`')
      ..writeln('- Inconclusive: `$inconclusiveCount`')
      ..writeln('- Duration: `$totalDurationMs ms`')
      ..writeln('- Tool calls: `$totalToolCallCount`')
      ..writeln()
      ..writeln(
        '| Order | Case | Trial | Origin | Split | Tier | Prompt Style | Started | Result | Duration | Tool Calls | Turns | Summary |',
      )
      ..writeln(
        '|-------|------|-------|--------|-------|------|--------------|---------|--------|----------|------------|-------|---------|',
      );

    for (final entry in cases) {
      buffer.writeln(
        '| `${entry.executionOrder}` '
        '| ${_markdownCell(entry.caseId)} '
        '| ${_markdownCell(entry.trialId)} '
        '| `${entry.origin}` '
        '| `${entry.split}` '
        '| `${entry.tier?.toString() ?? 'unclassified'}` '
        '| `${entry.promptStyle ?? 'unclassified'}` '
        '| `${entry.startedAt?.toIso8601String() ?? 'unknown'}` '
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
    required this.trialId,
    required this.executionOrder,
    required this.startedAt,
    required this.title,
    required this.origin,
    required this.split,
    required this.tier,
    required this.promptStyle,
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
  final String trialId;
  final int executionOrder;
  final DateTime? startedAt;
  final String title;
  final String origin;
  final String split;
  final int? tier;
  final String? promptStyle;
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
    required String trialId,
    required int executionOrder,
    required PersonalEvalVerificationResult verificationResult,
    required CavernoLlmSessionLogSummary summary,
  }) {
    return PersonalEvalReplayCaseArtifact(
      caseId: manifest.caseId,
      trialId: trialId,
      executionOrder: executionOrder,
      startedAt: _startedAt(summary),
      title: manifest.title,
      origin: manifest.origin,
      split: manifest.split,
      tier: manifest.tier,
      promptStyle: manifest.promptStyle,
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
      'trialId': trialId,
      'executionOrder': executionOrder,
      if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
      'title': title,
      'origin': origin,
      'split': split,
      if (tier != null) 'tier': tier,
      if (promptStyle != null) 'promptStyle': promptStyle,
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

DateTime? _startedAt(CavernoLlmSessionLogSummary summary) {
  DateTime? earliest;
  for (final entry in summary.entries) {
    if (entry.isMemoryExtraction || entry.isAutoReview) continue;
    final parsed = DateTime.tryParse(entry.startedAt ?? '');
    if (parsed != null && (earliest == null || parsed.isBefore(earliest))) {
      earliest = parsed;
    }
  }
  return earliest;
}

final class PersonalEvalReplayCaseManifest {
  const PersonalEvalReplayCaseManifest({
    required this.path,
    required this.caseId,
    required this.title,
    required this.readiness,
    required this.expectedVerificationResult,
    required this.origin,
    required this.split,
    required this.tier,
    required this.promptStyle,
  });

  final String path;
  final String caseId;
  final String title;
  final String readiness;
  final PersonalEvalVerificationResult expectedVerificationResult;
  final String origin;
  final String split;
  final int? tier;
  final String? promptStyle;

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
    final origin = _asString(json['origin']) ?? 'recorded';
    if (origin != 'recorded' && origin != 'authored') {
      throw FormatException('Invalid personal eval origin in $path.');
    }
    final split = _asString(json['split']) ?? 'heldIn';
    if (split != 'heldIn' && split != 'heldOut') {
      throw FormatException('Invalid personal eval split in $path.');
    }
    return PersonalEvalReplayCaseManifest(
      path: path,
      caseId: _requiredString(json, 'caseId', path),
      title: _requiredString(json, 'title', path),
      readiness: _asString(json['readiness']) ?? 'unknown',
      expectedVerificationResult: verificationResult,
      origin: origin,
      split: split,
      tier: _optionalTier(json['tier'], path),
      promptStyle: _optionalPromptStyle(json['promptStyle'], path),
    );
  }
}

int? _optionalTier(Object? value, String path) {
  if (value == null) return null;
  if (value is! int || value < 1 || value > 3) {
    throw FormatException('Invalid personal eval tier in $path.');
  }
  return value;
}

String? _optionalPromptStyle(Object? value, String path) {
  if (value == null) return null;
  if (value != 'guided' && value != 'unguided') {
    throw FormatException('Invalid personal eval promptStyle in $path.');
  }
  return value as String;
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
