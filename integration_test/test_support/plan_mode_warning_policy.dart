class PlanModeWarningSummary {
  const PlanModeWarningSummary({
    required this.allowedWarnings,
    required this.unexpectedWarnings,
    required this.details,
  });

  final List<String> allowedWarnings;
  final List<String> unexpectedWarnings;
  final List<PlanModeWarningDetail> details;

  Map<String, Object> toJson() {
    return <String, Object>{
      'counts': <String, int>{
        'warnings': details.length,
        'allowedWarnings': allowedWarnings.length,
        'unexpectedWarnings': unexpectedWarnings.length,
      },
      'details': details
          .map((detail) => detail.toJson())
          .toList(growable: false),
    };
  }
}

class PlanModeWarningDetail {
  const PlanModeWarningDetail({
    required this.warning,
    required this.disposition,
    required this.reason,
  });

  final String warning;
  final String disposition;
  final String reason;

  bool get isAllowed => disposition == 'allowed';

  Map<String, String> toJson() {
    return <String, String>{
      'warning': warning,
      'disposition': disposition,
      'reason': reason,
    };
  }
}

PlanModeWarningSummary summarizeScenarioWarnings({
  required List<String> warnings,
  required List<String> allowedPatterns,
  required List<String> logs,
}) {
  final allowedWarnings = <String>[];
  final unexpectedWarnings = <String>[];
  final details = <PlanModeWarningDetail>[];

  for (final warning in warnings) {
    final detail = _classifyScenarioWarning(
      warning: warning,
      allowedPatterns: allowedPatterns,
      logs: logs,
    );
    details.add(detail);
    if (detail.isAllowed) {
      allowedWarnings.add(warning);
    } else {
      unexpectedWarnings.add(warning);
    }
  }

  return PlanModeWarningSummary(
    allowedWarnings: allowedWarnings,
    unexpectedWarnings: unexpectedWarnings,
    details: details,
  );
}

PlanModeWarningDetail _classifyScenarioWarning({
  required String warning,
  required List<String> allowedPatterns,
  required List<String> logs,
}) {
  if (allowedPatterns.any(warning.contains)) {
    return PlanModeWarningDetail(
      warning: warning,
      disposition: 'allowed',
      reason: 'allowedPattern',
    );
  }
  if (_isRecoverableCreateParseWarning(warning: warning, logs: logs)) {
    return PlanModeWarningDetail(
      warning: warning,
      disposition: 'allowed',
      reason: 'recoveredCreateParseWarning',
    );
  }
  if (_isRecoverablePostCompletionWarning(warning: warning, logs: logs)) {
    return PlanModeWarningDetail(
      warning: warning,
      disposition: 'allowed',
      reason: 'postCompletionMemoryExtraction',
    );
  }
  if (_isRecoverableMemoryPhaseTransportWarning(warning: warning, logs: logs)) {
    return PlanModeWarningDetail(
      warning: warning,
      disposition: 'allowed',
      reason: 'recoveredMemoryPhaseTransport',
    );
  }
  if (_isRecoverableContinuationStreamWarning(warning: warning, logs: logs)) {
    return PlanModeWarningDetail(
      warning: warning,
      disposition: 'allowed',
      reason: 'recoveredContinuationStream',
    );
  }
  return PlanModeWarningDetail(
    warning: warning,
    disposition: 'unexpected',
    reason: 'requiresInvestigation',
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

  const recoveryMarkers = <String>[
    '[Workflow] Workflow proposal ready',
    '[Workflow] Task proposal ready',
    '[Workflow] Task status changed:',
    '[Memory] LLM memory extraction succeeded',
    '[Memory] Failed to parse LLM memory extraction JSON (falling back to rule-based)',
    '[Memory] Repaired malformed memory extraction JSON',
  ];

  for (final warningIndex in _warningIndices(warning, logs)) {
    for (var index = warningIndex + 1; index < logs.length; index += 1) {
      final line = logs[index];
      if (recoveryMarkers.any(line.contains)) {
        return true;
      }
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

  for (final warningIndex in _warningIndices(warning, logs)) {
    final finalAnswerIndex = logs.lastIndexWhere(
      (line) =>
          line.contains('[LLM] ========== streamChatCompletion =========='),
    );
    if (finalAnswerIndex == -1 || warningIndex <= finalAnswerIndex) {
      continue;
    }

    final hasLaterToolLoop = logs
        .skip(warningIndex + 1)
        .any(
          (line) =>
              line.contains('[Tool] LLM requested additional tool calls') ||
              line.contains('finishReason: FinishReason.toolCalls'),
        );
    if (hasLaterToolLoop) {
      continue;
    }

    final hasPairedMemoryWarning = logs
        .skip(warningIndex)
        .any((line) => line.contains('[Memory] LLM memory extraction error:'));
    if (hasPairedMemoryWarning) {
      return true;
    }
  }
  return false;
}

bool _isRecoverableMemoryPhaseTransportWarning({
  required String warning,
  required List<String> logs,
}) {
  final isMemoryPhaseWarning =
      (warning.contains('[LLM] createChatCompletion error:') ||
          warning.contains('[Memory] LLM memory extraction error:')) &&
      warning.contains('Connection closed before full header was received');
  if (!isMemoryPhaseWarning) {
    return false;
  }

  const recoveryMarkers = <String>[
    '[Tool] Sending hidden prompt in tool-aware mode',
    '[Tool] Sending hidden prompt in normal mode',
    '[Tool] Sending in tool-aware mode (MCP)',
    '[Tool] Sending in normal mode',
    '[Workflow] Workflow proposal ready',
    '[Workflow] Task proposal ready',
    '[Workflow] Task status changed:',
    '[LLM] ========== streamChatCompletionWithTools ==========',
  ];

  for (final warningIndex in _warningIndices(warning, logs)) {
    final hasPairedMemoryWarning = logs
        .skip(warningIndex)
        .any((line) => line.contains('[Memory] LLM memory extraction error:'));
    if (!hasPairedMemoryWarning) {
      continue;
    }

    final hasLaterRecovery = logs
        .skip(warningIndex + 1)
        .any((line) => recoveryMarkers.any(line.contains));
    if (hasLaterRecovery) {
      return true;
    }
  }

  return false;
}

bool _isRecoverableContinuationStreamWarning({
  required String warning,
  required List<String> logs,
}) {
  final isContinuationWarning =
      warning.contains('[LLM] streamChatCompletion error:') ||
      warning.contains(
        '[ChatNotifier] _continueAfterContentToolResults onError:',
      );
  if (!isContinuationWarning ||
      !warning.contains('Connection closed before full header was received')) {
    return false;
  }

  for (final warningIndex in _warningIndices(warning, logs)) {
    final laterLogs = logs.skip(warningIndex + 1);
    final earlierLogs = logs.take(warningIndex);
    final hasValidationExecution = earlierLogs.any(
      (line) =>
          line.contains('[ContentTool]   - local_execute_command:') ||
          line.contains('[ContentTool]   - ping:') ||
          line.contains('[ContentTool]   - dns_lookup:') ||
          line.contains('[ContentTool]   - http_status:'),
    );
    if (!hasValidationExecution) {
      continue;
    }

    final hasSavedTaskAutoContinuation = laterLogs.any(
      (line) => line.contains(
        'The previous saved task is complete. Continue immediately with the next pending saved task',
      ),
    );
    if (hasSavedTaskAutoContinuation) {
      return true;
    }

    final hasLaterToolLoop = laterLogs.any(
      (line) =>
          line.contains('[Tool] LLM requested additional tool calls') ||
          line.contains('finishReason: FinishReason.toolCalls') ||
          line.contains('[ContentTool] Detected tool_call(s):'),
    );
    if (hasLaterToolLoop) {
      continue;
    }

    final hasLaterMemoryPhase = laterLogs.any(
      (line) =>
          line.contains('[Memory] ') ||
          line.contains(
            'You extract reusable user memory from a conversation.',
          ),
    );
    if (!hasLaterMemoryPhase) {
      continue;
    }
    return true;
  }
  return false;
}

Iterable<int> _warningIndices(String warning, List<String> logs) sync* {
  for (var index = 0; index < logs.length; index += 1) {
    if (logs[index].contains(warning)) {
      yield index;
    }
  }
}
