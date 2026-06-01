import 'dart:convert';
import 'dart:io';

import 'live_llm_canary_reference_report.dart';

Future<void> main(List<String> args) async {
  final options = LiveLlmCanaryReferenceCompareOptions.parse(args);
  if (options == null) {
    stderr.writeln(
      'Usage: dart run tool/live_llm_canary_reference_compare.dart '
      '--reference PATH --candidate PATH --out-dir PATH [--label LABEL]',
    );
    exitCode = 64;
    return;
  }

  final LiveLlmCanaryReferenceComparison comparison;
  try {
    comparison = await buildLiveLlmCanaryReferenceComparison(
      referenceReport: File(options.referencePath),
      candidateReport: File(options.candidatePath),
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
  final jsonFile = File('${outputDirectory.path}/reference_compare.json');
  await jsonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(comparison.toJson()),
  );
  final markdownFile = File('${outputDirectory.path}/reference_compare.md');
  await markdownFile.writeAsString(comparison.toMarkdown());

  stdout.writeln(
    'Live LLM canary reference comparison written to ${jsonFile.path}',
  );
  stdout.writeln(comparison.toMarkdown());

  if (!comparison.isSuccessful) {
    exitCode = 1;
  }
}

Future<LiveLlmCanaryReferenceComparison> buildLiveLlmCanaryReferenceComparison({
  required File referenceReport,
  required File candidateReport,
  String? label,
  DateTime? generatedAt,
}) async {
  final reference = LiveLlmCanaryReferenceReport.fromJson(
    await _readJsonObject(referenceReport),
  );
  final candidate = LiveLlmCanaryReferenceReport.fromJson(
    await _readJsonObject(candidateReport),
  );
  final entries = _compareEntries(reference, candidate);

  return LiveLlmCanaryReferenceComparison(
    schemaName: 'live_llm_canary_reference_compare',
    schemaVersion: 1,
    generatedAt: generatedAt ?? DateTime.now(),
    label: label ?? '${reference.label} vs ${candidate.label}',
    referencePath: referenceReport.path,
    candidatePath: candidateReport.path,
    reference: reference,
    candidate: candidate,
    entries: entries,
  );
}

class LiveLlmCanaryReferenceComparison {
  const LiveLlmCanaryReferenceComparison({
    required this.schemaName,
    required this.schemaVersion,
    required this.generatedAt,
    required this.label,
    required this.referencePath,
    required this.candidatePath,
    required this.reference,
    required this.candidate,
    required this.entries,
  });

  final String schemaName;
  final int schemaVersion;
  final DateTime generatedAt;
  final String label;
  final String referencePath;
  final String candidatePath;
  final LiveLlmCanaryReferenceReport reference;
  final LiveLlmCanaryReferenceReport candidate;
  final List<LiveLlmCanaryReferenceComparisonEntry> entries;

  int get hardRegressionCount =>
      entries.fold(0, (sum, entry) => sum + entry.hardRegressions.length);

  int get watchSignalCount =>
      entries.fold(0, (sum, entry) => sum + entry.watchSignals.length);

  int get improvementCount =>
      entries.fold(0, (sum, entry) => sum + entry.improvements.length);

  bool get isSuccessful => candidate.isSuccessful && hardRegressionCount == 0;

  String get result => isSuccessful ? 'passed' : 'failed';

  Map<String, dynamic> toJson() {
    return {
      'schemaName': schemaName,
      'schemaVersion': schemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'label': label,
      'result': result,
      'referencePath': referencePath,
      'candidatePath': candidatePath,
      'reference': _summaryJson(reference),
      'candidate': _summaryJson(candidate),
      'hardRegressionCount': hardRegressionCount,
      'watchSignalCount': watchSignalCount,
      'improvementCount': improvementCount,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Live LLM Canary Reference Comparison')
      ..writeln()
      ..writeln('- Label: `$label`')
      ..writeln('- Result: `$result`')
      ..writeln(
        '- Reference: `${reference.label}` `${reference.model ?? 'unknown'}`',
      )
      ..writeln(
        '- Candidate: `${candidate.label}` `${candidate.model ?? 'unknown'}`',
      )
      ..writeln(
        '- Checks: `${reference.totalPassed}/${reference.totalCount}` reference, '
        '`${candidate.totalPassed}/${candidate.totalCount}` candidate',
      )
      ..writeln('- Hard regressions: `$hardRegressionCount`')
      ..writeln('- Watch signals: `$watchSignalCount`')
      ..writeln('- Improvements: `$improvementCount`')
      ..writeln()
      ..writeln(
        '| Surface | Check | Status | Reference | Candidate | Hard Regressions | Watch Signals | Improvements |',
      )
      ..writeln(
        '|---------|-------|--------|-----------|-----------|------------------|---------------|--------------|',
      );

    for (final entry in entries) {
      buffer.writeln(
        '| ${_tableCell(entry.surface)} '
        '| ${_tableCell(entry.check)} '
        '| `${entry.status}` '
        '| ${_tableCell(entry.referenceSummary)} '
        '| ${_tableCell(entry.candidateSummary)} '
        '| ${_listCell(entry.hardRegressions)} '
        '| ${_listCell(entry.watchSignals)} '
        '| ${_listCell(entry.improvements)} |',
      );
    }

    return buffer.toString();
  }

  Map<String, dynamic> _summaryJson(LiveLlmCanaryReferenceReport report) {
    return {
      'label': report.label,
      'result': report.result,
      'model': report.model,
      'baseUrl': report.baseUrl,
      'totalPassed': report.totalPassed,
      'totalCount': report.totalCount,
      'totalFailed': report.totalFailed,
      'validationErrors': report.validationErrors,
    };
  }
}

class LiveLlmCanaryReferenceComparisonEntry {
  const LiveLlmCanaryReferenceComparisonEntry({
    required this.surface,
    required this.check,
    required this.status,
    required this.referenceEntry,
    required this.candidateEntry,
    required this.hardRegressions,
    required this.watchSignals,
    required this.improvements,
  });

  final String surface;
  final String check;
  final String status;
  final LiveLlmCanaryReferenceEntry? referenceEntry;
  final LiveLlmCanaryReferenceEntry? candidateEntry;
  final List<String> hardRegressions;
  final List<String> watchSignals;
  final List<String> improvements;

  String get referenceSummary => _entrySummary(referenceEntry);

  String get candidateSummary => _entrySummary(candidateEntry);

  Map<String, dynamic> toJson() {
    return {
      'surface': surface,
      'check': check,
      'status': status,
      'reference': _entryJson(referenceEntry),
      'candidate': _entryJson(candidateEntry),
      'hardRegressions': hardRegressions,
      'watchSignals': watchSignals,
      'improvements': improvements,
    };
  }

  static Map<String, dynamic>? _entryJson(LiveLlmCanaryReferenceEntry? entry) {
    if (entry == null) {
      return null;
    }
    return {
      'result': entry.result,
      'passed': entry.passed,
      'total': entry.total,
      'failed': entry.failed,
      'riskSummary': entry.riskSummary,
    };
  }

  static String _entrySummary(LiveLlmCanaryReferenceEntry? entry) {
    if (entry == null) {
      return 'missing';
    }
    return '${entry.result} ${entry.passed}/${entry.total}; ${entry.riskSummary}';
  }
}

class LiveLlmCanaryReferenceCompareOptions {
  const LiveLlmCanaryReferenceCompareOptions({
    required this.referencePath,
    required this.candidatePath,
    required this.outDir,
    required this.label,
  });

  final String referencePath;
  final String candidatePath;
  final String outDir;
  final String? label;

  static LiveLlmCanaryReferenceCompareOptions? parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (!arg.startsWith('--') || index + 1 >= args.length) {
        return null;
      }
      values[arg.substring(2)] = args[index + 1];
      index += 1;
    }

    final referencePath = values['reference'];
    final candidatePath = values['candidate'];
    final outDir = values['out-dir'];
    if (referencePath == null || candidatePath == null || outDir == null) {
      return null;
    }
    return LiveLlmCanaryReferenceCompareOptions(
      referencePath: referencePath,
      candidatePath: candidatePath,
      outDir: outDir,
      label: values['label'],
    );
  }
}

List<LiveLlmCanaryReferenceComparisonEntry> _compareEntries(
  LiveLlmCanaryReferenceReport reference,
  LiveLlmCanaryReferenceReport candidate,
) {
  final referenceEntries = {
    for (final entry in reference.entries) _entryKey(entry): entry,
  };
  final candidateEntries = {
    for (final entry in candidate.entries) _entryKey(entry): entry,
  };
  final keys = <String>{
    ...referenceEntries.keys,
    ...candidateEntries.keys,
  }.toList()..sort();

  return keys
      .map((key) {
        final referenceEntry = referenceEntries[key];
        final candidateEntry = candidateEntries[key];
        return _compareEntry(referenceEntry, candidateEntry);
      })
      .toList(growable: false);
}

LiveLlmCanaryReferenceComparisonEntry _compareEntry(
  LiveLlmCanaryReferenceEntry? reference,
  LiveLlmCanaryReferenceEntry? candidate,
) {
  final surface = candidate?.surface ?? reference?.surface ?? 'unknown';
  final check = candidate?.check ?? reference?.check ?? 'unknown';
  final hardRegressions = <String>[];
  final watchSignals = <String>[];
  final improvements = <String>[];

  if (reference == null && candidate != null) {
    if (candidate.result == 'passed') {
      improvements.add('added passing check');
    } else {
      hardRegressions.add('added failing check');
    }
    return LiveLlmCanaryReferenceComparisonEntry(
      surface: surface,
      check: check,
      status: hardRegressions.isEmpty ? 'added' : 'regressed',
      referenceEntry: reference,
      candidateEntry: candidate,
      hardRegressions: hardRegressions,
      watchSignals: watchSignals,
      improvements: improvements,
    );
  }

  if (reference != null && candidate == null) {
    hardRegressions.add('missing candidate check');
    return LiveLlmCanaryReferenceComparisonEntry(
      surface: surface,
      check: check,
      status: 'regressed',
      referenceEntry: reference,
      candidateEntry: candidate,
      hardRegressions: hardRegressions,
      watchSignals: watchSignals,
      improvements: improvements,
    );
  }

  final referenceEntry = reference!;
  final candidateEntry = candidate!;

  if (referenceEntry.result == 'passed' && candidateEntry.result != 'passed') {
    hardRegressions.add(
      'result regressed from passed to ${candidateEntry.result}',
    );
  }
  if (referenceEntry.result != 'passed' && candidateEntry.result == 'passed') {
    improvements.add('result improved from ${referenceEntry.result} to passed');
  }
  _compareInt(
    hardRegressions,
    improvements,
    name: 'failed tests',
    referenceValue: referenceEntry.failed,
    candidateValue: candidateEntry.failed,
  );
  _compareInt(
    hardRegressions,
    improvements,
    name: 'unexpected warnings',
    referenceValue: referenceEntry.signals.unexpectedWarningCount,
    candidateValue: candidateEntry.signals.unexpectedWarningCount,
  );
  _compareInt(
    hardRegressions,
    improvements,
    name: 'task drift',
    referenceValue: referenceEntry.signals.taskDriftCount,
    candidateValue: candidateEntry.signals.taskDriftCount,
  );
  _compareInt(
    hardRegressions,
    improvements,
    name: 'report blockers',
    referenceValue: referenceEntry.signals.reportQualityBlockerCount,
    candidateValue: candidateEntry.signals.reportQualityBlockerCount,
  );
  _compareInt(
    hardRegressions,
    improvements,
    name: 'stream fallback',
    referenceValue: referenceEntry.signals.recoveredStreamFallbackCount,
    candidateValue: candidateEntry.signals.recoveredStreamFallbackCount,
  );
  _compareInt(
    hardRegressions,
    improvements,
    name: 'transport disconnect',
    referenceValue: referenceEntry.signals.transportDisconnectCount,
    candidateValue: candidateEntry.signals.transportDisconnectCount,
  );
  _compareInt(
    hardRegressions,
    improvements,
    name: 'memory fallback',
    referenceValue: referenceEntry.signals.memoryExtractionFallbackCount,
    candidateValue: candidateEntry.signals.memoryExtractionFallbackCount,
  );
  _compareInt(
    hardRegressions,
    improvements,
    name: 'assistant tool blocks',
    referenceValue: referenceEntry.signals.assistantAuthoredToolBlockCount,
    candidateValue: candidateEntry.signals.assistantAuthoredToolBlockCount,
  );
  _compareRequiredEvidenceInt(
    hardRegressions,
    watchSignals,
    improvements,
    name: 'analyzer feedback',
    referenceValue: referenceEntry.signals.dartAnalyzeFeedbackCount,
    candidateValue: candidateEntry.signals.dartAnalyzeFeedbackCount,
  );
  _compareRequiredEvidenceInt(
    hardRegressions,
    watchSignals,
    improvements,
    name: 'analyzer diagnostics',
    referenceValue: referenceEntry.signals.dartAnalyzeDiagnosticCount,
    candidateValue: candidateEntry.signals.dartAnalyzeDiagnosticCount,
  );
  _compareRequiredEvidenceInt(
    hardRegressions,
    watchSignals,
    improvements,
    name: 'command output feedback',
    referenceValue: referenceEntry.signals.codingOutputFeedbackCount,
    candidateValue: candidateEntry.signals.codingOutputFeedbackCount,
  );
  _compareRequiredEvidenceInt(
    hardRegressions,
    watchSignals,
    improvements,
    name: 'command output issues',
    referenceValue: referenceEntry.signals.codingOutputIssueCount,
    candidateValue: candidateEntry.signals.codingOutputIssueCount,
  );
  _compareWatchInt(
    watchSignals,
    improvements,
    name: 'allowed warnings',
    referenceValue: referenceEntry.signals.allowedWarningCount,
    candidateValue: candidateEntry.signals.allowedWarningCount,
  );
  _compareWatchInt(
    watchSignals,
    improvements,
    name: 'guard activations',
    referenceValue: referenceEntry.signals.guardActivationCount,
    candidateValue: candidateEntry.signals.guardActivationCount,
  );
  _compareWatchInt(
    watchSignals,
    improvements,
    name: 'cleanup cancellations',
    referenceValue: referenceEntry.signals.cleanupCancellationCount,
    candidateValue: candidateEntry.signals.cleanupCancellationCount,
  );
  _compareWatchInt(
    watchSignals,
    improvements,
    name: 'approval fallback',
    referenceValue: referenceEntry.signals.approvalFallbackCount,
    candidateValue: candidateEntry.signals.approvalFallbackCount,
  );
  _compareWatchInt(
    watchSignals,
    improvements,
    name: 'compaction retry',
    referenceValue: referenceEntry.signals.toolResultCompactionRetryCount,
    candidateValue: candidateEntry.signals.toolResultCompactionRetryCount,
  );

  final status = hardRegressions.isNotEmpty
      ? 'regressed'
      : watchSignals.isNotEmpty
      ? 'watch'
      : improvements.isNotEmpty
      ? 'improved'
      : 'unchanged';

  return LiveLlmCanaryReferenceComparisonEntry(
    surface: surface,
    check: check,
    status: status,
    referenceEntry: referenceEntry,
    candidateEntry: candidateEntry,
    hardRegressions: hardRegressions,
    watchSignals: watchSignals,
    improvements: improvements,
  );
}

void _compareInt(
  List<String> hardRegressions,
  List<String> improvements, {
  required String name,
  required int referenceValue,
  required int candidateValue,
}) {
  if (candidateValue > referenceValue) {
    hardRegressions.add('$name increased $referenceValue->$candidateValue');
  } else if (candidateValue < referenceValue) {
    improvements.add('$name decreased $referenceValue->$candidateValue');
  }
}

void _compareRequiredEvidenceInt(
  List<String> hardRegressions,
  List<String> watchSignals,
  List<String> improvements, {
  required String name,
  required int referenceValue,
  required int candidateValue,
}) {
  if (candidateValue < referenceValue) {
    hardRegressions.add('$name decreased $referenceValue->$candidateValue');
  } else if (candidateValue > referenceValue) {
    if (referenceValue == 0) {
      improvements.add('$name added 0->$candidateValue');
    } else {
      watchSignals.add('$name increased $referenceValue->$candidateValue');
    }
  }
}

void _compareWatchInt(
  List<String> watchSignals,
  List<String> improvements, {
  required String name,
  required int referenceValue,
  required int candidateValue,
}) {
  if (candidateValue > referenceValue) {
    watchSignals.add('$name increased $referenceValue->$candidateValue');
  } else if (candidateValue < referenceValue) {
    improvements.add('$name decreased $referenceValue->$candidateValue');
  }
}

Future<Map<String, dynamic>> _readJsonObject(File file) async {
  if (!file.existsSync()) {
    throw FileSystemException('Reference report not found', file.path);
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Expected a JSON object in ${file.path}.');
  }
  return decoded;
}

String _entryKey(LiveLlmCanaryReferenceEntry entry) {
  return '${entry.surface}\u0000${entry.check}';
}

String _listCell(List<String> values) {
  if (values.isEmpty) {
    return 'none';
  }
  return _tableCell(values.join('; '));
}

String _tableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}
