import 'dart:convert';
import 'dart:io';

import 'personal_eval_case_manifest.dart';

const _schemaName = 'caverno_personal_eval_suite_report';
const _schemaVersion = 1;
const _runSchemaName = 'caverno_personal_eval_replay_run';

Future<void> main(List<String> args) async {
  final options = PersonalEvalSuiteReportOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/personal_eval_suite_report.dart '
      '--manifest PATH [--manifest PATH ...] '
      '--incumbent PATH --candidate PATH --out-dir PATH [--label LABEL]',
    );
    exitCode = 64;
    return;
  }

  final PersonalEvalSuiteReport report;
  try {
    report = await buildPersonalEvalSuiteReport(
      manifestFiles: options.manifestPaths.map(File.new).toList(),
      incumbentResultFile: File(options.incumbentPath),
      candidateResultFile: File(options.candidatePath),
      label: options.label,
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

  final outputDirectory = Directory(options.outDir);
  outputDirectory.createSync(recursive: true);
  final jsonFile = File(
    '${outputDirectory.path}/personal_eval_suite_report.json',
  );
  await jsonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report.toJson()),
  );
  final markdownFile = File(
    '${outputDirectory.path}/personal_eval_suite_report.md',
  );
  await markdownFile.writeAsString(report.toMarkdown());

  stdout.writeln('Personal eval suite report written to ${jsonFile.path}');
  stdout.writeln(report.toMarkdown());

  if (!report.isSuccessful) {
    exitCode = 1;
  }
}

Future<PersonalEvalSuiteReport> buildPersonalEvalSuiteReport({
  required List<File> manifestFiles,
  required File incumbentResultFile,
  required File candidateResultFile,
  String? label,
  DateTime? generatedAt,
}) async {
  if (manifestFiles.isEmpty) {
    throw const FormatException('At least one eval case manifest is required.');
  }

  final manifests = <PersonalEvalCaseManifestRecord>[];
  final seenCaseIds = <String>{};
  for (final file in manifestFiles) {
    final manifest = PersonalEvalCaseManifestRecord.fromJson(
      await _readJsonObject(file),
      path: file.path,
    );
    if (!seenCaseIds.add(manifest.caseId)) {
      throw FormatException('Duplicate eval case id: ${manifest.caseId}');
    }
    manifests.add(manifest);
  }

  final incumbent = PersonalEvalReplayRun.fromJson(
    await _readJsonObject(incumbentResultFile),
    path: incumbentResultFile.path,
  );
  final candidate = PersonalEvalReplayRun.fromJson(
    await _readJsonObject(candidateResultFile),
    path: candidateResultFile.path,
  );

  final entries = [
    for (final manifest in manifests)
      PersonalEvalSuiteReportEntry.compare(
        manifest: manifest,
        incumbent: incumbent.caseById[manifest.caseId],
        candidate: candidate.caseById[manifest.caseId],
      ),
  ];

  return PersonalEvalSuiteReport(
    schemaName: _schemaName,
    schemaVersion: _schemaVersion,
    generatedAt: generatedAt ?? DateTime.now(),
    label: label ?? '${incumbent.label} vs ${candidate.label}',
    manifestPaths: manifestFiles.map((file) => file.path).toList(),
    incumbentPath: incumbentResultFile.path,
    candidatePath: candidateResultFile.path,
    incumbent: PersonalEvalRunSummary.fromRun(incumbent, manifests),
    candidate: PersonalEvalRunSummary.fromRun(candidate, manifests),
    entries: entries,
  );
}

final class PersonalEvalSuiteReportOptions {
  const PersonalEvalSuiteReportOptions({
    required this.manifestPaths,
    required this.incumbentPath,
    required this.candidatePath,
    required this.outDir,
    this.label,
  });

  final List<String> manifestPaths;
  final String incumbentPath;
  final String candidatePath;
  final String outDir;
  final String? label;

  static PersonalEvalSuiteReportOptions? parse(List<String> args) {
    final manifests = <String>[];
    String? incumbentPath;
    String? candidatePath;
    String? outDir;
    String? label;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--manifest':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          manifests.add(value);
        case '--incumbent':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          incumbentPath = value;
        case '--candidate':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          candidatePath = value;
        case '--out-dir':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          outDir = value;
        case '--label':
          final value = _nextValue(args, ++index);
          if (value == null) return null;
          label = value;
        default:
          return null;
      }
    }

    if (manifests.isEmpty ||
        incumbentPath == null ||
        candidatePath == null ||
        outDir == null) {
      return null;
    }
    return PersonalEvalSuiteReportOptions(
      manifestPaths: List.unmodifiable(manifests),
      incumbentPath: incumbentPath,
      candidatePath: candidatePath,
      outDir: outDir,
      label: label,
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

final class PersonalEvalSuiteReport {
  const PersonalEvalSuiteReport({
    required this.schemaName,
    required this.schemaVersion,
    required this.generatedAt,
    required this.label,
    required this.manifestPaths,
    required this.incumbentPath,
    required this.candidatePath,
    required this.incumbent,
    required this.candidate,
    required this.entries,
  });

  final String schemaName;
  final int schemaVersion;
  final DateTime generatedAt;
  final String label;
  final List<String> manifestPaths;
  final String incumbentPath;
  final String candidatePath;
  final PersonalEvalRunSummary incumbent;
  final PersonalEvalRunSummary candidate;
  final List<PersonalEvalSuiteReportEntry> entries;

  int get hardRegressionCount =>
      entries.fold(0, (sum, entry) => sum + entry.hardRegressions.length);

  int get watchSignalCount =>
      entries.fold(0, (sum, entry) => sum + entry.watchSignals.length);

  int get improvementCount =>
      entries.fold(0, (sum, entry) => sum + entry.improvements.length);

  bool get isSuccessful => hardRegressionCount == 0;

  String get result => isSuccessful ? 'passed' : 'failed';

  String get recommendation =>
      isSuccessful ? 'candidate_ready' : 'reject_candidate';

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'label': label,
      'result': result,
      'recommendation': recommendation,
      'manifestPaths': manifestPaths,
      'incumbentPath': incumbentPath,
      'candidatePath': candidatePath,
      'hardRegressionCount': hardRegressionCount,
      'watchSignalCount': watchSignalCount,
      'improvementCount': improvementCount,
      'incumbent': incumbent.toJson(),
      'candidate': candidate.toJson(),
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Personal Eval Suite Report')
      ..writeln()
      ..writeln('- Label: `$label`')
      ..writeln('- Result: `$result`')
      ..writeln('- Recommendation: `$recommendation`')
      ..writeln('- Cases: `${entries.length}`')
      ..writeln(
        '- Pass rate: `${_percent(incumbent.passRate)}` incumbent, '
        '`${_percent(candidate.passRate)}` candidate',
      )
      ..writeln('- Hard regressions: `$hardRegressionCount`')
      ..writeln('- Watch signals: `$watchSignalCount`')
      ..writeln('- Improvements: `$improvementCount`')
      ..writeln()
      ..writeln(
        '| Case | Status | Incumbent | Candidate | Hard Regressions | Watch Signals | Improvements |',
      )
      ..writeln(
        '|------|--------|-----------|-----------|------------------|---------------|--------------|',
      );

    for (final entry in entries) {
      buffer.writeln(
        '| ${_tableCell(entry.caseId)} '
        '| `${entry.status}` '
        '| ${_tableCell(entry.incumbentSummary)} '
        '| ${_tableCell(entry.candidateSummary)} '
        '| ${_listCell(entry.hardRegressions)} '
        '| ${_listCell(entry.watchSignals)} '
        '| ${_listCell(entry.improvements)} |',
      );
    }

    return buffer.toString();
  }
}

final class PersonalEvalRunSummary {
  const PersonalEvalRunSummary({
    required this.label,
    required this.model,
    required this.baseUrl,
    required this.caseCount,
    required this.missingCaseCount,
    required this.passedCount,
    required this.failedCount,
    required this.inconclusiveCount,
    required this.totalDurationMs,
    required this.totalToolCallCount,
    required this.averageToolCallDelta,
  });

  final String label;
  final String? model;
  final String? baseUrl;
  final int caseCount;
  final int missingCaseCount;
  final int passedCount;
  final int failedCount;
  final int inconclusiveCount;
  final int totalDurationMs;
  final int totalToolCallCount;
  final double averageToolCallDelta;

  double get passRate => caseCount == 0 ? 0 : passedCount / caseCount;

  double get averageDurationMs =>
      caseCount == 0 ? 0 : totalDurationMs / caseCount;

  factory PersonalEvalRunSummary.fromRun(
    PersonalEvalReplayRun run,
    List<PersonalEvalCaseManifestRecord> manifests,
  ) {
    var missing = 0;
    var passed = 0;
    var failed = 0;
    var inconclusive = 0;
    var duration = 0;
    var toolCalls = 0;
    var toolDelta = 0;
    for (final manifest in manifests) {
      final result = run.caseById[manifest.caseId];
      if (result == null) {
        missing += 1;
        continue;
      }
      switch (result.verificationResult) {
        case PersonalEvalVerificationResult.passed:
          passed += 1;
        case PersonalEvalVerificationResult.failed:
          failed += 1;
        case PersonalEvalVerificationResult.inconclusive:
          inconclusive += 1;
      }
      duration += result.durationMs;
      toolCalls += result.toolCallCount;
      toolDelta += (result.toolCallCount - manifest.sourceToolCallCount).abs();
    }
    final caseCount = manifests.length;
    return PersonalEvalRunSummary(
      label: run.label,
      model: run.model,
      baseUrl: run.baseUrl,
      caseCount: caseCount,
      missingCaseCount: missing,
      passedCount: passed,
      failedCount: failed,
      inconclusiveCount: inconclusive,
      totalDurationMs: duration,
      totalToolCallCount: toolCalls,
      averageToolCallDelta: caseCount == 0 ? 0 : toolDelta / caseCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      if (model != null) 'model': model,
      if (baseUrl != null) 'baseUrl': baseUrl,
      'caseCount': caseCount,
      'missingCaseCount': missingCaseCount,
      'passedCount': passedCount,
      'failedCount': failedCount,
      'inconclusiveCount': inconclusiveCount,
      'passRate': passRate,
      'totalDurationMs': totalDurationMs,
      'averageDurationMs': averageDurationMs,
      'totalToolCallCount': totalToolCallCount,
      'averageToolCallDelta': averageToolCallDelta,
    };
  }
}

final class PersonalEvalSuiteReportEntry {
  const PersonalEvalSuiteReportEntry({
    required this.caseId,
    required this.title,
    required this.status,
    required this.expectedToolCallCount,
    required this.incumbent,
    required this.candidate,
    required this.hardRegressions,
    required this.watchSignals,
    required this.improvements,
  });

  final String caseId;
  final String title;
  final String status;
  final int expectedToolCallCount;
  final PersonalEvalReplayCaseResult? incumbent;
  final PersonalEvalReplayCaseResult? candidate;
  final List<String> hardRegressions;
  final List<String> watchSignals;
  final List<String> improvements;

  String get incumbentSummary => _resultSummary(incumbent);

  String get candidateSummary => _resultSummary(candidate);

  factory PersonalEvalSuiteReportEntry.compare({
    required PersonalEvalCaseManifestRecord manifest,
    required PersonalEvalReplayCaseResult? incumbent,
    required PersonalEvalReplayCaseResult? candidate,
  }) {
    final hardRegressions = <String>[];
    final watchSignals = <String>[];
    final improvements = <String>[];

    if (incumbent == null) {
      hardRegressions.add('missing incumbent result');
    }
    if (candidate == null) {
      hardRegressions.add('missing candidate result');
    }

    if (incumbent != null && candidate != null) {
      _compareVerificationResult(
        incumbent: incumbent,
        candidate: candidate,
        hardRegressions: hardRegressions,
        improvements: improvements,
      );
      _compareDuration(
        incumbent: incumbent,
        candidate: candidate,
        watchSignals: watchSignals,
        improvements: improvements,
      );
      _compareTurns(
        incumbent: incumbent,
        candidate: candidate,
        watchSignals: watchSignals,
        improvements: improvements,
      );
      _compareToolCallFidelity(
        expectedToolCallCount: manifest.sourceToolCallCount,
        incumbent: incumbent,
        candidate: candidate,
        watchSignals: watchSignals,
        improvements: improvements,
      );
    }

    return PersonalEvalSuiteReportEntry(
      caseId: manifest.caseId,
      title: manifest.title,
      status: _entryStatus(hardRegressions, watchSignals, improvements),
      expectedToolCallCount: manifest.sourceToolCallCount,
      incumbent: incumbent,
      candidate: candidate,
      hardRegressions: List.unmodifiable(hardRegressions),
      watchSignals: List.unmodifiable(watchSignals),
      improvements: List.unmodifiable(improvements),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'caseId': caseId,
      'title': title,
      'status': status,
      'expectedToolCallCount': expectedToolCallCount,
      'incumbent': incumbent?.toJson(),
      'candidate': candidate?.toJson(),
      'hardRegressions': hardRegressions,
      'watchSignals': watchSignals,
      'improvements': improvements,
    };
  }

  static String _resultSummary(PersonalEvalReplayCaseResult? result) {
    if (result == null) {
      return 'missing';
    }
    return '${result.verificationResult.name}, '
        '${result.durationMs} ms, '
        '${result.toolCallCount} tools, '
        '${result.turnCount} turns';
  }
}

final class PersonalEvalCaseManifestRecord {
  const PersonalEvalCaseManifestRecord({
    required this.path,
    required this.caseId,
    required this.title,
    required this.readiness,
    required this.expectedVerificationResult,
    required this.sourceToolCallCount,
  });

  final String path;
  final String caseId;
  final String title;
  final String readiness;
  final PersonalEvalVerificationResult expectedVerificationResult;
  final int sourceToolCallCount;

  factory PersonalEvalCaseManifestRecord.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final schemaName = _asString(json['schemaName']);
    if (schemaName != 'caverno_personal_eval_case_manifest') {
      throw FormatException('Invalid personal eval manifest schema in $path.');
    }
    final task = _asStringMap(json['task']);
    final source = _asStringMap(json['source']);
    final summary = _asStringMap(source?['sessionLogSummary']);
    final verificationResult = PersonalEvalVerificationResult.parse(
      _asString(task?['verificationResult']) ?? '',
    );
    if (task == null || summary == null || verificationResult == null) {
      throw FormatException('Incomplete personal eval manifest in $path.');
    }
    return PersonalEvalCaseManifestRecord(
      path: path,
      caseId: _requiredString(json, 'caseId', path),
      title: _requiredString(json, 'title', path),
      readiness: _asString(json['readiness']) ?? 'unknown',
      expectedVerificationResult: verificationResult,
      sourceToolCallCount: _asInt(summary['toolCallCount']) ?? 0,
    );
  }
}

final class PersonalEvalReplayRun {
  const PersonalEvalReplayRun({
    required this.label,
    required this.model,
    required this.baseUrl,
    required this.cases,
    required this.path,
  });

  final String label;
  final String? model;
  final String? baseUrl;
  final List<PersonalEvalReplayCaseResult> cases;
  final String path;

  Map<String, PersonalEvalReplayCaseResult> get caseById => {
    for (final result in cases) result.caseId: result,
  };

  factory PersonalEvalReplayRun.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final schemaName = _asString(json['schemaName']);
    if (schemaName != _runSchemaName) {
      throw FormatException(
        'Invalid personal eval replay run schema in $path.',
      );
    }
    final rawCases = _asList(json['cases']);
    final cases = <PersonalEvalReplayCaseResult>[];
    final seenCaseIds = <String>{};
    for (final rawCase in rawCases) {
      final caseJson = _asStringMap(rawCase);
      if (caseJson == null) {
        throw FormatException('Invalid replay case entry in $path.');
      }
      final result = PersonalEvalReplayCaseResult.fromJson(
        caseJson,
        path: path,
      );
      if (!seenCaseIds.add(result.caseId)) {
        throw FormatException(
          'Duplicate replay result for case ${result.caseId} in $path.',
        );
      }
      cases.add(result);
    }
    return PersonalEvalReplayRun(
      label: _asString(json['label']) ?? 'unnamed',
      model: _asString(json['model']),
      baseUrl: _asString(json['baseUrl']),
      cases: List.unmodifiable(cases),
      path: path,
    );
  }
}

final class PersonalEvalReplayCaseResult {
  const PersonalEvalReplayCaseResult({
    required this.caseId,
    required this.verificationResult,
    required this.durationMs,
    required this.toolCallCount,
    required this.turnCount,
    required this.error,
  });

  final String caseId;
  final PersonalEvalVerificationResult verificationResult;
  final int durationMs;
  final int toolCallCount;
  final int turnCount;
  final String? error;

  factory PersonalEvalReplayCaseResult.fromJson(
    Map<String, dynamic> json, {
    required String path,
  }) {
    final verificationResult = PersonalEvalVerificationResult.parse(
      _asString(json['verificationResult']) ?? '',
    );
    if (verificationResult == null) {
      throw FormatException('Invalid verification result in $path.');
    }
    return PersonalEvalReplayCaseResult(
      caseId: _requiredString(json, 'caseId', path),
      verificationResult: verificationResult,
      durationMs: _asNonNegativeInt(json['durationMs']) ?? 0,
      toolCallCount: _asNonNegativeInt(json['toolCallCount']) ?? 0,
      turnCount: _asNonNegativeInt(json['turnCount']) ?? 0,
      error: _asString(json['error']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'caseId': caseId,
      'verificationResult': verificationResult.name,
      'durationMs': durationMs,
      'toolCallCount': toolCallCount,
      'turnCount': turnCount,
      if (error != null) 'error': error,
    };
  }
}

void _compareVerificationResult({
  required PersonalEvalReplayCaseResult incumbent,
  required PersonalEvalReplayCaseResult candidate,
  required List<String> hardRegressions,
  required List<String> improvements,
}) {
  final incumbentRank = _verificationRank(incumbent.verificationResult);
  final candidateRank = _verificationRank(candidate.verificationResult);
  if (candidateRank < incumbentRank) {
    hardRegressions.add(
      'verification result regressed '
      '${incumbent.verificationResult.name}->${candidate.verificationResult.name}',
    );
  } else if (candidateRank > incumbentRank) {
    improvements.add(
      'verification result improved '
      '${incumbent.verificationResult.name}->${candidate.verificationResult.name}',
    );
  }
}

void _compareDuration({
  required PersonalEvalReplayCaseResult incumbent,
  required PersonalEvalReplayCaseResult candidate,
  required List<String> watchSignals,
  required List<String> improvements,
}) {
  if (incumbent.durationMs <= 0 || candidate.durationMs <= 0) {
    return;
  }
  final increase = candidate.durationMs - incumbent.durationMs;
  if (increase > 1000 && candidate.durationMs > incumbent.durationMs * 1.1) {
    watchSignals.add(
      'duration increased ${incumbent.durationMs}->${candidate.durationMs} ms',
    );
  } else if (candidate.durationMs < incumbent.durationMs) {
    improvements.add(
      'duration decreased ${incumbent.durationMs}->${candidate.durationMs} ms',
    );
  }
}

void _compareTurns({
  required PersonalEvalReplayCaseResult incumbent,
  required PersonalEvalReplayCaseResult candidate,
  required List<String> watchSignals,
  required List<String> improvements,
}) {
  if (candidate.turnCount > incumbent.turnCount + 1) {
    watchSignals.add(
      'turn count increased ${incumbent.turnCount}->${candidate.turnCount}',
    );
  } else if (candidate.turnCount < incumbent.turnCount) {
    improvements.add(
      'turn count decreased ${incumbent.turnCount}->${candidate.turnCount}',
    );
  }
}

void _compareToolCallFidelity({
  required int expectedToolCallCount,
  required PersonalEvalReplayCaseResult incumbent,
  required PersonalEvalReplayCaseResult candidate,
  required List<String> watchSignals,
  required List<String> improvements,
}) {
  final incumbentDelta = (incumbent.toolCallCount - expectedToolCallCount)
      .abs();
  final candidateDelta = (candidate.toolCallCount - expectedToolCallCount)
      .abs();
  if (candidateDelta > incumbentDelta) {
    watchSignals.add(
      'tool-call fidelity delta increased $incumbentDelta->$candidateDelta',
    );
  } else if (candidateDelta < incumbentDelta) {
    improvements.add(
      'tool-call fidelity delta decreased $incumbentDelta->$candidateDelta',
    );
  }
}

int _verificationRank(PersonalEvalVerificationResult result) {
  return switch (result) {
    PersonalEvalVerificationResult.failed => 0,
    PersonalEvalVerificationResult.inconclusive => 1,
    PersonalEvalVerificationResult.passed => 2,
  };
}

String _entryStatus(
  List<String> hardRegressions,
  List<String> watchSignals,
  List<String> improvements,
) {
  if (hardRegressions.isNotEmpty) {
    return 'regressed';
  }
  if (watchSignals.isNotEmpty) {
    return improvements.isEmpty ? 'watch' : 'mixed';
  }
  if (improvements.isNotEmpty) {
    return 'improved';
  }
  return 'unchanged';
}

Future<Map<String, dynamic>> _readJsonObject(File file) async {
  final decoded = jsonDecode(await file.readAsString());
  final object = _asStringMap(decoded);
  if (object == null) {
    throw FormatException('Expected a JSON object in ${file.path}.');
  }
  return object;
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is Map) {
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }
  return null;
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

String? _asString(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

int? _asNonNegativeInt(Object? value) {
  final parsed = _asInt(value);
  if (parsed == null || parsed < 0) {
    return null;
  }
  return parsed;
}

String _requiredString(Map<String, dynamic> json, String key, String path) {
  final value = _asString(json[key])?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('Missing `$key` in $path.');
  }
  return value;
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _tableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

String _listCell(List<String> values) {
  if (values.isEmpty) {
    return '';
  }
  return values.map(_tableCell).join('<br>');
}
