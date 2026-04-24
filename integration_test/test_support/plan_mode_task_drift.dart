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
  final shouldEvaluate = expected.isNotEmpty;

  final missingExpectedSavedTaskTargetFiles = shouldEvaluate
      ? _subtract(expected, saved)
      : const <String>[];
  final unexpectedSavedTaskTargetFiles = shouldEvaluate
      ? _subtract(saved, expected)
      : const <String>[];
  final missingExpectedChangedFiles = shouldEvaluate
      ? _subtract(expected, actual)
      : const <String>[];
  final unexpectedChangedFiles = shouldEvaluate
      ? _subtract(actual, expected)
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
