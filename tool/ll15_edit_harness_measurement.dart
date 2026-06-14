import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = Ll15EditHarnessMeasurementOptions.parse(args);
  if (options == null) {
    stderr.writeln(Ll15EditHarnessMeasurementOptions.usage);
    exitCode = 64;
    return;
  }

  final summary = await buildLl15EditHarnessMeasurement(
    baselineSummaryPath: options.baselineSummaryPath,
    baselineLogPath: options.baselineLogPath,
    currentSummaryPath: options.currentSummaryPath,
    currentLogPath: options.currentLogPath,
  );

  if (options.outputPath != null) {
    final output = File(options.outputPath!);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(summary.toJson())}\n',
    );
  }

  switch (options.format) {
    case Ll15MeasurementOutputFormat.json:
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(summary.toJson()),
      );
    case Ll15MeasurementOutputFormat.markdown:
      stdout.write(summary.toMarkdown());
  }
}

enum Ll15MeasurementOutputFormat { markdown, json }

class Ll15EditHarnessMeasurementOptions {
  const Ll15EditHarnessMeasurementOptions({
    required this.baselineSummaryPath,
    required this.currentSummaryPath,
    required this.baselineLogPath,
    required this.currentLogPath,
    required this.outputPath,
    required this.format,
  });

  final String baselineSummaryPath;
  final String currentSummaryPath;
  final String? baselineLogPath;
  final String? currentLogPath;
  final String? outputPath;
  final Ll15MeasurementOutputFormat format;

  static const usage =
      'Usage: dart run tool/ll15_edit_harness_measurement.dart '
      '--baseline-summary PATH --current-summary PATH '
      '[--baseline-log PATH] [--current-log PATH] '
      '[--output PATH] [--format markdown|json]';

  static Ll15EditHarnessMeasurementOptions? parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (arg == '--help' || arg == '-h') return null;
      if (!arg.startsWith('--')) return null;
      final equalsIndex = arg.indexOf('=');
      if (equalsIndex > 0) {
        values[arg.substring(2, equalsIndex)] = arg.substring(equalsIndex + 1);
        continue;
      }
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        return null;
      }
      values[arg.substring(2)] = args[index + 1];
      index += 1;
    }

    final baselineSummaryPath = values['baseline-summary'];
    final currentSummaryPath = values['current-summary'];
    if (baselineSummaryPath == null || currentSummaryPath == null) {
      return null;
    }

    final format = switch (values['format']?.trim().toLowerCase()) {
      null || '' || 'markdown' => Ll15MeasurementOutputFormat.markdown,
      'json' => Ll15MeasurementOutputFormat.json,
      _ => null,
    };
    if (format == null) return null;

    return Ll15EditHarnessMeasurementOptions(
      baselineSummaryPath: baselineSummaryPath,
      currentSummaryPath: currentSummaryPath,
      baselineLogPath: values['baseline-log'],
      currentLogPath: values['current-log'],
      outputPath: values['output'],
      format: format,
    );
  }
}

class Ll15EditHarnessMeasurementSummary {
  const Ll15EditHarnessMeasurementSummary({
    required this.generatedAt,
    required this.baseline,
    required this.current,
  });

  final DateTime generatedAt;
  final Ll15CanaryRunSummary baseline;
  final Ll15CanaryRunSummary current;

  double get failureRateDelta => current.failureRate - baseline.failureRate;

  double get passRateDelta => current.passRate - baseline.passRate;

  bool get failureRateReduced {
    return baseline.attempts > 0 &&
        current.attempts > 0 &&
        current.failureRate < baseline.failureRate;
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaName': 'caverno_ll15_edit_harness_measurement',
      'schemaVersion': 2,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'baseline': baseline.toJson(),
      'current': current.toJson(),
      'comparison': {
        'failureRateDelta': failureRateDelta,
        'failureRateReduced': failureRateReduced,
        'passRateDelta': passRateDelta,
      },
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# LL15 Weak-Model Edit Harness Measurement')
      ..writeln()
      ..writeln('- Generated at: `${generatedAt.toUtc().toIso8601String()}`')
      ..writeln('- Failure rate reduced: `$failureRateReduced`')
      ..writeln(
        '- Failure-rate delta: `${failureRateDelta.toStringAsFixed(3)}`',
      )
      ..writeln('- Pass-rate delta: `${passRateDelta.toStringAsFixed(3)}`')
      ..writeln()
      ..writeln('## Runs')
      ..writeln()
      ..writeln(_runMarkdown('Baseline', baseline))
      ..writeln()
      ..writeln(_runMarkdown('Current', current));
    return buffer.toString();
  }

  static String _runMarkdown(String label, Ll15CanaryRunSummary run) {
    return (StringBuffer()
          ..writeln('### $label')
          ..writeln()
          ..writeln('- Summary: `${run.summaryPath}`')
          ..writeln('- Log: `${run.logPath}`')
          ..writeln('- Result: `${run.result}`')
          ..writeln(
            '- Tests: `${run.passedCount}/${run.testCount}` passed, '
            '`${run.failedCount}` failed, `${run.skippedCount}` skipped',
          )
          ..writeln('- Pass rate: `${run.passRate.toStringAsFixed(3)}`')
          ..writeln('- LL15 snapshots: `${run.snapshotCount}`')
          ..writeln(
            '- Harness-prompted snapshots: `${run.harnessPromptedCount}`',
          )
          ..writeln('- edit_file attempts: `${run.attempts}`')
          ..writeln('- edit_file successes: `${run.successes}`')
          ..writeln('- edit_file failures: `${run.failures}`')
          ..writeln(
            '- edit_file failure rate: `${run.failureRate.toStringAsFixed(3)}`',
          )
          ..writeln('- edit_file tool calls: `${run.editToolCallCount}`')
          ..writeln('- write_file tool calls: `${run.writeToolCallCount}`')
          ..writeln(
            '- Failure classes: `${_formatFailureClassCounts(run.failureClassCounts)}`',
          )
          ..write(_failedTestsMarkdown(run.failedTests)))
        .toString()
        .trimRight();
  }

  static String _failedTestsMarkdown(List<Ll15CanaryFailedTest> failedTests) {
    if (failedTests.isEmpty) {
      return '';
    }
    final buffer = StringBuffer()
      ..writeln()
      ..writeln()
      ..writeln('| Failed test | Failure class | Preview |')
      ..writeln('|-------------|---------------|---------|');
    for (final failedTest in failedTests) {
      buffer.writeln(
        '| ${_tableCell(failedTest.name)} | '
        '`${failedTest.failureClass}` | '
        '${_tableCell(failedTest.failurePreview)} |',
      );
    }
    return buffer.toString().trimRight();
  }

  static String _formatFailureClassCounts(Map<String, int> counts) {
    if (counts.isEmpty) {
      return '(none)';
    }
    return counts.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(', ');
  }
}

class Ll15CanaryRunSummary {
  const Ll15CanaryRunSummary({
    required this.summaryPath,
    required this.logPath,
    required this.result,
    required this.runnerSuccess,
    required this.testCount,
    required this.passedCount,
    required this.failedCount,
    required this.skippedCount,
    required this.snapshotCount,
    required this.harnessPromptedCount,
    required this.attempts,
    required this.successes,
    required this.failures,
    required this.editToolCallCount,
    required this.writeToolCallCount,
    required this.failedTests,
  });

  final String summaryPath;
  final String logPath;
  final String result;
  final bool runnerSuccess;
  final int testCount;
  final int passedCount;
  final int failedCount;
  final int skippedCount;
  final int snapshotCount;
  final int harnessPromptedCount;
  final int attempts;
  final int successes;
  final int failures;
  final int editToolCallCount;
  final int writeToolCallCount;
  final List<Ll15CanaryFailedTest> failedTests;

  double get passRate => testCount == 0 ? 0 : passedCount / testCount;

  double get failureRate => attempts == 0 ? 0 : failures / attempts;

  Map<String, int> get failureClassCounts {
    final counts = <String, int>{};
    for (final failedTest in failedTests) {
      counts.update(
        failedTest.failureClass,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    return counts;
  }

  Map<String, dynamic> toJson() {
    return {
      'summaryPath': summaryPath,
      'logPath': logPath,
      'result': result,
      'runnerSuccess': runnerSuccess,
      'testCount': testCount,
      'passedCount': passedCount,
      'failedCount': failedCount,
      'skippedCount': skippedCount,
      'passRate': passRate,
      'snapshotCount': snapshotCount,
      'harnessPromptedCount': harnessPromptedCount,
      'editFile': {
        'attempts': attempts,
        'successes': successes,
        'failures': failures,
        'failureRate': failureRate,
        'toolCallCount': editToolCallCount,
      },
      'writeFile': {'toolCallCount': writeToolCallCount},
      'failureClasses': failureClassCounts,
      'failedTests': failedTests
          .map((failedTest) => failedTest.toJson())
          .toList(growable: false),
    };
  }
}

class Ll15CanaryFailedTest {
  const Ll15CanaryFailedTest({
    required this.name,
    required this.failureClass,
    required this.failurePreview,
  });

  final String name;
  final String failureClass;
  final String failurePreview;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'failureClass': failureClass,
      'failurePreview': failurePreview,
    };
  }
}

Future<Ll15EditHarnessMeasurementSummary> buildLl15EditHarnessMeasurement({
  required String baselineSummaryPath,
  required String currentSummaryPath,
  String? baselineLogPath,
  String? currentLogPath,
  DateTime? generatedAt,
}) async {
  final baseline = await loadLl15CanaryRunSummary(
    summaryPath: baselineSummaryPath,
    logPath: baselineLogPath,
  );
  final current = await loadLl15CanaryRunSummary(
    summaryPath: currentSummaryPath,
    logPath: currentLogPath,
  );
  return Ll15EditHarnessMeasurementSummary(
    generatedAt: generatedAt ?? DateTime.now(),
    baseline: baseline,
    current: current,
  );
}

Future<Ll15CanaryRunSummary> loadLl15CanaryRunSummary({
  required String summaryPath,
  String? logPath,
}) async {
  final summaryFile = File(summaryPath);
  final summaryJson =
      jsonDecode(await summaryFile.readAsString()) as Map<String, dynamic>;
  final resolvedLogPath = logPath ?? summaryJson['logPath'] as String? ?? '';
  final snapshots = resolvedLogPath.isEmpty
      ? const <Ll15EditHarnessSnapshot>[]
      : await loadLl15EditHarnessSnapshots(resolvedLogPath);
  final attempts = snapshots.fold<int>(0, (sum, item) => sum + item.attempts);
  final successes = snapshots.fold<int>(0, (sum, item) => sum + item.successes);
  final failures = snapshots.fold<int>(0, (sum, item) => sum + item.failures);
  final failedTests = _failedTestsFromSummary(summaryJson);

  return Ll15CanaryRunSummary(
    summaryPath: summaryFile.path,
    logPath: resolvedLogPath,
    result: _stringValue(summaryJson['result']),
    runnerSuccess: summaryJson['runnerSuccess'] == true,
    testCount: _intValue(summaryJson['testCount']),
    passedCount: _intValue(summaryJson['passedCount']),
    failedCount: _intValue(summaryJson['failedCount']),
    skippedCount: _intValue(summaryJson['skippedCount']),
    snapshotCount: snapshots.length,
    harnessPromptedCount: snapshots
        .where((snapshot) => snapshot.harnessPrompted)
        .length,
    attempts: attempts,
    successes: successes,
    failures: failures,
    editToolCallCount: snapshots.fold<int>(
      0,
      (sum, item) => sum + item.editToolCallCount,
    ),
    writeToolCallCount: snapshots.fold<int>(
      0,
      (sum, item) => sum + item.writeToolCallCount,
    ),
    failedTests: failedTests,
  );
}

List<Ll15CanaryFailedTest> _failedTestsFromSummary(
  Map<String, dynamic> summaryJson,
) {
  final tests = summaryJson['tests'];
  if (tests is! List) {
    return const <Ll15CanaryFailedTest>[];
  }
  final failedTests = <Ll15CanaryFailedTest>[];
  for (final item in tests) {
    if (item is! Map) {
      continue;
    }
    final test = Map<String, dynamic>.from(item);
    final failureMessage = _stringValue(test['failureMessage']);
    if (test['result'] != 'failed' && failureMessage.isEmpty) {
      continue;
    }
    final name = _stringValue(test['name']);
    failedTests.add(
      Ll15CanaryFailedTest(
        name: name.isEmpty ? '(unnamed test)' : name,
        failureClass: _classifyFailure(failureMessage),
        failurePreview: _failurePreview(failureMessage),
      ),
    );
  }
  return failedTests;
}

String _classifyFailure(String message) {
  final normalized = message.toLowerCase();
  if (normalized.contains('lateinitializationerror') ||
      normalized.contains('has not been initialized')) {
    return 'harness_error';
  }
  if (normalized.contains('old_text was not found') ||
      normalized.contains('matched multiple locations') ||
      normalized.contains('old_text must not be empty') ||
      normalized.contains('path is required')) {
    return 'edit_apply';
  }
  if (normalized.contains('a value greater than or equal to <1>') ||
      normalized.contains('a value greater than or equal to <2>')) {
    return 'verification_missing';
  }
  if (_hasNoMutationToolCall(normalized)) {
    return 'no_edit';
  }
  if (normalized.contains('revert --no-edit head') ||
      normalized.contains('successfulgitcommands')) {
    return 'git_lifecycle_incomplete';
  }
  if (normalized.contains('conversationgoalstatus.active')) {
    return 'completion_missing';
  }
  if (normalized.contains('does not contain') ||
      normalized.contains('expected:')) {
    return 'output_mismatch';
  }
  return 'unknown';
}

bool _hasNoMutationToolCall(String normalizedFailureMessage) {
  if (!normalizedFailureMessage.contains('toolcalls=')) {
    return false;
  }
  return !normalizedFailureMessage.contains('"name":"edit_file"') &&
      !normalizedFailureMessage.contains('"name":"write_file"');
}

String _failurePreview(String message) {
  final collapsed = message
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (collapsed.length <= 220) {
    return collapsed;
  }
  return '${collapsed.substring(0, 217)}...';
}

class Ll15EditHarnessSnapshot {
  const Ll15EditHarnessSnapshot({
    required this.harnessPrompted,
    required this.attempts,
    required this.successes,
    required this.failures,
    required this.editToolCallCount,
    required this.writeToolCallCount,
  });

  final bool harnessPrompted;
  final int attempts;
  final int successes;
  final int failures;
  final int editToolCallCount;
  final int writeToolCallCount;

  factory Ll15EditHarnessSnapshot.fromJson(Map<String, dynamic> json) {
    return Ll15EditHarnessSnapshot(
      harnessPrompted: json['harnessPrompted'] == true,
      attempts: _intValue(json['attempts']),
      successes: _intValue(json['successes']),
      failures: _intValue(json['failures']),
      editToolCallCount: _intValue(json['editToolCallCount']),
      writeToolCallCount: _intValue(json['writeToolCallCount']),
    );
  }
}

Future<List<Ll15EditHarnessSnapshot>> loadLl15EditHarnessSnapshots(
  String logPath,
) async {
  final file = File(logPath);
  if (!file.existsSync()) {
    return const <Ll15EditHarnessSnapshot>[];
  }
  final snapshots = <Ll15EditHarnessSnapshot>[];
  await for (final line
      in file
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    final message = _printedMessage(line);
    if (message == null) continue;
    final payload = _snapshotPayload(message);
    if (payload == null) continue;
    snapshots.add(Ll15EditHarnessSnapshot.fromJson(payload));
  }
  return snapshots;
}

Map<String, dynamic>? _snapshotPayload(String message) {
  const prefix = '[LL15] edit_harness_snapshot ';
  final index = message.indexOf(prefix);
  if (index == -1) {
    return null;
  }
  final raw = message.substring(index + prefix.length).trim();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    if (decoded['schemaName'] != 'll15_edit_harness_canary_snapshot') {
      return null;
    }
    return decoded;
  } catch (_) {
    return null;
  }
}

String? _printedMessage(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map<String, dynamic>) {
      if (decoded['type'] == 'print') {
        return decoded['message'] as String?;
      }
      return null;
    }
  } catch (_) {
    return line;
  }
  return line;
}

String _stringValue(Object? value) => value is String ? value : '';

String _tableCell(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', '<br>');
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
