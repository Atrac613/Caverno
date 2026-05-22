import 'dart:convert';
import 'dart:io';

import 'plan_mode_heartbeat.dart';
import 'plan_mode_live_diagnostics.dart';
import 'plan_mode_report_summary.dart';
import 'plan_mode_scenario_spec.dart';
import 'plan_mode_screenshot_policy.dart';
import 'plan_mode_task_drift.dart';
import 'plan_mode_tool_loop_convergence.dart';
import 'plan_mode_warning_policy.dart';

Future<void> copyPlanModeDirectoryContents({
  required Directory source,
  required Directory destination,
}) async {
  await destination.create(recursive: true);
  for (final entity in source.listSync()) {
    final entityName = _entityBasename(entity);
    if (entityName.isEmpty) {
      continue;
    }
    if (entity is File) {
      await entity.copy('${destination.path}/$entityName');
      continue;
    }
    if (entity is Directory) {
      await copyPlanModeDirectoryContents(
        source: entity,
        destination: Directory('${destination.path}/$entityName'),
      );
    }
  }
}

String _entityBasename(FileSystemEntity entity) {
  final segments = entity.path
      .split(Platform.pathSeparator)
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  return segments.isEmpty ? '' : segments.last;
}

List<String> filterPlanModeFailureCapturedLogs(List<String> logs) {
  return logs
      .where(
        (line) =>
            line.contains('[ScenarioLLM]') ||
            line.contains('[Tool]') ||
            line.contains('[LLM]') ||
            line.contains('[ContentTool]') ||
            line.contains('[Screenshot]') ||
            line.contains('[Workflow]'),
      )
      .toList(growable: false);
}

List<String> resolvePlanModeFailureSavedTaskTargetFiles({
  required List<String> logs,
}) {
  final targetPattern = RegExp(
    r'Target files:\s*([^\r\n]+)',
    caseSensitive: false,
  );
  for (final log in logs.reversed) {
    final match = targetPattern.firstMatch(log);
    if (match == null) {
      continue;
    }
    final targets = (match.group(1) ?? '')
        .split(',')
        .map((target) => target.replaceAll('`', '').trim())
        .where((target) => target.isNotEmpty)
        .where((target) => target.toLowerCase() != 'none')
        .toList(growable: false);
    if (targets.isNotEmpty) {
      return targets;
    }
  }
  return const <String>[];
}

Future<void> writePlanModeFailureScenarioArtifacts({
  required PlanModeScenarioSpec scenario,
  required Directory scenarioDir,
  required List<String> logs,
  required Object error,
  required StackTrace stackTrace,
  required PlanModePhaseTrace phaseTrace,
  required PlanModeTimeoutBudgets budgets,
  String? heartbeatPath,
}) async {
  final screenshotPaths = listPlanModeScenarioScreenshotPaths(scenarioDir);
  final filteredLogs = filterPlanModeFailureCapturedLogs(logs);
  final warnings = collectPlanModeScenarioWarnings(logs);
  final warningSummary = summarizeScenarioWarnings(
    warnings: warnings,
    allowedPatterns: scenario.allowedWarningPatterns,
    logs: logs,
  );
  final approvalPath = resolvePlanModeApprovalPathFromLogs(logs);

  final logFile = File('${scenarioDir.path}/scenario_log.txt');
  await logFile.writeAsString('${logs.join('\n')}\n');
  final lastHeartbeat = readPlanModeLiveHeartbeatSnapshot(path: heartbeatPath);
  final diagnostics = buildPlanModeFailureDiagnostics(
    logs: logs,
    errorText: error.toString(),
    phaseTimings: phaseTrace.toJson(),
    budgets: budgets.toJson(),
    activeTaskTitle: lastHeartbeat['activeTaskTitle'] as String?,
    toolResultCount: lastHeartbeat['toolResultCount'] as int?,
    fileWriteCount: lastHeartbeat['fileWriteCount'] as int?,
  );
  final shouldEvaluateTaskDrift =
      phaseTrace.taskProposalReadyAt != null ||
      phaseTrace.approvalTappedAt != null ||
      phaseTrace.firstTaskStartedAt != null ||
      phaseTrace.lastTaskProgressAt != null;
  final taskDrift = buildPlanModeScenarioTaskDriftReport(
    expectedTargetFiles: shouldEvaluateTaskDrift
        ? scenario.resolvedWorkflowExpectation.firstTaskTargetFilesContain
        : const <String>[],
    savedTaskTargetFiles: resolvePlanModeFailureSavedTaskTargetFiles(
      logs: logs,
    ),
    scenarioDir: scenarioDir,
  ).toJson();
  final toolLoopConvergence = buildPlanModeToolLoopConvergenceReport(logs);

  final report = <String, Object?>{
    'scenario': scenario.name,
    'status': 'failed',
    'failureClass': diagnostics.failureClass.name,
    'projectRoot': scenarioDir.path,
    'approvalPath': approvalPath,
    'fallbackPath': fallbackPathForApprovalPath(approvalPath),
    'usedHarnessApprovalFallback':
        approvalPath == planModeApprovalPathLiveHarnessFallback,
    'error': error.toString(),
    'stackTrace': stackTrace.toString(),
    'screenshots': screenshotPaths,
    'warnings': warnings,
    'allowedWarnings': warningSummary.allowedWarnings,
    'unexpectedWarnings': warningSummary.unexpectedWarnings,
    'warningSummary': warningSummary.toJson(),
    'taskDrift': taskDrift,
    'taskDriftDetected': taskDrift['driftDetected'],
    'toolLoopConvergence': toolLoopConvergence,
    'phaseTimings': phaseTrace.toJson(),
    'budgets': budgets.toJson(),
    'lastHeartbeat': lastHeartbeat,
    'diagnostics': diagnostics.toJson(),
    'capturedLogs': filteredLogs,
  };
  final reportFile = File('${scenarioDir.path}/scenario_report.json');
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
}
