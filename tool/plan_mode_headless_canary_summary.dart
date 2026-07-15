import 'dart:convert';
import 'dart:io';

Map<String, Object?> buildPlanModeHeadlessCanarySummary({
  required Map<String, dynamic> suiteReport,
  required Map<String, dynamic> scenarioReport,
  required List<String> sessionLogPaths,
  required DateTime generatedAt,
}) {
  final scenarios = (suiteReport['scenarios'] as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
  if (scenarios.length != 1) {
    throw StateError(
      'Headless canary summary requires exactly one suite scenario.',
    );
  }

  final scenario = scenarios.single;
  final capturedLogs =
      (scenarioReport['capturedLogs'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false);
  final quality = Map<String, dynamic>.from(
    suiteReport['reportQualitySummary'] as Map? ?? const <String, dynamic>{},
  );
  final toolLifecycle = Map<String, dynamic>.from(
    scenarioReport['toolLifecycle'] as Map? ?? const <String, dynamic>{},
  );
  final convergence = Map<String, dynamic>.from(
    scenarioReport['toolLoopConvergence'] as Map? ?? const <String, dynamic>{},
  );
  final budgets = Map<String, dynamic>.from(
    scenarioReport['budgets'] as Map? ?? const <String, dynamic>{},
  );
  final approvalPath = scenarioReport['approvalPath']?.toString() ?? 'none';
  final usedHarnessApprovalFallback =
      scenarioReport['usedHarnessApprovalFallback'] == true;
  final sortedSessionLogs = [...sessionLogPaths]..sort();

  return <String, Object?>{
    'schema': 'caverno_plan_mode_headless_canary_summary',
    'schemaVersion': 1,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'surface': 'plan_mode_headless',
    'baseUrl': suiteReport['baseUrl'],
    'model': suiteReport['model'],
    'scenario': scenario['scenario'],
    'status': scenario['status'],
    'startedAt': scenario['startedAt'],
    'finishedAt': scenario['finishedAt'],
    'durationMs': scenario['durationMs'],
    'executionTimeoutMs': budgets['executionTimeoutMs'],
    'overallTimeoutMs': budgets['overallTimeoutMs'],
    'reportQualityReady': quality['ready'] == true,
    'reportQualityBlockerCount': quality['blockerCount'] ?? 0,
    'taskDriftDetected': scenario['taskDriftDetected'] == true,
    'toolLoopCount': _countContaining(capturedLogs, '[Tool] Tool loop ['),
    'toolCallCount': toolLifecycle['toolCallCount'] ?? 0,
    'toolFailureCount': toolLifecycle['failedCount'] ?? 0,
    'successfulValidationCount': convergence['successfulValidations'] ?? 0,
    'recoveryCount': _countContaining(capturedLogs, 'tool-less recovery'),
    'approvalDecisionCount': usedHarnessApprovalFallback ? 1 : 0,
    'approvalPath': approvalPath,
    'usedHarnessApprovalFallback': usedHarnessApprovalFallback,
    'screenshotCount':
        (scenarioReport['screenshots'] as List<dynamic>? ?? const []).length,
    'appOpenMarkerCount': _countAnyContaining(capturedLogs, const <String>[
      'Caverno.app',
      'Foregrounding Caverno',
      'Opening Caverno',
    ]),
    'sessionLogPaths': sortedSessionLogs,
  };
}

int _countContaining(List<String> lines, String pattern) {
  return lines.where((line) => line.contains(pattern)).length;
}

int _countAnyContaining(List<String> lines, List<String> patterns) {
  return lines
      .where((line) => patterns.any((pattern) => line.contains(pattern)))
      .length;
}

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseOptions(arguments);
    final suiteReportFile = File(_requiredOption(options, 'suite-report'));
    final sessionLogRoot = Directory(
      _requiredOption(options, 'session-log-root'),
    );
    final outputFile = File(_requiredOption(options, 'out'));

    final suiteReport = Map<String, dynamic>.from(
      jsonDecode(await suiteReportFile.readAsString()) as Map,
    );
    final scenarios = (suiteReport['scenarios'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    if (scenarios.length != 1) {
      throw StateError(
        'Headless canary summary requires exactly one suite scenario.',
      );
    }

    final scenarioReportPath = scenarios.single['scenarioReport']?.toString();
    if (scenarioReportPath == null || scenarioReportPath.trim().isEmpty) {
      throw StateError('Suite scenario is missing scenarioReport.');
    }
    final scenarioReport = Map<String, dynamic>.from(
      jsonDecode(await File(scenarioReportPath).readAsString()) as Map,
    );
    final sessionLogPaths = sessionLogRoot.existsSync()
        ? sessionLogRoot
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.jsonl'))
              .map((file) => file.absolute.path)
              .toList(growable: false)
        : <String>[];
    if (sessionLogPaths.isEmpty) {
      throw StateError('Headless canary did not produce a session log.');
    }

    final summary = buildPlanModeHeadlessCanarySummary(
      suiteReport: suiteReport,
      scenarioReport: scenarioReport,
      sessionLogPaths: sessionLogPaths,
      generatedAt: DateTime.now(),
    );
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(summary)}\n',
    );
    stdout.writeln('Headless canary summary written to ${outputFile.path}');
  } catch (error) {
    stderr.writeln('Failed to build headless canary summary: $error');
    exitCode = 1;
  }
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
