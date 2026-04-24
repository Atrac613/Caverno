const planModeApprovalPathUi = 'uiApproval';
const planModeApprovalPathLiveHarnessFallback = 'liveHarnessApprovalFallback';
const planModeApprovalPathUnknown = 'unknown';
const planModeFallbackPathNone = 'none';
const planModeFallbackPathLiveHarnessApproval = 'liveHarnessApprovalFallback';

String resolvePlanModeApprovalPathFromLogs(List<String> logs) {
  if (logs.any(
    (line) => line.contains(
      '[Workflow] Proposal approval UI bypassed by live harness',
    ),
  )) {
    return planModeApprovalPathLiveHarnessFallback;
  }

  if (logs.any(
    (line) =>
        line.contains('[Workflow] Proposal approval UI visible') ||
        line.contains('[Workflow] Proposal approval tap started'),
  )) {
    return planModeApprovalPathUi;
  }

  return planModeApprovalPathUnknown;
}

String fallbackPathForApprovalPath(String approvalPath) {
  if (approvalPath == planModeApprovalPathLiveHarnessFallback) {
    return planModeFallbackPathLiveHarnessApproval;
  }
  return planModeFallbackPathNone;
}

Map<String, Object> buildPlanModeSuiteOutcomeSummary(
  List<Map<String, Object?>> suiteResults,
) {
  final passed = suiteResults
      .where((result) => result['status'] == 'passed')
      .length;
  return <String, Object>{
    'total': suiteResults.length,
    'passed': passed,
    'failed': suiteResults.length - passed,
  };
}

Map<String, Object> buildPlanModeSuiteWarningSummary(
  List<Map<String, Object?>> suiteResults,
) {
  var totalWarnings = 0;
  var allowedWarnings = 0;
  var unexpectedWarnings = 0;
  final scenarios = <Map<String, Object>>[];

  for (final result in suiteResults) {
    final warnings = _asList(result['warnings']);
    final allowed = _asList(result['allowedWarnings']);
    final unexpected = _asList(result['unexpectedWarnings']);
    totalWarnings += warnings.length;
    allowedWarnings += allowed.length;
    unexpectedWarnings += unexpected.length;
    if (warnings.isEmpty && allowed.isEmpty && unexpected.isEmpty) {
      continue;
    }
    scenarios.add(<String, Object>{
      'scenario': result['scenario']?.toString() ?? 'unknown',
      'warnings': warnings.length,
      'allowedWarnings': allowed.length,
      'unexpectedWarnings': unexpected.length,
      if (result['scenarioReport'] != null)
        'report': result['scenarioReport'].toString(),
      if (result['scenarioLog'] != null)
        'log': result['scenarioLog'].toString(),
    });
  }

  return <String, Object>{
    'warnings': totalWarnings,
    'allowedWarnings': allowedWarnings,
    'unexpectedWarnings': unexpectedWarnings,
    'scenariosWithWarnings': scenarios.length,
    'scenariosWithUnexpectedWarnings': scenarios
        .where((scenario) => scenario['unexpectedWarnings'] != 0)
        .length,
    'scenarios': scenarios,
  };
}

Map<String, Object> buildPlanModeSuiteTaskDriftSummary(
  List<Map<String, Object?>> suiteResults,
) {
  final scenarios = <Map<String, Object?>>[];
  for (final result in suiteResults) {
    final taskDrift = _asObjectMap(result['taskDrift']);
    final driftDetected =
        taskDrift['driftDetected'] == true ||
        result['taskDriftDetected'] == true;
    if (!driftDetected) {
      continue;
    }

    scenarios.add(<String, Object?>{
      'scenario': result['scenario']?.toString() ?? 'unknown',
      'driftReason': taskDrift['driftReason']?.toString() ?? 'unknown',
      'fallbackSource': taskDrift['fallbackSource']?.toString() ?? 'unknown',
      'expectedTargetFiles': _asList(taskDrift['expectedTargetFiles']),
      'savedTaskTargetFiles': _asList(taskDrift['savedTaskTargetFiles']),
      'actualChangedFiles': _asList(taskDrift['actualChangedFiles']),
      'report': result['scenarioReport'],
    });
  }

  return <String, Object>{'detected': scenarios.length, 'scenarios': scenarios};
}

Map<String, Object> buildPlanModeSuiteToolLoopConvergenceSummary(
  List<Map<String, Object?>> suiteResults,
) {
  var guardActivations = 0;
  final scenarios = <Map<String, Object?>>[];

  for (final result in suiteResults) {
    final convergence = _asObjectMap(result['toolLoopConvergence']);
    final activationCount = _asInt(convergence['guardActivations']);
    if (activationCount <= 0 && convergence['detected'] != true) {
      continue;
    }

    guardActivations += activationCount;
    scenarios.add(<String, Object?>{
      'scenario': result['scenario']?.toString() ?? 'unknown',
      'guardActivations': activationCount,
      'guardPattern': convergence['guardPattern']?.toString(),
      'report': result['scenarioReport'],
      'log': result['scenarioLog'],
    });
  }

  return <String, Object>{
    'detected': scenarios.length,
    'guardActivations': guardActivations,
    'scenarios': scenarios,
  };
}

Map<String, Object> buildPlanModeSuiteExecutionPathSummary(
  List<Map<String, Object?>> suiteResults,
) {
  var uiApprovalCount = 0;
  var liveHarnessFallbackCount = 0;
  var unknownApprovalCount = 0;
  final fallbackScenarios = <Map<String, Object>>[];

  for (final result in suiteResults) {
    final approvalPath =
        result['approvalPath']?.toString() ?? planModeApprovalPathUnknown;
    if (approvalPath == planModeApprovalPathUi) {
      uiApprovalCount += 1;
    } else if (approvalPath == planModeApprovalPathLiveHarnessFallback) {
      liveHarnessFallbackCount += 1;
      fallbackScenarios.add(<String, Object>{
        'scenario': result['scenario']?.toString() ?? 'unknown',
        'approvalPath': approvalPath,
        'fallbackPath':
            result['fallbackPath']?.toString() ??
            fallbackPathForApprovalPath(approvalPath),
        if (result['scenarioReport'] != null)
          'report': result['scenarioReport'].toString(),
        if (result['scenarioLog'] != null)
          'log': result['scenarioLog'].toString(),
      });
    } else {
      unknownApprovalCount += 1;
    }
  }

  return <String, Object>{
    'uiApproval': uiApprovalCount,
    'liveHarnessApprovalFallback': liveHarnessFallbackCount,
    'unknown': unknownApprovalCount,
    'fallbackScenarios': fallbackScenarios,
  };
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
