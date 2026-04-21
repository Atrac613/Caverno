class PlanModeWarningSummary {
  const PlanModeWarningSummary({
    required this.allowedWarnings,
    required this.unexpectedWarnings,
  });

  final List<String> allowedWarnings;
  final List<String> unexpectedWarnings;
}

PlanModeWarningSummary summarizeScenarioWarnings({
  required List<String> warnings,
  required List<String> allowedPatterns,
  required List<String> logs,
}) {
  final allowedWarnings = <String>[];
  final unexpectedWarnings = <String>[];

  for (final warning in warnings) {
    final isAllowedByPattern = allowedPatterns.any(warning.contains);
    final isAllowedByRecovery = _isRecoverableCreateParseWarning(
      warning: warning,
      logs: logs,
    );
    if (isAllowedByPattern || isAllowedByRecovery) {
      allowedWarnings.add(warning);
    } else {
      unexpectedWarnings.add(warning);
    }
  }

  return PlanModeWarningSummary(
    allowedWarnings: allowedWarnings,
    unexpectedWarnings: unexpectedWarnings,
  );
}

bool _isRecoverableCreateParseWarning({
  required String warning,
  required List<String> logs,
}) {
  if (!warning.contains(
    '[LLM] Recovered raw text response after create parse failure',
  )) {
    return false;
  }

  final warningIndex = logs.indexOf(warning);
  if (warningIndex == -1) {
    return false;
  }

  const recoveryMarkers = <String>[
    '[Workflow] Workflow proposal ready',
    '[Workflow] Task proposal ready',
    '[Workflow] Task status changed:',
    '[Memory] LLM memory extraction succeeded',
    '[Memory] Failed to parse LLM memory extraction JSON (falling back to rule-based)',
    '[Memory] Repaired malformed memory extraction JSON',
  ];

  for (var index = warningIndex + 1; index < logs.length; index += 1) {
    final line = logs[index];
    if (recoveryMarkers.any(line.contains)) {
      return true;
    }
  }

  return false;
}
