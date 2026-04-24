import 'plan_mode_report_summary.dart';

class PlanModeSuiteReportConfig {
  const PlanModeSuiteReportConfig({
    required this.generatedAt,
    required this.suiteName,
    required this.modeName,
    required this.failOnWarnings,
    required this.requestedScenarioNames,
    required this.requestedTags,
    required this.suiteDirectoryPath,
    this.model,
    this.baseUrl,
  });

  final DateTime generatedAt;
  final String suiteName;
  final String modeName;
  final bool failOnWarnings;
  final List<String> requestedScenarioNames;
  final List<String> requestedTags;
  final String suiteDirectoryPath;
  final String? model;
  final String? baseUrl;
}

Map<String, Object?> buildPlanModeSuiteJsonReport({
  required PlanModeSuiteReportConfig config,
  required List<Map<String, Object?>> suiteResults,
}) {
  final outcomeSummary = buildPlanModeSuiteOutcomeSummary(suiteResults);
  return <String, Object?>{
    'generatedAt': config.generatedAt.toIso8601String(),
    'suite': config.suiteName,
    'mode': config.modeName,
    'requestedScenarioNames': config.requestedScenarioNames,
    'requestedTags': config.requestedTags,
    'suiteDirectory': config.suiteDirectoryPath,
    'model': config.model,
    'baseUrl': config.baseUrl,
    'failOnWarnings': config.failOnWarnings,
    'scenarioCount': suiteResults.length,
    'passedCount': outcomeSummary['passed'],
    'failedCount': outcomeSummary['failed'],
    'outcomeSummary': outcomeSummary,
    'warningSummary': buildPlanModeSuiteWarningSummary(suiteResults),
    'taskDriftSummary': buildPlanModeSuiteTaskDriftSummary(suiteResults),
    'toolLoopConvergenceSummary': buildPlanModeSuiteToolLoopConvergenceSummary(
      suiteResults,
    ),
    'executionPathSummary': buildPlanModeSuiteExecutionPathSummary(
      suiteResults,
    ),
    'scenarios': suiteResults,
  };
}

String buildPlanModeSuiteJUnitReport({
  required PlanModeSuiteReportConfig config,
  required List<Map<String, Object?>> suiteResults,
}) {
  final failureCount = suiteResults
      .where((result) => result['status'] != 'passed')
      .length;
  final totalDurationSeconds = suiteResults.fold<num>(
    0,
    (sum, result) => sum + ((result['durationMs'] as int? ?? 0) / 1000),
  );

  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<testsuites tests="${suiteResults.length}" '
      'failures="$failureCount" '
      'time="${totalDurationSeconds.toStringAsFixed(3)}">',
    )
    ..writeln(
      '  <testsuite name="${_xmlEscape(config.suiteName)}" '
      'tests="${suiteResults.length}" '
      'failures="$failureCount" '
      'time="${totalDurationSeconds.toStringAsFixed(3)}">',
    );

  for (final result in suiteResults) {
    final scenarioName = (result['scenario'] as String?) ?? 'unknown';
    final durationSeconds = ((result['durationMs'] as int? ?? 0) / 1000)
        .toStringAsFixed(3);
    final warnings = _asList(result['warnings']);
    final allowedWarnings = _asList(result['allowedWarnings']);
    final unexpectedWarnings = _asList(result['unexpectedWarnings']);
    final reportPath = result['scenarioReport'] as String?;
    final logPath = result['scenarioLog'] as String?;
    final failureClass = (result['failureClass'] as String?) ?? 'passed';
    final budgetPhase = (result['budgetPhase'] as String?) ?? '-';
    final taskDrift = _asObjectMap(result['taskDrift']);
    final taskDriftDetected =
        taskDrift['driftDetected'] == true ||
        result['taskDriftDetected'] == true;
    final taskDriftReason = (taskDrift['driftReason'] as String?) ?? 'none';
    final taskDriftSource = (taskDrift['fallbackSource'] as String?) ?? 'none';
    final toolLoopConvergence = _asObjectMap(result['toolLoopConvergence']);
    final toolLoopConvergenceDetected = toolLoopConvergence['detected'] == true;
    final toolLoopConvergenceStatus =
        (toolLoopConvergence['status'] as String?) ?? 'not_observed';
    final toolLoopSuccessfulValidations = _asInt(
      toolLoopConvergence['successfulValidations'],
    );
    final toolLoopGuardActivations = _asInt(
      toolLoopConvergence['guardActivations'],
    );
    final toolLoopNaturalStops = _asInt(toolLoopConvergence['naturalStops']);
    final approvalPath =
        (result['approvalPath'] as String?) ?? planModeApprovalPathUnknown;
    final fallbackPath =
        (result['fallbackPath'] as String?) ??
        fallbackPathForApprovalPath(approvalPath);
    final postScenarioSettled = result['postScenarioSettled'];
    final postScenarioCancellationUsed = result['postScenarioCancellationUsed'];
    buffer.writeln(
      '    <testcase classname="${_xmlEscape(config.suiteName)}" '
      'name="${_xmlEscape(scenarioName)}" '
      'time="$durationSeconds">',
    );
    if (result['status'] != 'passed') {
      final message = (result['error'] as String?) ?? 'Scenario failed';
      final stackTrace = (result['stackTrace'] as String?) ?? '';
      buffer.writeln(
        '      <failure message="${_xmlEscape(message)}">'
        '${_xmlEscape(stackTrace)}'
        '</failure>',
      );
    }
    final systemOut = <String>[
      if (reportPath != null) 'report=$reportPath',
      if (logPath != null) 'log=$logPath',
      'failureClass=$failureClass',
      'budgetPhase=$budgetPhase',
      'approvalPath=$approvalPath',
      'fallbackPath=$fallbackPath',
      if (postScenarioSettled != null)
        'postScenarioSettled=$postScenarioSettled',
      if (postScenarioCancellationUsed != null)
        'postScenarioCancellationUsed=$postScenarioCancellationUsed',
      'taskDriftDetected=$taskDriftDetected',
      'taskDriftReason=$taskDriftReason',
      'taskDriftSource=$taskDriftSource',
      'toolLoopConvergenceDetected=$toolLoopConvergenceDetected',
      'toolLoopConvergenceStatus=$toolLoopConvergenceStatus',
      'toolLoopConvergenceSuccessfulValidations=$toolLoopSuccessfulValidations',
      'toolLoopConvergenceGuardActivations=$toolLoopGuardActivations',
      'toolLoopConvergenceNaturalStops=$toolLoopNaturalStops',
      'warnings=${warnings.length}',
      'allowedWarnings=${allowedWarnings.length}',
      'unexpectedWarnings=${unexpectedWarnings.length}',
      if (warnings.isNotEmpty) ...warnings.map((warning) => 'warning=$warning'),
      if (allowedWarnings.isNotEmpty)
        ...allowedWarnings.map((warning) => 'allowedWarning=$warning'),
      if (unexpectedWarnings.isNotEmpty)
        ...unexpectedWarnings.map((warning) => 'unexpectedWarning=$warning'),
    ].join('\n');
    if (systemOut.isNotEmpty) {
      buffer.writeln('      <system-out>${_xmlEscape(systemOut)}</system-out>');
    }
    buffer.writeln('    </testcase>');
  }

  buffer
    ..writeln('  </testsuite>')
    ..writeln('</testsuites>');
  return buffer.toString();
}

String buildPlanModeSuiteMarkdownReport({
  required PlanModeSuiteReportConfig config,
  required List<Map<String, Object?>> suiteResults,
}) {
  final outcomeSummary = buildPlanModeSuiteOutcomeSummary(suiteResults);
  final warningSummary = buildPlanModeSuiteWarningSummary(suiteResults);
  final taskDriftSummary = buildPlanModeSuiteTaskDriftSummary(suiteResults);
  final toolLoopConvergenceSummary =
      buildPlanModeSuiteToolLoopConvergenceSummary(suiteResults);
  final executionPathSummary = buildPlanModeSuiteExecutionPathSummary(
    suiteResults,
  );
  final failureClassCounts = <String, int>{};
  for (final result in suiteResults) {
    final failureClass = (result['failureClass'] as String?) ?? 'passed';
    failureClassCounts.update(
      failureClass,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  final buffer = StringBuffer()
    ..writeln('# Plan Mode Scenario Suite')
    ..writeln()
    ..writeln('- Generated at: ${config.generatedAt.toIso8601String()}')
    ..writeln('- Suite: ${config.suiteName}')
    ..writeln('- Mode: ${config.modeName}')
    ..writeln('- Fail on warnings: ${config.failOnWarnings}')
    ..writeln(
      '- Scenario filter: ${_formatFilter(config.requestedScenarioNames)}',
    )
    ..writeln('- Tag filter: ${_formatFilter(config.requestedTags)}')
    ..writeln('- Suite directory: ${config.suiteDirectoryPath}')
    ..writeln(
      '- Model: ${config.model?.isNotEmpty == true ? config.model : 'default'}',
    );
  if (config.baseUrl?.isNotEmpty == true) {
    buffer.writeln('- Base URL: ${config.baseUrl}');
  }
  buffer
    ..writeln('- Scenario count: ${suiteResults.length}')
    ..writeln('- Passed: ${outcomeSummary['passed']}')
    ..writeln('- Failed: ${outcomeSummary['failed']}')
    ..writeln(
      '- Warnings: ${warningSummary['warnings']} total, '
      '${warningSummary['allowedWarnings']} allowed, '
      '${warningSummary['unexpectedWarnings']} unexpected',
    )
    ..writeln('- Task drift: ${taskDriftSummary['detected']} detected')
    ..writeln(
      '- Tool-loop convergence: '
      '${toolLoopConvergenceSummary['successfulValidations']} validation(s), '
      '${toolLoopConvergenceSummary['guardActivations']} activation(s) '
      'and ${toolLoopConvergenceSummary['naturalStops']} natural stop(s) '
      'across ${toolLoopConvergenceSummary['detected']} scenario(s)',
    )
    ..writeln(
      '- Approval paths: ${executionPathSummary['uiApproval']} UI, '
      '${executionPathSummary['liveHarnessApprovalFallback']} live harness fallback, '
      '${executionPathSummary['unknown']} unknown',
    )
    ..writeln()
    ..writeln(
      '| Scenario | Tags | Status | Failure Class | Budget Phase | Approval Path | Fallback Path | Post Settled | Cleanup Cancel | Duration (ms) | Warnings | Allowed | Unexpected | Screenshots | Report | Log | Error |',
    )
    ..writeln(
      '| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |',
    );

  for (final result in suiteResults) {
    final screenshots = _asList(result['screenshots']);
    final warnings = _asList(result['warnings']);
    final allowedWarnings = _asList(result['allowedWarnings']);
    final unexpectedWarnings = _asList(result['unexpectedWarnings']);
    final tags = _asList(result['tags']);
    final failureClass = (result['failureClass'] as String?) ?? 'passed';
    final budgetPhase = (result['budgetPhase'] as String?) ?? '-';
    final approvalPath =
        (result['approvalPath'] as String?) ?? planModeApprovalPathUnknown;
    final fallbackPath =
        (result['fallbackPath'] as String?) ??
        fallbackPathForApprovalPath(approvalPath);
    final postScenarioSettled =
        result['postScenarioSettled']?.toString() ?? '-';
    final postScenarioCancellationUsed =
        result['postScenarioCancellationUsed']?.toString() ?? '-';
    final error = (result['error'] as String?)?.replaceAll('\n', ' ') ?? '';
    buffer.writeln(
      '| ${_markdownTableCell(result['scenario'])} | '
      '${_markdownTableCell(tags.isEmpty ? '-' : tags.join(', '))} | '
      '${_markdownTableCell(result['status'])} | '
      '${_markdownTableCell(failureClass)} | '
      '${_markdownTableCell(budgetPhase)} | '
      '${_markdownTableCell(approvalPath)} | '
      '${_markdownTableCell(fallbackPath)} | '
      '${_markdownTableCell(postScenarioSettled)} | '
      '${_markdownTableCell(postScenarioCancellationUsed)} | '
      '${_markdownTableCell(result['durationMs'])} | '
      '${warnings.length} | ${allowedWarnings.length} | '
      '${unexpectedWarnings.length} | ${screenshots.length} | '
      '${_markdownArtifactLink(result['scenarioReport'], 'report')} | '
      '${_markdownArtifactLink(result['scenarioLog'], 'log')} | '
      '${_markdownTableCell(error.isEmpty ? '-' : error)} |',
    );
  }

  if (failureClassCounts.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Failure Classes')
      ..writeln();
    for (final entry in failureClassCounts.entries) {
      buffer.writeln('- ${entry.key}: ${entry.value}');
    }
  }

  final taskDriftScenarios = _asList(taskDriftSummary['scenarios']);
  if (taskDriftScenarios.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Task Drift')
      ..writeln();
    for (final item in taskDriftScenarios) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      buffer.writeln(
        '- ${item['scenario']}: ${item['driftReason']} '
        '(${item['fallbackSource']}) '
        'expected=${_formatInlineList(item['expectedTargetFiles'])}; '
        'saved=${_formatInlineList(item['savedTaskTargetFiles'])}; '
        'actual=${_formatInlineList(item['actualChangedFiles'])} '
        '${_markdownArtifactLink(item['report'], 'report')}',
      );
    }
  }

  final convergenceScenarios = _asList(toolLoopConvergenceSummary['scenarios']);
  if (convergenceScenarios.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Tool-Loop Convergence')
      ..writeln();
    for (final item in convergenceScenarios) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      buffer.writeln(
        '- ${item['scenario']}: '
        '${item['successfulValidations']} validation(s), '
        '${item['guardActivations']} guard activation(s), '
        '${item['naturalStops']} natural stop(s), '
        'status `${item['status'] ?? 'unknown'}` '
        '${_markdownArtifactLink(item['report'], 'report')} '
        '${_markdownArtifactLink(item['log'], 'log')}',
      );
    }
  }

  _writeWarningSection(
    buffer,
    title: 'Warnings',
    suiteResults: suiteResults,
    key: 'warnings',
  );
  _writeWarningSection(
    buffer,
    title: 'Unexpected Warnings',
    suiteResults: suiteResults,
    key: 'unexpectedWarnings',
  );
  _writeWarningSection(
    buffer,
    title: 'Allowed Warnings',
    suiteResults: suiteResults,
    key: 'allowedWarnings',
  );

  final fallbackScenarios = _asList(executionPathSummary['fallbackScenarios']);
  if (fallbackScenarios.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('## Live Harness Fallback Paths')
      ..writeln();
    for (final item in fallbackScenarios) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      buffer.writeln(
        '- ${item['scenario']}: ${item['fallbackPath']} '
        '(${_markdownArtifactLink(item['report'], 'report')})',
      );
    }
  }

  return buffer.toString();
}

void _writeWarningSection(
  StringBuffer buffer, {
  required String title,
  required List<Map<String, Object?>> suiteResults,
  required String key,
}) {
  final scenarios = suiteResults
      .where((result) => _asList(result[key]).isNotEmpty)
      .toList(growable: false);
  if (scenarios.isEmpty) {
    return;
  }

  buffer
    ..writeln()
    ..writeln('## $title')
    ..writeln();
  for (final result in scenarios) {
    final warnings = _asList(result[key]);
    buffer.writeln('### ${result['scenario']}');
    for (final warning in warnings) {
      buffer.writeln('- $warning');
    }
    buffer.writeln();
  }
}

String _formatFilter(List<String> values) {
  return values.isEmpty ? 'all' : values.join(', ');
}

String _markdownArtifactLink(Object? value, String label) {
  final path = value?.toString().trim();
  if (path == null || path.isEmpty) {
    return '-';
  }
  return '[$label](<${path.replaceAll('>', '%3E')}>)';
}

String _markdownTableCell(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return '-';
  }
  return text.replaceAll('\n', ' ').replaceAll('|', r'\|');
}

String _xmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

List<Object?> _asList(Object? value) {
  return value is List ? value.cast<Object?>() : const <Object?>[];
}

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return const <String, Object?>{};
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return 0;
}

String _formatInlineList(Object? value) {
  final items = _asList(value).map((item) => item.toString()).toList();
  if (items.isEmpty) {
    return '-';
  }
  return items.join(',');
}
