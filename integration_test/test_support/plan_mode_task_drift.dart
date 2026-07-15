import 'dart:io';

import 'plan_mode_scenario_spec.dart';

const planModeTaskDriftSourceNone = 'none';
const planModeTaskDriftSourceSavedTaskTargetFiles = 'savedTaskTargetFiles';
const planModeTaskDriftSourceActualChangedFiles = 'actualChangedFiles';
const planModeTaskDriftSourceSavedAndActualFiles =
    'savedTaskTargetFiles+actualChangedFiles';

const planModeTaskDriftReasonNone = 'none';
const planModeTaskDriftReasonMissingExpectedSavedTaskTargetFiles =
    'missingExpectedSavedTaskTargetFiles';
const planModeTaskDriftReasonUnexpectedSavedTaskTargetFiles =
    'unexpectedSavedTaskTargetFiles';
const planModeTaskDriftReasonMissingExpectedChangedFiles =
    'missingExpectedChangedFiles';
const planModeTaskDriftReasonUnexpectedChangedFiles = 'unexpectedChangedFiles';

class PlanModeTaskDriftReport {
  const PlanModeTaskDriftReport({
    required this.expectedTargetFiles,
    required this.savedTaskTargetFiles,
    required this.actualChangedFiles,
    required this.missingExpectedSavedTaskTargetFiles,
    required this.unexpectedSavedTaskTargetFiles,
    required this.missingExpectedChangedFiles,
    required this.unexpectedChangedFiles,
    required this.fallbackSource,
    required this.driftReason,
    required this.driftReasons,
  });

  final List<String> expectedTargetFiles;
  final List<String> savedTaskTargetFiles;
  final List<String> actualChangedFiles;
  final List<String> missingExpectedSavedTaskTargetFiles;
  final List<String> unexpectedSavedTaskTargetFiles;
  final List<String> missingExpectedChangedFiles;
  final List<String> unexpectedChangedFiles;
  final String fallbackSource;
  final String driftReason;
  final List<String> driftReasons;

  bool get driftDetected => driftReasons.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'expectedTargetFiles': expectedTargetFiles,
      'savedTaskTargetFiles': savedTaskTargetFiles,
      'actualChangedFiles': actualChangedFiles,
      'missingExpectedSavedTaskTargetFiles':
          missingExpectedSavedTaskTargetFiles,
      'unexpectedSavedTaskTargetFiles': unexpectedSavedTaskTargetFiles,
      'missingExpectedChangedFiles': missingExpectedChangedFiles,
      'unexpectedChangedFiles': unexpectedChangedFiles,
      'fallbackSource': fallbackSource,
      'driftReason': driftReason,
      'driftReasons': driftReasons,
      'driftDetected': driftDetected,
    };
  }
}

PlanModeTaskDriftReport buildPlanModeTaskDriftReport({
  required Iterable<String> expectedTargetFiles,
  required Iterable<String> savedTaskTargetFiles,
  required Iterable<String> actualChangedFiles,
}) {
  final expected = _normalizeUniquePaths(expectedTargetFiles);
  final saved = _normalizeUniquePaths(savedTaskTargetFiles);
  final actual = _normalizeUniquePaths(actualChangedFiles);
  final comparisonTargets = expected.isNotEmpty ? expected : saved;
  final shouldEvaluate = comparisonTargets.isNotEmpty;

  final missingExpectedSavedTaskTargetFiles = expected.isNotEmpty
      ? _subtract(expected, saved)
      : const <String>[];
  final unexpectedSavedTaskTargetFiles = expected.isNotEmpty
      ? _subtract(saved, expected)
      : const <String>[];
  final missingExpectedChangedFiles = shouldEvaluate
      ? _subtract(comparisonTargets, actual)
      : const <String>[];
  final unexpectedChangedFiles = shouldEvaluate
      ? _subtract(actual, comparisonTargets)
      : const <String>[];

  final driftReasons = <String>[
    if (missingExpectedSavedTaskTargetFiles.isNotEmpty)
      planModeTaskDriftReasonMissingExpectedSavedTaskTargetFiles,
    if (unexpectedSavedTaskTargetFiles.isNotEmpty)
      planModeTaskDriftReasonUnexpectedSavedTaskTargetFiles,
    if (missingExpectedChangedFiles.isNotEmpty)
      planModeTaskDriftReasonMissingExpectedChangedFiles,
    if (unexpectedChangedFiles.isNotEmpty)
      planModeTaskDriftReasonUnexpectedChangedFiles,
  ];

  return PlanModeTaskDriftReport(
    expectedTargetFiles: expected,
    savedTaskTargetFiles: saved,
    actualChangedFiles: actual,
    missingExpectedSavedTaskTargetFiles: missingExpectedSavedTaskTargetFiles,
    unexpectedSavedTaskTargetFiles: unexpectedSavedTaskTargetFiles,
    missingExpectedChangedFiles: missingExpectedChangedFiles,
    unexpectedChangedFiles: unexpectedChangedFiles,
    fallbackSource: _resolveFallbackSource(
      hasSavedTaskDrift:
          missingExpectedSavedTaskTargetFiles.isNotEmpty ||
          unexpectedSavedTaskTargetFiles.isNotEmpty,
      hasActualChangedFileDrift:
          missingExpectedChangedFiles.isNotEmpty ||
          unexpectedChangedFiles.isNotEmpty,
    ),
    driftReason: driftReasons.isEmpty
        ? planModeTaskDriftReasonNone
        : driftReasons.first,
    driftReasons: driftReasons,
  );
}

PlanModeTaskDriftReport buildPlanModeScenarioTaskDriftReport({
  required Iterable<String> expectedTargetFiles,
  required Directory scenarioDir,
  Iterable<String> savedTaskTargetFiles = const <String>[],
  Iterable<String> excludedPaths = const <String>[],
}) {
  return buildPlanModeTaskDriftReport(
    expectedTargetFiles: expectedTargetFiles,
    savedTaskTargetFiles: savedTaskTargetFiles,
    actualChangedFiles: collectPlanModeScenarioChangedFiles(
      scenarioDir,
      excludedPaths: excludedPaths,
    ),
  );
}

List<String> resolvePlanModeScenarioExpectedTaskDriftTargetFiles({
  required PlanModeScenarioSpec scenario,
  required List<String> savedTaskTargetFiles,
}) {
  if (scenario.harnessTaskExecutionLimit != null &&
      savedTaskTargetFiles.isNotEmpty) {
    return savedTaskTargetFiles;
  }

  final expectation = scenario.resolvedWorkflowExpectation;
  if (expectation.targetFilesContain.isNotEmpty) {
    return expectation.targetFilesContain;
  }
  return expectation.firstTaskTargetFilesContain;
}

List<String> collectPlanModeScenarioChangedFiles(
  Directory scenarioDir, {
  Iterable<String> excludedPaths = const <String>[],
}) {
  if (!scenarioDir.existsSync()) {
    return const <String>[];
  }

  final rootPath = scenarioDir.path.endsWith(Platform.pathSeparator)
      ? scenarioDir.path
      : '${scenarioDir.path}${Platform.pathSeparator}';
  final files = <String>[];
  final normalizedExcludedPaths = excludedPaths
      .map(normalizePlanModeTaskDriftPath)
      .where((path) => path.isNotEmpty)
      .toSet();
  final excludedPrefixes = normalizedExcludedPaths
      .where((path) => path.endsWith('/'))
      .toList(growable: false);
  for (final entity in scenarioDir.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File || !entity.path.startsWith(rootPath)) {
      continue;
    }
    final relativePath = entity.path
        .substring(rootPath.length)
        .replaceAll(Platform.pathSeparator, '/');
    final normalizedPath = normalizePlanModeTaskDriftPath(relativePath);
    if (normalizedPath.isEmpty ||
        normalizedExcludedPaths.contains(normalizedPath) ||
        excludedPrefixes.any(normalizedPath.startsWith) ||
        isPlanModeScenarioHarnessArtifact(normalizedPath)) {
      continue;
    }
    files.add(normalizedPath);
  }
  files.sort();
  return files;
}

bool isPlanModeScenarioHarnessArtifact(String normalizedPath) {
  return normalizedPath == 'scenario_report.json' ||
      normalizedPath == 'scenario_log.txt' ||
      normalizedPath == 'scenario_post_validation.json' ||
      normalizedPath == 'heartbeat.json' ||
      normalizedPath == '.ds_store' ||
      normalizedPath.endsWith('/.ds_store') ||
      normalizedPath.endsWith('.png');
}

List<String> _normalizeUniquePaths(Iterable<String> paths) {
  final values = paths
      .map(normalizePlanModeTaskDriftPath)
      .where((path) => path.isNotEmpty)
      .toSet()
      .toList(growable: false);
  values.sort();
  return values;
}

String normalizePlanModeTaskDriftPath(String value) {
  return value.replaceAll('\\', '/').trim().toLowerCase();
}

List<String> _subtract(List<String> left, List<String> right) {
  final rightSet = right.toSet();
  return left.where((item) => !rightSet.contains(item)).toList(growable: false);
}

String _resolveFallbackSource({
  required bool hasSavedTaskDrift,
  required bool hasActualChangedFileDrift,
}) {
  if (hasSavedTaskDrift && hasActualChangedFileDrift) {
    return planModeTaskDriftSourceSavedAndActualFiles;
  }
  if (hasSavedTaskDrift) {
    return planModeTaskDriftSourceSavedTaskTargetFiles;
  }
  if (hasActualChangedFileDrift) {
    return planModeTaskDriftSourceActualChangedFiles;
  }
  return planModeTaskDriftSourceNone;
}
