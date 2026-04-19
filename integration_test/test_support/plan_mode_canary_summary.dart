import 'dart:convert';
import 'dart:io';

class PlanModeCanaryRunSummary {
  const PlanModeCanaryRunSummary({
    required this.name,
    required this.status,
    required this.failureClass,
    required this.durationMs,
    this.error,
    this.budgetPhase,
    this.lastKnownPhase,
    this.activeTaskTitle,
    this.lastUpdatedAt,
    this.phaseTimings = const <String, Object?>{},
    this.budgets = const <String, Object?>{},
    this.reportPath,
    this.logPath,
  });

  final String name;
  final String status;
  final String failureClass;
  final int durationMs;
  final String? error;
  final String? budgetPhase;
  final String? lastKnownPhase;
  final String? activeTaskTitle;
  final String? lastUpdatedAt;
  final Map<String, Object?> phaseTimings;
  final Map<String, Object?> budgets;
  final String? reportPath;
  final String? logPath;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'status': status,
      'failureClass': failureClass,
      'durationMs': durationMs,
      'error': error,
      'budgetPhase': budgetPhase,
      'lastKnownPhase': lastKnownPhase,
      'activeTaskTitle': activeTaskTitle,
      'lastUpdatedAt': lastUpdatedAt,
      'phaseTimings': phaseTimings,
      'budgets': budgets,
      'reportPath': reportPath,
      'logPath': logPath,
    };
  }
}

class PlanModeCanarySummary {
  const PlanModeCanarySummary({
    required this.runCount,
    required this.passedCount,
    required this.failedCount,
    required this.failureClassCounts,
    required this.runs,
  });

  final int runCount;
  final int passedCount;
  final int failedCount;
  final Map<String, int> failureClassCounts;
  final List<PlanModeCanaryRunSummary> runs;

  double get passRate => runCount == 0 ? 0 : passedCount / runCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'runCount': runCount,
      'passedCount': passedCount,
      'failedCount': failedCount,
      'passRate': passRate,
      'failureClassCounts': failureClassCounts,
      'runs': runs.map((run) => run.toJson()).toList(growable: false),
    };
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Plan Mode Live Canary Summary')
      ..writeln()
      ..writeln('- Run count: $runCount')
      ..writeln('- Passed: $passedCount')
      ..writeln('- Failed: $failedCount')
      ..writeln('- Pass rate: ${(passRate * 100).toStringAsFixed(1)}%')
      ..writeln()
      ..writeln(
        '| Run | Status | Failure Class | Budget Phase | Last Known Phase | Active Task | Duration (ms) | Error |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | ---: | --- |');

    for (final run in runs) {
      buffer.writeln(
        '| ${run.name} | ${run.status} | ${run.failureClass} | ${run.budgetPhase ?? '-'} | ${run.lastKnownPhase ?? '-'} | ${run.activeTaskTitle ?? '-'} | ${run.durationMs} | ${run.error ?? '-'} |',
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

    return buffer.toString();
  }
}

PlanModeCanarySummary buildPlanModeCanarySummary(
  List<Map<String, dynamic>> suiteReports,
) {
  final runs = <PlanModeCanaryRunSummary>[];
  final failureClassCounts = <String, int>{};

  for (final suiteReport in suiteReports) {
    final scenarios =
        (suiteReport['scenarios'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>();
    for (final scenario in scenarios) {
      final diagnostics =
          scenario['diagnostics'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final scenarioHeartbeat =
          scenario['lastHeartbeat'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final lastHeartbeat =
          diagnostics['lastHeartbeat'] as Map<String, dynamic>? ??
          scenarioHeartbeat;
      final logPath =
          scenario['scenarioLog'] as String? ??
          diagnostics['scenarioLog'] as String?;
      final recentLogTail =
          (diagnostics['recentLogTail'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toList(growable: false);
      final logLines = _readCanaryLogLines(
        logPath,
        fallbackTail: recentLogTail,
      );
      final heartbeatPhase =
          scenario['lastKnownPhase'] as String? ??
          lastHeartbeat['phase'] as String?;
      final heartbeatSubphase = lastHeartbeat['subphase'] as String?;
      final rawFailureClass =
          (scenario['failureClass'] as String?)?.trim().isNotEmpty == true
          ? scenario['failureClass'] as String
          : (scenario['status'] == 'passed' ? 'passed' : 'unclassified');
      final failureClass = _resolveLogAwareFailureClass(
        rawFailureClass,
        logLines,
      );
      failureClassCounts.update(
        failureClass,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      runs.add(
        PlanModeCanaryRunSummary(
          name: scenario['scenario'] as String? ?? 'unknown',
          status: scenario['status'] as String? ?? 'failed',
          failureClass: failureClass,
          durationMs: scenario['durationMs'] as int? ?? 0,
          error: scenario['error'] as String?,
          budgetPhase:
              scenario['budgetPhase'] as String? ??
              diagnostics['budgetPhase'] as String?,
          lastKnownPhase: _resolveLogAwarePhase(
            heartbeatPhase: heartbeatPhase,
            heartbeatSubphase: heartbeatSubphase,
            logLines: logLines,
          ),
          activeTaskTitle:
              scenario['activeTaskTitle'] as String? ??
              lastHeartbeat['activeTaskTitle'] as String? ??
              diagnostics['activeTaskTitle'] as String?,
          lastUpdatedAt:
              scenario['lastUpdatedAt'] as String? ??
              lastHeartbeat['updatedAt'] as String?,
          phaseTimings: Map<String, Object?>.from(
            scenario['phaseTimings'] as Map<String, dynamic>? ??
                lastHeartbeat['phaseTimings'] as Map<String, dynamic>? ??
                const <String, dynamic>{},
          ),
          budgets: Map<String, Object?>.from(
            scenario['budgets'] as Map<String, dynamic>? ??
                lastHeartbeat['budgets'] as Map<String, dynamic>? ??
                diagnostics['budgets'] as Map<String, dynamic>? ??
                const <String, dynamic>{},
          ),
          reportPath: scenario['scenarioReport'] as String?,
          logPath: logPath,
        ),
      );
    }
  }

  final passedCount = runs.where((run) => run.status == 'passed').length;
  return PlanModeCanarySummary(
    runCount: runs.length,
    passedCount: passedCount,
    failedCount: runs.length - passedCount,
    failureClassCounts: Map<String, int>.unmodifiable(failureClassCounts),
    runs: List<PlanModeCanaryRunSummary>.unmodifiable(runs),
  );
}

String _resolveLogAwareFailureClass(
  String failureClass,
  List<String> logLines,
) {
  if (failureClass != 'overallTimeout') {
    return failureClass;
  }
  final normalizedLines = logLines.map((line) => line.toLowerCase()).toList();
  if (normalizedLines.any(
    (line) =>
        line.contains('failed to foreground app; open returned 1') ||
        line.contains('[canaryrunner] stage=foregroundfailed'),
  )) {
    return 'appForegroundFailure';
  }
  if (normalizedLines.any(
    (line) => line.contains('[canaryrunner] stage=firstheartbeattimeout'),
  )) {
    return 'appLaunchTimeout';
  }
  return failureClass;
}

List<String> _readCanaryLogLines(
  String? logPath, {
  List<String> fallbackTail = const <String>[],
}) {
  if (logPath == null || logPath.isEmpty) {
    return fallbackTail;
  }
  final file = File(logPath);
  if (!file.existsSync()) {
    return fallbackTail;
  }
  final lines = file.readAsLinesSync();
  if (lines.isEmpty) {
    return fallbackTail;
  }
  return lines;
}

String? _resolveLogAwarePhase({
  required String? heartbeatPhase,
  required String? heartbeatSubphase,
  required List<String> logLines,
}) {
  final logPhase = _inferPhaseFromLogLines(logLines);
  if (heartbeatPhase == null || heartbeatPhase.isEmpty) {
    return logPhase;
  }
  final heartbeatLooksStale =
      heartbeatPhase == 'planning' &&
      (heartbeatSubphase == null || heartbeatSubphase == 'promptSubmitted');
  if (heartbeatLooksStale && logPhase != null) {
    return logPhase;
  }
  return heartbeatPhase;
}

String? _inferPhaseFromLogLines(List<String> logLines) {
  if (logLines.isEmpty) {
    return null;
  }
  final normalizedLines = logLines.map((line) => line.toLowerCase()).toList();
  final sawStartup = normalizedLines.any(
    (line) =>
        line.contains('building macos application') ||
        line.contains('✓ built ') ||
        line.contains('failed to foreground app; open returned 1') ||
        line.contains('[canaryrunner] stage=buildstarted') ||
        line.contains('[canaryrunner] stage=buildfinished') ||
        line.contains('[canaryrunner] stage=foregroundfailed') ||
        line.contains('[canaryrunner] stage=firstheartbeattimeout'),
  );
  if (sawStartup) {
    return 'startup';
  }
  final sawExecution = normalizedLines.any(
    (line) =>
        line.contains('[contenttool]') ||
        line.contains('[tool] llm requested additional tool calls') ||
        line.contains('[chatnotifier] waiting for pending tool executions') ||
        line.contains('approve and start'),
  );
  if (sawExecution) {
    return 'execution';
  }
  final sawPlanning = normalizedLines.any(
    (line) =>
        line.contains('[workflow]') ||
        line.contains('pendingdecision') ||
        line.contains('task proposal') ||
        line.contains('workflow proposal'),
  );
  if (sawPlanning) {
    return 'planning';
  }
  return null;
}

List<Map<String, dynamic>> decodeCanarySuiteReports(List<String> jsonContents) {
  return jsonContents
      .map((content) => jsonDecode(content) as Map<String, dynamic>)
      .toList(growable: false);
}
