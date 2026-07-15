import 'dart:convert';
import 'dart:io';

Map<String, Object?> buildPlanModeCli0ComparisonSummary({
  required List<Map<String, dynamic>> headlessSummaries,
  required Map<String, dynamic> macosSuiteReport,
  required Map<String, dynamic> macosScenarioReport,
  required List<String> macosSessionLogPaths,
  required int expectedHeadlessCount,
  required String macosSuiteReportPath,
  required DateTime generatedAt,
}) {
  if (expectedHeadlessCount < 1) {
    throw ArgumentError.value(
      expectedHeadlessCount,
      'expectedHeadlessCount',
      'Expected headless count must be positive.',
    );
  }

  final macosScenarios =
      (macosSuiteReport['scenarios'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
  if (macosScenarios.length != 1) {
    throw StateError(
      'CLI0 comparison requires exactly one macOS suite scenario.',
    );
  }

  final macosScenario = macosScenarios.single;
  final quality = Map<String, dynamic>.from(
    macosSuiteReport['reportQualitySummary'] as Map? ??
        const <String, dynamic>{},
  );
  final capturedLogs =
      (macosScenarioReport['capturedLogs'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false);
  final macosToolLifecycle = Map<String, dynamic>.from(
    macosScenarioReport['toolLifecycle'] as Map? ?? const <String, dynamic>{},
  );
  final macosConvergence = Map<String, dynamic>.from(
    macosScenarioReport['toolLoopConvergence'] as Map? ??
        const <String, dynamic>{},
  );
  final macosBudgets = Map<String, dynamic>.from(
    macosScenarioReport['budgets'] as Map? ?? const <String, dynamic>{},
  );

  final sortedHeadless = [...headlessSummaries]
    ..sort(
      (left, right) =>
          _string(left['startedAt']).compareTo(_string(right['startedAt'])),
    );
  final headlessRuns = sortedHeadless
      .map(
        (summary) => <String, Object?>{
          'summaryPath': summary['summaryPath'],
          'status': summary['status'],
          'startedAt': summary['startedAt'],
          'finishedAt': summary['finishedAt'],
          'durationMs': _integer(summary['durationMs']),
          'executionTimeoutMs': _integer(summary['executionTimeoutMs']),
          'overallTimeoutMs': _integer(summary['overallTimeoutMs']),
          'toolLoopCount': _integer(summary['toolLoopCount']),
          'toolCallCount': _integer(summary['toolCallCount']),
          'toolFailureCount': _integer(summary['toolFailureCount']),
          'successfulValidationCount': _integer(
            summary['successfulValidationCount'],
          ),
          'recoveryCount': _integer(summary['recoveryCount']),
          'approvalDecisionCount': _integer(summary['approvalDecisionCount']),
          'approvalPath': summary['approvalPath'],
          'taskDriftDetected': summary['taskDriftDetected'] == true,
          'reportQualityReady': summary['reportQualityReady'] == true,
          'reportQualityBlockerCount': _integer(
            summary['reportQualityBlockerCount'],
          ),
          'screenshotCount': _integer(summary['screenshotCount']),
          'appOpenMarkerCount': _integer(summary['appOpenMarkerCount']),
          'sessionLogPaths': _sortedStrings(summary['sessionLogPaths']),
        },
      )
      .toList(growable: false);
  final durations = sortedHeadless
      .map((summary) => _integer(summary['durationMs']))
      .toList(growable: false);
  final headlessSessionLogs =
      sortedHeadless
          .expand((summary) => _sortedStrings(summary['sessionLogPaths']))
          .toSet()
          .toList()
        ..sort();

  final macosScreenshots =
      (macosScenarioReport['screenshots'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false);
  final sortedMacosSessionLogs = [...macosSessionLogPaths]..sort();
  final macosUsedFallback =
      macosScenarioReport['usedHarnessApprovalFallback'] == true;
  final macosApprovalPath =
      macosScenarioReport['approvalPath']?.toString() ?? 'none';

  final failureReasons = <String>[];
  if (sortedHeadless.length != expectedHeadlessCount) {
    failureReasons.add('headless_run_count_mismatch');
  }
  if (sortedHeadless.any((summary) => summary['status'] != 'passed')) {
    failureReasons.add('headless_run_failed');
  }
  if (macosScenario['status'] != 'passed') {
    failureReasons.add('macos_run_failed');
  }
  if (sortedHeadless.any(
    (summary) =>
        summary['reportQualityReady'] != true ||
        _integer(summary['reportQualityBlockerCount']) != 0,
  )) {
    failureReasons.add('headless_report_quality_blocked');
  }
  if (quality['ready'] != true || _integer(quality['blockerCount']) != 0) {
    failureReasons.add('macos_report_quality_blocked');
  }
  if (sortedHeadless.any((summary) => summary['taskDriftDetected'] == true) ||
      macosScenario['taskDriftDetected'] == true) {
    failureReasons.add('task_drift_detected');
  }

  final macosScenarioName = _string(macosScenario['scenario']);
  final headlessScenarioNames = sortedHeadless
      .map((summary) => _string(summary['scenario']))
      .toSet();
  if (macosScenarioName.isEmpty ||
      headlessScenarioNames.length != 1 ||
      !headlessScenarioNames.contains(macosScenarioName)) {
    failureReasons.add('scenario_mismatch');
  }

  final macosModel = _string(macosSuiteReport['model']);
  final headlessModels = sortedHeadless
      .map((summary) => _string(summary['model']))
      .toSet();
  if (macosModel.isEmpty ||
      headlessModels.length != 1 ||
      !headlessModels.contains(macosModel)) {
    failureReasons.add('model_mismatch');
  }

  final macosBaseUrl = _string(macosSuiteReport['baseUrl']);
  final headlessBaseUrls = sortedHeadless
      .map((summary) => _string(summary['baseUrl']))
      .toSet();
  if (macosBaseUrl.isEmpty ||
      headlessBaseUrls.length != 1 ||
      !headlessBaseUrls.contains(macosBaseUrl)) {
    failureReasons.add('base_url_mismatch');
  }
  if (headlessSessionLogs.length < sortedHeadless.length) {
    failureReasons.add('headless_session_log_missing');
  }
  if (sortedMacosSessionLogs.isEmpty) {
    failureReasons.add('macos_session_log_missing');
  }
  final headlessExecutionTimeouts = sortedHeadless
      .map((summary) => _integer(summary['executionTimeoutMs']))
      .toSet();
  final headlessOverallTimeouts = sortedHeadless
      .map((summary) => _integer(summary['overallTimeoutMs']))
      .toSet();
  final macosExecutionTimeoutMs = _integer(macosBudgets['executionTimeoutMs']);
  final macosOverallTimeoutMs = _integer(macosBudgets['overallTimeoutMs']);
  if (macosExecutionTimeoutMs < 1 ||
      macosOverallTimeoutMs < 1 ||
      headlessExecutionTimeouts.length != 1 ||
      headlessOverallTimeouts.length != 1 ||
      !headlessExecutionTimeouts.contains(macosExecutionTimeoutMs) ||
      !headlessOverallTimeouts.contains(macosOverallTimeoutMs)) {
    failureReasons.add('budget_mismatch');
  }

  return <String, Object?>{
    'schema': 'caverno_plan_mode_cli0_comparison_summary',
    'schemaVersion': 1,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'status': failureReasons.isEmpty ? 'passed' : 'failed',
    'failureReasons': failureReasons,
    'scenario': macosScenarioName,
    'model': macosModel,
    'baseUrl': macosBaseUrl,
    'headless': <String, Object?>{
      'surface': 'plan_mode_headless',
      'expectedRunCount': expectedHeadlessCount,
      'runCount': sortedHeadless.length,
      'passedCount': sortedHeadless
          .where((summary) => summary['status'] == 'passed')
          .length,
      'passRate': sortedHeadless.isEmpty
          ? 0.0
          : sortedHeadless
                    .where((summary) => summary['status'] == 'passed')
                    .length /
                sortedHeadless.length,
      'durationMs': <String, Object?>{
        'values': durations,
        'minimum': durations.isEmpty ? 0 : durations.reduce(_minimum),
        'maximum': durations.isEmpty ? 0 : durations.reduce(_maximum),
        'average': durations.isEmpty
            ? 0
            : (durations.reduce((left, right) => left + right) /
                      durations.length)
                  .round(),
      },
      'executionTimeoutMs': headlessExecutionTimeouts.length == 1
          ? headlessExecutionTimeouts.single
          : 0,
      'overallTimeoutMs': headlessOverallTimeouts.length == 1
          ? headlessOverallTimeouts.single
          : 0,
      'toolLoopCount': _sum(sortedHeadless, 'toolLoopCount'),
      'toolCallCount': _sum(sortedHeadless, 'toolCallCount'),
      'toolFailureCount': _sum(sortedHeadless, 'toolFailureCount'),
      'successfulValidationCount': _sum(
        sortedHeadless,
        'successfulValidationCount',
      ),
      'recoveryCount': _sum(sortedHeadless, 'recoveryCount'),
      'approvalDecisionCount': _sum(sortedHeadless, 'approvalDecisionCount'),
      'approvalPathCounts': _countsByValue(sortedHeadless, 'approvalPath'),
      'taskDriftCount': sortedHeadless
          .where((summary) => summary['taskDriftDetected'] == true)
          .length,
      'reportQualityBlockerCount': _sum(
        sortedHeadless,
        'reportQualityBlockerCount',
      ),
      'screenshotCount': _sum(sortedHeadless, 'screenshotCount'),
      'appOpenMarkerCount': _sum(sortedHeadless, 'appOpenMarkerCount'),
      'sessionLogPaths': headlessSessionLogs,
      'runs': headlessRuns,
    },
    'macos': <String, Object?>{
      'surface': 'plan_mode_macos_app_path',
      'status': macosScenario['status'],
      'startedAt': macosScenario['startedAt'],
      'finishedAt': macosScenario['finishedAt'],
      'durationMs': _integer(macosScenario['durationMs']),
      'executionTimeoutMs': macosExecutionTimeoutMs,
      'overallTimeoutMs': macosOverallTimeoutMs,
      'toolLoopCount': _countContaining(capturedLogs, '[Tool] Tool loop ['),
      'toolCallCount': _integer(macosToolLifecycle['toolCallCount']),
      'toolFailureCount': _integer(macosToolLifecycle['failedCount']),
      'successfulValidationCount': _integer(
        macosConvergence['successfulValidations'],
      ),
      'recoveryCount': _countContaining(capturedLogs, 'tool-less recovery'),
      'approvalDecisionCount': macosUsedFallback ? 1 : 0,
      'approvalPath': macosApprovalPath,
      'usedHarnessApprovalFallback': macosUsedFallback,
      'taskDriftDetected': macosScenario['taskDriftDetected'] == true,
      'reportQualityReady': quality['ready'] == true,
      'reportQualityBlockerCount': _integer(quality['blockerCount']),
      'screenshotCount': macosScreenshots.length,
      'sessionLogPaths': sortedMacosSessionLogs,
      'suiteReportPath': macosSuiteReportPath,
      'scenarioReportPath': macosScenario['scenarioReport'],
    },
    'coverageBoundary': <String, Object?>{
      'shared': <String>[
        'scenario contract and exact prompt',
        'saved workflow execution and tool lifecycle',
        'post-validator and report quality',
        'session logging',
      ],
      'macosOnly': <String>[
        'application bootstrap',
        'proposal presentation',
        'approval rendering',
        'screenshot capture',
      ],
      'notCovered': <String>[
        'terminal TTY behavior',
        'terminal signal handling',
        'public CLI exit codes',
        'frontend-neutral runtime composition',
      ],
    },
  };
}

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseOptions(arguments);
    final headlessRoot = Directory(_requiredOption(options, 'headless-root'));
    final macosSuiteReportFile = File(
      _requiredOption(options, 'macos-suite-report'),
    );
    final macosSessionLogRoot = Directory(
      _requiredOption(options, 'macos-session-log-root'),
    );
    final outputFile = File(_requiredOption(options, 'out'));
    final expectedHeadlessCount = int.parse(
      _requiredOption(options, 'expected-headless-count'),
    );

    final headlessSummaryFiles = headlessRoot.existsSync()
        ? headlessRoot
              .listSync(recursive: true)
              .whereType<File>()
              .where(
                (file) => file.path.endsWith('headless_canary_summary.json'),
              )
              .toList(growable: false)
        : <File>[];
    final headlessSummaries = <Map<String, dynamic>>[];
    for (final file in headlessSummaryFiles) {
      final summary = Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      summary['summaryPath'] = file.absolute.path;
      headlessSummaries.add(summary);
    }

    final macosSuiteReport = Map<String, dynamic>.from(
      jsonDecode(await macosSuiteReportFile.readAsString()) as Map,
    );
    final scenarios =
        (macosSuiteReport['scenarios'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
    if (scenarios.length != 1) {
      throw StateError(
        'CLI0 comparison requires exactly one macOS suite scenario.',
      );
    }
    final scenarioReportPath = _string(scenarios.single['scenarioReport']);
    if (scenarioReportPath.isEmpty) {
      throw StateError('macOS suite scenario is missing scenarioReport.');
    }
    final macosScenarioReport = Map<String, dynamic>.from(
      jsonDecode(await File(scenarioReportPath).readAsString()) as Map,
    );
    final macosSessionLogPaths = macosSessionLogRoot.existsSync()
        ? macosSessionLogRoot
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.jsonl'))
              .map((file) => file.absolute.path)
              .toList(growable: false)
        : <String>[];

    final summary = buildPlanModeCli0ComparisonSummary(
      headlessSummaries: headlessSummaries,
      macosSuiteReport: macosSuiteReport,
      macosScenarioReport: macosScenarioReport,
      macosSessionLogPaths: macosSessionLogPaths,
      expectedHeadlessCount: expectedHeadlessCount,
      macosSuiteReportPath: macosSuiteReportFile.absolute.path,
      generatedAt: DateTime.now(),
    );
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(summary)}\n',
    );
    stdout.writeln('CLI0 comparison summary written to ${outputFile.path}');
    if (summary['status'] != 'passed') {
      stderr.writeln(
        'CLI0 comparison failed: '
        '${(summary['failureReasons'] as List<dynamic>).join(', ')}',
      );
      exitCode = 1;
    }
  } catch (error) {
    stderr.writeln('Failed to build CLI0 comparison summary: $error');
    exitCode = 1;
  }
}

int _sum(List<Map<String, dynamic>> values, String key) {
  return values.fold<int>(0, (total, value) => total + _integer(value[key]));
}

Map<String, int> _countsByValue(List<Map<String, dynamic>> values, String key) {
  final counts = <String, int>{};
  for (final value in values) {
    final label = _string(value[key]);
    counts[label] = (counts[label] ?? 0) + 1;
  }
  return Map<String, int>.fromEntries(
    counts.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key)),
  );
}

int _countContaining(List<String> lines, String pattern) {
  return lines.where((line) => line.contains(pattern)).length;
}

int _minimum(int left, int right) => left < right ? left : right;

int _maximum(int left, int right) => left > right ? left : right;

int _integer(Object? value) => value is num ? value.toInt() : 0;

String _string(Object? value) => value?.toString().trim() ?? '';

List<String> _sortedStrings(Object? value) {
  final values = (value as List<dynamic>? ?? const [])
      .map((item) => item.toString())
      .toList(growable: false);
  return [...values]..sort();
}

Map<String, String> _parseOptions(List<String> arguments) {
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    if (!argument.startsWith('--') || index + 1 >= arguments.length) {
      throw FormatException('Expected --name value arguments.');
    }
    options[argument.substring(2)] = arguments[index + 1];
    index += 1;
  }
  return options;
}

String _requiredOption(Map<String, String> options, String name) {
  final value = options[name]?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('Missing required --$name option.');
  }
  return value;
}
