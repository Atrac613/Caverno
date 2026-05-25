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

List<Map<String, Object?>> collectPlanModeScenarioWarningDetails(
  Map<String, Object?> result,
) {
  final explicitDetails = _asList(result['warningDetails']);
  final warningSummary = _asObjectMap(result['warningSummary']);
  final summaryDetails = _asList(warningSummary['details']);
  final rawDetails = explicitDetails.isNotEmpty
      ? explicitDetails
      : summaryDetails;
  if (rawDetails.isNotEmpty) {
    final details = <Map<String, Object?>>[];
    for (final rawDetail in rawDetails) {
      final detail = _normalizeScenarioWarningDetail(
        result: result,
        detail: _asObjectMap(rawDetail),
      );
      if (detail != null) {
        details.add(detail);
      }
    }
    return details;
  }

  final details = <Map<String, Object?>>[];
  for (final warning in _asList(result['allowedWarnings'])) {
    final detail = _normalizeScenarioWarningDetail(
      result: result,
      detail: <String, Object?>{
        'warning': warning,
        'disposition': 'allowed',
        'reason': 'legacyAllowedWarning',
      },
    );
    if (detail != null) {
      details.add(detail);
    }
  }
  for (final warning in _asList(result['unexpectedWarnings'])) {
    final detail = _normalizeScenarioWarningDetail(
      result: result,
      detail: <String, Object?>{
        'warning': warning,
        'disposition': 'unexpected',
        'reason': 'requiresInvestigation',
      },
    );
    if (detail != null) {
      details.add(detail);
    }
  }
  return details;
}

Map<String, Object> buildPlanModeSuiteWarningDetailSummary(
  List<Map<String, Object?>> suiteResults,
) {
  final details = <Map<String, Object?>>[];
  final byReason = <String, int>{};
  final unexpectedByReason = <String, int>{};

  for (final result in suiteResults) {
    for (final detail in collectPlanModeScenarioWarningDetails(result)) {
      details.add(detail);
      final reason = detail['reason']?.toString() ?? 'unknown';
      byReason.update(reason, (count) => count + 1, ifAbsent: () => 1);
      if (detail['disposition'] != 'allowed') {
        unexpectedByReason.update(
          reason,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }

  final unexpectedDetails = details
      .where((detail) => detail['disposition'] != 'allowed')
      .length;
  return <String, Object>{
    'details': details,
    'totalDetails': details.length,
    'allowedDetails': details.length - unexpectedDetails,
    'unexpectedDetails': unexpectedDetails,
    'byReason': byReason,
    'unexpectedByReason': unexpectedByReason,
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
  var successfulValidations = 0;
  var guardActivations = 0;
  var naturalStops = 0;
  final scenarios = <Map<String, Object?>>[];

  for (final result in suiteResults) {
    final convergence = _asObjectMap(result['toolLoopConvergence']);
    final validationCount = _asInt(convergence['successfulValidations']);
    final activationCount = _asInt(convergence['guardActivations']);
    final naturalStopCount = _asInt(convergence['naturalStops']);
    if (activationCount <= 0 &&
        naturalStopCount <= 0 &&
        convergence['detected'] != true) {
      continue;
    }

    successfulValidations += validationCount;
    guardActivations += activationCount;
    naturalStops += naturalStopCount;
    scenarios.add(<String, Object?>{
      'scenario': result['scenario']?.toString() ?? 'unknown',
      'status': convergence['status']?.toString(),
      'successfulValidations': validationCount,
      'guardActivations': activationCount,
      'naturalStops': naturalStopCount,
      'guardPattern': convergence['guardPattern']?.toString(),
      'report': result['scenarioReport'],
      'log': result['scenarioLog'],
    });
  }

  return <String, Object>{
    'detected': scenarios.length,
    'successfulValidations': successfulValidations,
    'guardActivations': guardActivations,
    'naturalStops': naturalStops,
    'scenarios': scenarios,
  };
}

Map<String, Object> buildPlanModeSuiteToolLifecycleSummary(
  List<Map<String, Object?>> suiteResults,
) {
  var eventCount = 0;
  var serviceExecutionCount = 0;
  var toolCallCount = 0;
  var completedCount = 0;
  var skippedCount = 0;
  var failedCount = 0;
  var exceptionCount = 0;
  var incompleteToolCount = 0;
  var maxDurationMs = 0;
  final scenarios = <Map<String, Object?>>[];
  final observedToolNames = <String>{};

  for (final result in suiteResults) {
    final lifecycle = _asObjectMap(result['toolLifecycle']);
    final scenarioEventCount = _asInt(lifecycle['eventCount']);
    final scenarioServiceExecutionCount = _asInt(
      lifecycle['serviceExecutionCount'],
    );
    if (scenarioEventCount <= 0 &&
        scenarioServiceExecutionCount <= 0 &&
        lifecycle['detected'] != true) {
      continue;
    }

    final scenarioToolCallCount = _asInt(lifecycle['toolCallCount']);
    final scenarioCompletedCount = _asInt(lifecycle['completedCount']);
    final scenarioSkippedCount = _asInt(lifecycle['skippedCount']);
    final scenarioFailedCount = _asInt(lifecycle['failedCount']);
    final scenarioExceptionCount = _asInt(lifecycle['exceptionCount']);
    final scenarioIncompleteToolCount = _asInt(
      lifecycle['incompleteToolCount'],
    );
    final scenarioMaxDurationMs = _asInt(lifecycle['maxDurationMs']);

    eventCount += scenarioEventCount;
    serviceExecutionCount += scenarioServiceExecutionCount;
    toolCallCount += scenarioToolCallCount;
    completedCount += scenarioCompletedCount;
    skippedCount += scenarioSkippedCount;
    failedCount += scenarioFailedCount;
    exceptionCount += scenarioExceptionCount;
    incompleteToolCount += scenarioIncompleteToolCount;
    if (scenarioMaxDurationMs > maxDurationMs) {
      maxDurationMs = scenarioMaxDurationMs;
    }
    final scenarioObservedToolNames = _asList(
      lifecycle['observedToolNames'],
    ).map((toolName) => toolName.toString()).toList(growable: false);
    observedToolNames.addAll(scenarioObservedToolNames);

    scenarios.add(<String, Object?>{
      'scenario': result['scenario']?.toString() ?? 'unknown',
      'eventCount': scenarioEventCount,
      'serviceExecutionCount': scenarioServiceExecutionCount,
      'toolCallCount': scenarioToolCallCount,
      'completedCount': scenarioCompletedCount,
      'skippedCount': scenarioSkippedCount,
      'failedCount': scenarioFailedCount,
      'exceptionCount': scenarioExceptionCount,
      'incompleteToolCount': scenarioIncompleteToolCount,
      'maxDurationMs': scenarioMaxDurationMs,
      'observedToolNames': scenarioObservedToolNames,
      'incompleteTools': _asList(lifecycle['incompleteTools']),
      'report': result['scenarioReport'],
      'log': result['scenarioLog'],
    });
  }

  final sortedObservedToolNames = observedToolNames.toList(growable: false)
    ..sort();

  return <String, Object>{
    'detected': scenarios.length,
    'eventCount': eventCount,
    'serviceExecutionCount': serviceExecutionCount,
    'toolCallCount': toolCallCount,
    'completedCount': completedCount,
    'skippedCount': skippedCount,
    'failedCount': failedCount,
    'exceptionCount': exceptionCount,
    'incompleteToolCount': incompleteToolCount,
    'maxDurationMs': maxDurationMs,
    'observedToolNames': sortedObservedToolNames,
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

List<Map<String, Object?>> collectPlanModeScenarioQualityBlockers(
  Map<String, Object?> result,
) {
  final blockers = <Map<String, Object?>>[];

  void addBlocker({
    required String kind,
    required String reason,
    String? detail,
    String? warning,
  }) {
    blockers.add(<String, Object?>{
      'scenario': result['scenario']?.toString() ?? 'unknown',
      'kind': kind,
      'reason': reason,
      if (detail != null && detail.isNotEmpty) 'detail': detail,
      if (warning != null && warning.isNotEmpty) 'warning': warning,
      if (result['scenarioReport'] != null)
        'report': result['scenarioReport'].toString(),
      if (result['scenarioLog'] != null)
        'log': result['scenarioLog'].toString(),
    });
  }

  if (result['status'] != 'passed') {
    final failureClass = result['failureClass']?.toString();
    addBlocker(
      kind: 'scenarioFailed',
      reason:
          failureClass == null ||
              failureClass.isEmpty ||
              failureClass == 'passed'
          ? 'scenarioFailed'
          : failureClass,
      detail: result['error']?.toString(),
    );
  }

  for (final detail in collectPlanModeScenarioWarningDetails(result)) {
    if (detail['disposition'] == 'allowed') {
      continue;
    }
    addBlocker(
      kind: 'unexpectedWarning',
      reason: detail['reason']?.toString() ?? 'requiresInvestigation',
      warning: detail['warning']?.toString(),
    );
  }

  final taskDrift = _asObjectMap(result['taskDrift']);
  final driftDetected =
      taskDrift['driftDetected'] == true || result['taskDriftDetected'] == true;
  if (driftDetected) {
    addBlocker(
      kind: 'taskDrift',
      reason: taskDrift['driftReason']?.toString() ?? 'taskDriftDetected',
    );
  }

  final approvalPath =
      result['approvalPath']?.toString() ?? planModeApprovalPathUnknown;
  if (approvalPath == planModeApprovalPathUnknown &&
      _shouldRequireKnownApprovalPath(result)) {
    addBlocker(kind: 'unknownApprovalPath', reason: 'approvalPathUnknown');
  }

  if (result['postScenarioSettled'] == false) {
    addBlocker(
      kind: 'postScenarioUnsettled',
      reason: 'postScenarioDidNotSettle',
    );
  }

  return blockers;
}

bool _shouldRequireKnownApprovalPath(Map<String, Object?> result) {
  if (result['status'] == 'passed') {
    return true;
  }

  final lastKnownPhase = result['lastKnownPhase']?.toString().trim();
  if (lastKnownPhase != null && lastKnownPhase.isNotEmpty) {
    return true;
  }

  final phaseTimings = _asObjectMap(result['phaseTimings']);
  const approvalOrExecutionMarkers = <String>[
    'approvalTappedAt',
    'firstTaskStartedAt',
    'firstTaskCompletedAt',
    'nextTaskStartedAt',
    'validationStartedAt',
    'lastTaskProgressAt',
  ];
  return approvalOrExecutionMarkers.any((key) {
    final value = phaseTimings[key]?.toString().trim();
    return value != null && value.isNotEmpty;
  });
}

Map<String, Object> buildPlanModeSuiteReportQualitySummary(
  List<Map<String, Object?>> suiteResults,
) {
  final blockers = <Map<String, Object?>>[];
  final byReason = <String, int>{};
  final blockedScenarios = <String>{};

  for (final result in suiteResults) {
    final scenarioBlockers = collectPlanModeScenarioQualityBlockers(result);
    for (final blocker in scenarioBlockers) {
      blockers.add(blocker);
      final reason = blocker['reason']?.toString() ?? 'unknown';
      byReason.update(reason, (count) => count + 1, ifAbsent: () => 1);
      blockedScenarios.add(blocker['scenario']?.toString() ?? 'unknown');
    }
  }

  return <String, Object>{
    'ready': blockers.isEmpty,
    'blockerCount': blockers.length,
    'blockedScenarioCount': blockedScenarios.length,
    'byReason': byReason,
    'blockers': blockers,
  };
}

Map<String, Object?>? _normalizeScenarioWarningDetail({
  required Map<String, Object?> result,
  required Map<String, Object?> detail,
}) {
  final warning = detail['warning']?.toString().trim();
  if (warning == null || warning.isEmpty) {
    return null;
  }
  final disposition = detail['disposition']?.toString().trim();
  final normalizedDisposition = disposition == null || disposition.isEmpty
      ? (_asList(result['allowedWarnings']).contains(warning)
            ? 'allowed'
            : 'unexpected')
      : disposition;
  final reason = detail['reason']?.toString().trim();

  return <String, Object?>{
    'scenario': result['scenario']?.toString() ?? 'unknown',
    'warning': warning,
    'disposition': normalizedDisposition,
    'reason': reason == null || reason.isEmpty
        ? (normalizedDisposition == 'allowed'
              ? 'allowedWarning'
              : 'requiresInvestigation')
        : reason,
    if (result['scenarioReport'] != null)
      'report': result['scenarioReport'].toString(),
    if (result['scenarioLog'] != null) 'log': result['scenarioLog'].toString(),
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
