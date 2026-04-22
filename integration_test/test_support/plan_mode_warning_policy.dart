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
    final isAllowedByPostCompletionRecovery =
        _isRecoverablePostCompletionWarning(
          warning: warning,
          logs: logs,
        );
    final isAllowedByContinuationRecovery =
        _isRecoverableContinuationStreamWarning(
          warning: warning,
          logs: logs,
        );
    if (isAllowedByPattern ||
        isAllowedByRecovery ||
        isAllowedByPostCompletionRecovery ||
        isAllowedByContinuationRecovery) {
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

bool _isRecoverablePostCompletionWarning({
  required String warning,
  required List<String> logs,
}) {
  final isMemoryExtractionWarning =
      warning.contains('[Memory] LLM memory extraction error:') ||
      warning.contains('[LLM] createChatCompletion error:');
  if (!isMemoryExtractionWarning) {
    return false;
  }

  final warningIndex = logs.indexOf(warning);
  if (warningIndex == -1) {
    return false;
  }

  final finalAnswerIndex = logs.lastIndexWhere(
    (line) => line.contains('[LLM] ========== streamChatCompletion =========='),
  );
  if (finalAnswerIndex == -1 || warningIndex <= finalAnswerIndex) {
    return false;
  }

  final hasLaterToolLoop = logs.skip(warningIndex + 1).any(
    (line) =>
        line.contains('[Tool] LLM requested additional tool calls') ||
        line.contains('finishReason: FinishReason.toolCalls'),
  );
  if (hasLaterToolLoop) {
    return false;
  }

  final hasPairedMemoryWarning = logs.skip(warningIndex).any(
    (line) => line.contains('[Memory] LLM memory extraction error:'),
  );
  return hasPairedMemoryWarning;
}

bool _isRecoverableContinuationStreamWarning({
  required String warning,
  required List<String> logs,
}) {
  final isContinuationWarning =
      warning.contains('[LLM] streamChatCompletion error:') ||
      warning.contains('[ChatNotifier] _continueAfterContentToolResults onError:');
  if (!isContinuationWarning ||
      !warning.contains('Connection closed before full header was received')) {
    return false;
  }

  final warningIndex = logs.indexOf(warning);
  if (warningIndex == -1) {
    return false;
  }

  final laterLogs = logs.skip(warningIndex + 1);
  final hasLaterToolLoop = laterLogs.any(
    (line) =>
        line.contains('[Tool] LLM requested additional tool calls') ||
        line.contains('finishReason: FinishReason.toolCalls') ||
        line.contains('[ContentTool] Detected tool_call(s):'),
  );
  if (hasLaterToolLoop) {
    return false;
  }

  final hasLaterMemoryPhase = laterLogs.any(
    (line) =>
        line.contains('[Memory] ') ||
        line.contains(
          'You extract reusable user memory from a conversation.',
        ),
  );
  if (!hasLaterMemoryPhase) {
    return false;
  }

  final earlierLogs = logs.take(warningIndex);
  final hasValidationExecution = earlierLogs.any(
    (line) =>
        line.contains('[ContentTool]   - local_execute_command:') ||
        line.contains('[ContentTool]   - ping:') ||
        line.contains('[ContentTool]   - dns_lookup:') ||
        line.contains('[ContentTool]   - http_status:'),
  );
  return hasValidationExecution;
}
