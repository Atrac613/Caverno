import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/utils/logger.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';

import 'plan_mode_execution_progress.dart';
import 'plan_mode_failure_artifacts.dart';
import 'plan_mode_heartbeat.dart';
import 'plan_mode_live_diagnostics.dart';
import 'plan_mode_post_scenario_settle.dart';
import 'plan_mode_report_summary.dart';
import 'plan_mode_scenario_spec.dart';
import 'plan_mode_screenshot_policy.dart';
import 'plan_mode_task_drift.dart';
import 'plan_mode_tool_lifecycle.dart';
import 'plan_mode_tool_loop_convergence.dart';
import 'plan_mode_warning_policy.dart';

class PlanModeScenarioReportArtifacts {
  const PlanModeScenarioReportArtifacts({
    required this.reportPath,
    required this.logPath,
    required this.screenshotPaths,
    required this.report,
  });

  final String reportPath;
  final String logPath;
  final List<String> screenshotPaths;
  final Map<String, Object?> report;
}

class PlanModeArchivedScenarioResult {
  const PlanModeArchivedScenarioResult({
    required this.archivedScenarioDirectoryPath,
    required this.suiteResult,
  });

  final String archivedScenarioDirectoryPath;
  final Map<String, Object?> suiteResult;
}

Future<PlanModeScenarioReportArtifacts> writePlanModePassedScenarioReport({
  required PlanModeScenarioSpec scenario,
  required Directory scenarioDir,
  required String executionModeName,
  required String approvalPath,
  required Conversation conversation,
  required ConversationWorkflowSpec savedWorkflow,
  required List<String> logs,
  required List<String> warnings,
  required PlanModeWarningSummary warningSummary,
  required PlanModePostScenarioSettleResult postScenarioSettle,
  required PlanModePhaseTrace phaseTrace,
  required PlanModeTimeoutBudgets budgets,
  String? heartbeatPath,
}) async {
  final report = buildPlanModePassedScenarioReport(
    scenario: scenario,
    scenarioDir: scenarioDir,
    executionModeName: executionModeName,
    approvalPath: approvalPath,
    conversation: conversation,
    savedWorkflow: savedWorkflow,
    logs: logs,
    warnings: warnings,
    warningSummary: warningSummary,
    postScenarioSettle: postScenarioSettle,
    phaseTrace: phaseTrace,
    budgets: budgets,
    heartbeatPath: heartbeatPath,
  );
  final screenshotPaths = listPlanModeScenarioScreenshotPaths(scenarioDir);
  report['screenshots'] = screenshotPaths;

  final logFile = File('${scenarioDir.path}/scenario_log.txt');
  await logFile.writeAsString('${logs.join('\n')}\n');
  final reportFile = File('${scenarioDir.path}/scenario_report.json');
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  appLog('[Scenario] Report written to ${reportFile.path}');
  return PlanModeScenarioReportArtifacts(
    reportPath: reportFile.path,
    logPath: logFile.path,
    screenshotPaths: screenshotPaths,
    report: report,
  );
}

Map<String, Object?> buildPlanModePassedScenarioReport({
  required PlanModeScenarioSpec scenario,
  required Directory scenarioDir,
  required String executionModeName,
  required String approvalPath,
  required Conversation conversation,
  required ConversationWorkflowSpec savedWorkflow,
  required List<String> logs,
  required List<String> warnings,
  required PlanModeWarningSummary warningSummary,
  required PlanModePostScenarioSettleResult postScenarioSettle,
  required PlanModePhaseTrace phaseTrace,
  required PlanModeTimeoutBudgets budgets,
  String? heartbeatPath,
}) {
  final savedTaskTargetFiles = resolvePlanModeScenarioSavedTaskTargetFiles(
    conversation: conversation,
    savedWorkflow: savedWorkflow,
  );
  final taskDrift = buildPlanModeScenarioTaskDriftReport(
    expectedTargetFiles: resolvePlanModeScenarioExpectedTaskDriftTargetFiles(
      scenario: scenario,
      savedTaskTargetFiles: savedTaskTargetFiles,
    ),
    savedTaskTargetFiles: savedTaskTargetFiles,
    scenarioDir: scenarioDir,
  ).toJson();
  final toolLoopConvergence = buildPlanModeToolLoopConvergenceReport(logs);
  final toolLifecycle = buildPlanModeToolLifecycleReport(logs);
  final diagnostics = buildPlanModeFailureDiagnostics(
    logs: logs,
    lastWorkflowSnapshot: summarizePlanModeWorkflowTasks(
      conversation.projectedExecutionTasks,
    ),
    budgetPhase: 'completed',
    activeTaskTitle: activePlanModeWorkflowTaskTitle(
      conversation.projectedExecutionTasks,
    ),
    toolResultCount: countPlanModeContentToolResults(logs),
    fileWriteCount: countPlanModeFileWriteExecutions(logs),
    phaseTimings: phaseTrace.toJson(),
    budgets: budgets.toJson(),
  ).toJson();

  return <String, Object?>{
    'scenario': scenario.name,
    'tags': scenario.tags,
    'status': 'passed',
    'failureClass': PlanModeFailureClass.passed.name,
    'executionMode': executionModeName,
    'projectRoot': scenarioDir.path,
    'approvalPath': approvalPath,
    'fallbackPath': fallbackPathForApprovalPath(approvalPath),
    'usedHarnessApprovalFallback':
        approvalPath == planModeApprovalPathLiveHarnessFallback,
    'workflowStage': conversation.workflowStage.name,
    'workflowGoal': savedWorkflow.goal,
    'workflowOpenQuestions': savedWorkflow.openQuestions,
    'phaseTimings': phaseTrace.toJson(),
    'budgets': budgets.toJson(),
    'selectedDecisions': scenario.decisionSelections
        .map(
          (selection) => <String, String?>{
            'question': selection.question,
            'optionLabel': selection.optionLabel,
            'freeTextAnswer': selection.freeTextAnswer,
          },
        )
        .toList(growable: false),
    'warnings': warnings,
    'allowedWarnings': warningSummary.allowedWarnings,
    'unexpectedWarnings': warningSummary.unexpectedWarnings,
    'warningSummary': warningSummary.toJson(),
    'taskDrift': taskDrift,
    'taskDriftDetected': taskDrift['driftDetected'],
    'toolLoopConvergence': toolLoopConvergence,
    'toolLifecycle': toolLifecycle,
    'postScenarioSettled': postScenarioSettle.settled,
    'postScenarioInitiallySettled': postScenarioSettle.initiallySettled,
    'postScenarioCancellationUsed': postScenarioSettle.cancellationUsed,
    'postScenarioSettle': postScenarioSettle.toJson(),
    'artifacts': collectPlanModeScenarioArtifactContents(
      scenarioDir: scenarioDir,
      expectations: scenario.resolvedArtifactExpectations,
      mode: scenario.artifactExpectationMode,
    ),
    'logChecks': scenario.logExpectations
        .map(
          (expectation) => <String, Object?>{
            'pattern': expectation.pattern,
            'exactCount': expectation.exactCount,
            'minCount': expectation.minCount,
            'maxCount': expectation.maxCount,
          },
        )
        .toList(growable: false),
    'capturedLogs': filterPlanModePassedScenarioCapturedLogs(logs),
    'lastHeartbeat': readPlanModeLiveHeartbeatSnapshot(path: heartbeatPath),
    'diagnostics': diagnostics,
  };
}

List<String> resolvePlanModeScenarioSavedTaskTargetFiles({
  required Conversation conversation,
  required ConversationWorkflowSpec savedWorkflow,
}) {
  final startedTaskTargets = _nonPendingTaskTargetFiles(
    conversation.projectedExecutionTasks,
  );
  if (startedTaskTargets.isNotEmpty) {
    return startedTaskTargets;
  }

  final savedTaskTargets = _firstNonEmptyTaskTargetFiles(savedWorkflow.tasks);
  if (savedTaskTargets.isNotEmpty) {
    return savedTaskTargets;
  }
  return _firstNonEmptyTaskTargetFiles(conversation.projectedExecutionTasks);
}

Map<String, String> collectPlanModeScenarioArtifactContents({
  required Directory scenarioDir,
  required List<PlanModeArtifactExpectation> expectations,
  required PlanModeArtifactExpectationMode mode,
}) {
  final artifacts = <String, String>{};
  for (final artifact in expectations.where((item) => item.shouldExist)) {
    final file = File('${scenarioDir.path}/${artifact.path}');
    if (!file.existsSync() &&
        mode == PlanModeArtifactExpectationMode.anyRequired) {
      continue;
    }
    artifacts[artifact.path] = file.readAsStringSync();
  }
  return artifacts;
}

List<String> _nonPendingTaskTargetFiles(List<ConversationWorkflowTask> tasks) {
  final targets = <String>{};
  for (final task in tasks) {
    if (task.status == ConversationWorkflowTaskStatus.pending) {
      continue;
    }
    targets.addAll(_effectiveTaskTargetFiles(task));
  }
  final values = targets.toList(growable: false);
  values.sort();
  return values;
}

List<String> _firstNonEmptyTaskTargetFiles(
  List<ConversationWorkflowTask> tasks,
) {
  for (final task in tasks) {
    final targets = _effectiveTaskTargetFiles(task);
    if (targets.isNotEmpty) {
      return targets;
    }
  }
  return const <String>[];
}

List<String> _effectiveTaskTargetFiles(ConversationWorkflowTask task) {
  final explicitTargets = task.targetFiles
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  if (explicitTargets.isNotEmpty) {
    return explicitTargets;
  }

  final inferredTargets = <String>{
    ..._inferTaskTargetFiles('${task.title.trim()} ${task.notes.trim()}'),
    ..._inferTaskTargetFiles(task.validationCommand),
  }.toList(growable: false);
  inferredTargets.sort();
  return inferredTargets;
}

Set<String> _inferTaskTargetFiles(String text) {
  return RegExp(
        r'(?:(?:^|[\s`"(]))([A-Za-z0-9_./-]+\.[A-Za-z][A-Za-z0-9]{0,7}|__init__\.py|\.gitignore)(?=$|[\s`)",.:;])',
        caseSensitive: false,
      )
      .allMatches(text)
      .map((match) => match.group(1)?.trim() ?? '')
      .where((path) => path.isNotEmpty)
      .toSet();
}

List<String> filterPlanModePassedScenarioCapturedLogs(List<String> logs) {
  return logs
      .where(
        (line) =>
            line.contains('[ScenarioLLM]') ||
            line.contains('[Tool]') ||
            line.contains('[McpToolService]') ||
            line.contains('[LLM]') ||
            line.contains('[ContentTool]') ||
            line.contains('[Screenshot]'),
      )
      .toList(growable: false);
}

void writePlanModeCompletedScenarioHeartbeat({
  required Conversation conversation,
  required List<String> logs,
  required PlanModePostScenarioSettleResult postScenarioSettle,
  required PlanModePhaseTrace phaseTrace,
  required PlanModeTimeoutBudgets budgets,
  required PlanModeLiveHeartbeatWriter heartbeatWriter,
}) {
  if (!postScenarioSettle.settled) {
    return;
  }
  heartbeatWriter.write(
    phase: 'completed',
    subphase: postScenarioSettle.cancellationUsed
        ? 'scenarioCompletedAfterCleanupCancel'
        : 'scenarioCompleted',
    phaseTrace: phaseTrace,
    budgets: budgets,
    activeTaskTitle: activePlanModeWorkflowTaskTitle(
      conversation.projectedExecutionTasks,
    ),
    workflowSnapshot: summarizePlanModeWorkflowTasks(
      conversation.projectedExecutionTasks,
    ),
    toolResultCount: countPlanModeContentToolResults(logs),
    fileWriteCount: countPlanModeFileWriteExecutions(logs),
    messageCount: conversation.messages.length,
    hasPendingApprovals: false,
    isLoading: false,
  );
}

Future<PlanModeArchivedScenarioResult> archivePlanModeScenarioRun({
  required PlanModeScenarioSpec scenario,
  required Directory scenarioDir,
  required Directory suiteRunDirectory,
  required String modeName,
  required DateTime startedAt,
  required DateTime finishedAt,
  required String tempOutputDirectoryPath,
  required List<String> logs,
  required PlanModePhaseTrace phaseTrace,
  required PlanModeTimeoutBudgets budgets,
  String? heartbeatPath,
  required Object? failure,
  required StackTrace? failureStackTrace,
}) async {
  if (failure != null && failureStackTrace != null) {
    await writePlanModeFailureScenarioArtifacts(
      scenario: scenario,
      scenarioDir: scenarioDir,
      logs: logs,
      error: failure,
      stackTrace: failureStackTrace,
      phaseTrace: phaseTrace,
      budgets: budgets,
      heartbeatPath: heartbeatPath,
    );
  }
  final archivedScenarioDir = Directory(
    '${suiteRunDirectory.path}/${scenario.name}',
  );
  await copyPlanModeDirectoryContents(
    source: scenarioDir,
    destination: archivedScenarioDir,
  );
  final archivedReportPath = File(
    '${archivedScenarioDir.path}/scenario_report.json',
  );
  final archivedLogPath = File('${archivedScenarioDir.path}/scenario_log.txt');
  final archivedReport = archivedReportPath.existsSync()
      ? _readJsonObjectMap(archivedReportPath)
      : const <String, Object?>{};
  final suiteResult = buildPlanModeArchivedSuiteResult(
    scenario: scenario,
    modeName: modeName,
    startedAt: startedAt,
    finishedAt: finishedAt,
    tempOutputDirectoryPath: tempOutputDirectoryPath,
    archivedOutputDirectoryPath: archivedScenarioDir.path,
    archivedReportPath: archivedReportPath.existsSync()
        ? archivedReportPath.path
        : null,
    archivedLogPath: archivedLogPath.existsSync() ? archivedLogPath.path : null,
    archivedScreenshotPaths: listPlanModeScenarioScreenshotPaths(
      archivedScenarioDir,
    ),
    archivedReport: archivedReport,
    failure: failure,
    failureStackTrace: failureStackTrace,
  );
  return PlanModeArchivedScenarioResult(
    archivedScenarioDirectoryPath: archivedScenarioDir.path,
    suiteResult: suiteResult,
  );
}

Map<String, Object?> buildPlanModeArchivedSuiteResult({
  required PlanModeScenarioSpec scenario,
  required String modeName,
  required DateTime startedAt,
  required DateTime finishedAt,
  required String tempOutputDirectoryPath,
  required String archivedOutputDirectoryPath,
  required String? archivedReportPath,
  required String? archivedLogPath,
  required List<String> archivedScreenshotPaths,
  required Map<String, Object?> archivedReport,
  required Object? failure,
  required StackTrace? failureStackTrace,
}) {
  final archivedDiagnostics = _asObjectMap(archivedReport['diagnostics']);
  final archivedHeartbeat = _asObjectMap(archivedReport['lastHeartbeat']);
  final archivedTaskDrift = _asObjectMap(archivedReport['taskDrift']);
  final archivedToolLoopConvergence = _asObjectMap(
    archivedReport['toolLoopConvergence'],
  );
  final archivedToolLifecycle = _asObjectMap(archivedReport['toolLifecycle']);
  final archivedWarningSummary = _asObjectMap(archivedReport['warningSummary']);
  final archivedApprovalPath =
      archivedReport['approvalPath'] as String? ?? planModeApprovalPathUnknown;
  final archivedFallbackPath =
      archivedReport['fallbackPath'] as String? ??
      fallbackPathForApprovalPath(archivedApprovalPath);

  return <String, Object?>{
    'scenario': scenario.name,
    'tags': scenario.tags,
    'mode': modeName,
    'status': failure == null ? 'passed' : 'failed',
    'startedAt': startedAt.toIso8601String(),
    'finishedAt': finishedAt.toIso8601String(),
    'durationMs': finishedAt.difference(startedAt).inMilliseconds,
    'tempOutputDirectory': tempOutputDirectoryPath,
    'archivedOutputDirectory': archivedOutputDirectoryPath,
    'scenarioReport': archivedReportPath,
    'scenarioLog': archivedLogPath,
    'screenshots': archivedScreenshotPaths,
    'failureClass': archivedReportPath != null
        ? archivedReport['failureClass'] as String? ??
              (failure == null ? 'passed' : 'unclassified')
        : (failure == null ? 'passed' : 'unclassified'),
    'budgetPhase': archivedReportPath != null
        ? archivedDiagnostics['budgetPhase'] as String?
        : null,
    'lastKnownPhase': archivedHeartbeat['phase'] as String?,
    'activeTaskTitle': archivedHeartbeat['activeTaskTitle'] as String?,
    'lastUpdatedAt': archivedHeartbeat['updatedAt'] as String?,
    'lastHeartbeat': archivedHeartbeat,
    'phaseTimings': archivedReport['phaseTimings'],
    'budgets': archivedReport['budgets'],
    'postScenarioSettled': archivedReport['postScenarioSettled'] as bool?,
    'postScenarioCancellationUsed':
        archivedReport['postScenarioCancellationUsed'] as bool?,
    'approvalPath': archivedApprovalPath,
    'fallbackPath': archivedFallbackPath,
    'usedHarnessApprovalFallback':
        archivedApprovalPath == planModeApprovalPathLiveHarnessFallback,
    'taskDrift': archivedTaskDrift,
    'taskDriftDetected': archivedTaskDrift['driftDetected'] as bool? ?? false,
    'toolLoopConvergence': archivedToolLoopConvergence,
    'toolLifecycle': archivedToolLifecycle,
    'warnings': _asList(archivedReport['warnings']),
    'allowedWarnings': _asList(archivedReport['allowedWarnings']),
    'unexpectedWarnings': _asList(archivedReport['unexpectedWarnings']),
    'warningSummary': archivedWarningSummary,
    'warningDetails': _asList(archivedWarningSummary['details']),
    'error': failure?.toString(),
    'stackTrace': failureStackTrace?.toString(),
  };
}

Map<String, Object?> _readJsonObjectMap(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  return _asObjectMap(decoded);
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

List<Object?> _asList(Object? value) {
  return value is List ? value.cast<Object?>() : const <Object?>[];
}
