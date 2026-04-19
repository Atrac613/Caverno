import '../entities/conversation_workflow.dart';

class ConversationExecutionProgressInferenceResult {
  const ConversationExecutionProgressInferenceResult({
    required this.status,
    required this.summary,
    this.blockedReason,
    this.validationStatus = ConversationExecutionValidationStatus.unknown,
    this.validationSummary,
  });

  final ConversationWorkflowTaskStatus status;
  final String summary;
  final String? blockedReason;
  final ConversationExecutionValidationStatus validationStatus;
  final String? validationSummary;
}

class ConversationExecutionProgressInference {
  static const _blockedSignals = <String>[
    'blocked',
    'cannot ',
    'can\'t',
    'unable',
    'failed',
    'failure',
    'error',
    'errors',
    'not found',
    'missing',
    'permission denied',
    'did not pass',
    'failing',
  ];

  static const _completionSignals = <String>[
    'complete',
    'completed',
    'done',
    'finished',
    'implemented',
    'updated',
    'fixed',
    'added',
    'created',
    'resolved',
  ];

  static const _validationPassedSignals = <String>[
    'tests passed',
    'validation passed',
    'all checks passed',
    'passed successfully',
    'validated successfully',
  ];

  static const _transitionNarrationSignals = <String>[
    'the previous saved task is complete',
    'previous saved task is complete',
    'continue immediately with the next pending saved task',
    'the next task is',
    'next task:',
    'ignore the previous saved task context',
  ];

  static ConversationExecutionProgressInferenceResult infer({
    required String assistantResponse,
    required ConversationWorkflowTask task,
    required bool isValidationRun,
    String? fallbackAssistantResponse,
  }) {
    final primary = _inferSingle(
      assistantResponse: assistantResponse,
      task: task,
      isValidationRun: isValidationRun,
    );
    final fallback = fallbackAssistantResponse?.trim();
    if (fallback == null || fallback.isEmpty) {
      return primary;
    }

    final fallbackResult = _inferSingle(
      assistantResponse: fallback,
      task: task,
      isValidationRun: isValidationRun,
    );
    if (_shouldPreferFallback(primary: primary, fallback: fallbackResult)) {
      return fallbackResult;
    }
    return primary;
  }

  static ConversationExecutionProgressInferenceResult _inferSingle({
    required String assistantResponse,
    required ConversationWorkflowTask task,
    required bool isValidationRun,
  }) {
    final normalizedResponse = assistantResponse.trim();
    if (normalizedResponse.isEmpty) {
      return ConversationExecutionProgressInferenceResult(
        status: task.status == ConversationWorkflowTaskStatus.pending
            ? ConversationWorkflowTaskStatus.inProgress
            : task.status,
        summary: isValidationRun
            ? 'Validation ran without a structured assistant summary.'
            : 'Task execution continued without a structured assistant summary.',
        validationStatus: ConversationExecutionValidationStatus.unknown,
      );
    }

    final summary = _extractSummary(normalizedResponse);
    final lowercaseResponse = normalizedResponse.toLowerCase();
    final hasBlockedSignal = _containsAny(lowercaseResponse, _blockedSignals);
    final hasCompletionSignal = _containsAny(
      lowercaseResponse,
      _completionSignals,
    );
    final hasValidationPassedSignal = _containsAny(
      lowercaseResponse,
      _validationPassedSignals,
    );
    final looksLikeTaskTransitionNarration = _containsAny(
      lowercaseResponse,
      _transitionNarrationSignals,
    );

    if (isValidationRun) {
      if (hasBlockedSignal) {
        return ConversationExecutionProgressInferenceResult(
          status: ConversationWorkflowTaskStatus.blocked,
          summary: summary,
          blockedReason: summary,
          validationStatus: ConversationExecutionValidationStatus.failed,
          validationSummary: summary,
        );
      }
      if (hasCompletionSignal) {
        return ConversationExecutionProgressInferenceResult(
          status: ConversationWorkflowTaskStatus.completed,
          summary: summary,
          validationStatus: hasValidationPassedSignal
              ? ConversationExecutionValidationStatus.passed
              : ConversationExecutionValidationStatus.unknown,
          validationSummary: summary,
        );
      }
      return ConversationExecutionProgressInferenceResult(
        status: task.status == ConversationWorkflowTaskStatus.completed
            ? ConversationWorkflowTaskStatus.completed
            : ConversationWorkflowTaskStatus.inProgress,
        summary: summary,
        validationStatus: hasValidationPassedSignal
            ? ConversationExecutionValidationStatus.passed
            : ConversationExecutionValidationStatus.unknown,
        validationSummary: summary,
      );
    }

    if (looksLikeTaskTransitionNarration && !hasValidationPassedSignal) {
      return ConversationExecutionProgressInferenceResult(
        status: task.status == ConversationWorkflowTaskStatus.completed
            ? ConversationWorkflowTaskStatus.completed
            : ConversationWorkflowTaskStatus.inProgress,
        summary: summary,
      );
    }

    if (hasBlockedSignal) {
      return ConversationExecutionProgressInferenceResult(
        status: ConversationWorkflowTaskStatus.blocked,
        summary: summary,
        blockedReason: summary,
      );
    }
    if (hasCompletionSignal || hasValidationPassedSignal) {
      return ConversationExecutionProgressInferenceResult(
        status: ConversationWorkflowTaskStatus.completed,
        summary: summary,
      );
    }
    return ConversationExecutionProgressInferenceResult(
      status: ConversationWorkflowTaskStatus.inProgress,
      summary: summary,
    );
  }

  static bool _shouldPreferFallback({
    required ConversationExecutionProgressInferenceResult primary,
    required ConversationExecutionProgressInferenceResult fallback,
  }) {
    if (fallback.status == primary.status) {
      return false;
    }
    if (primary.status == ConversationWorkflowTaskStatus.inProgress &&
        fallback.status != ConversationWorkflowTaskStatus.inProgress) {
      return true;
    }
    if (primary.status == ConversationWorkflowTaskStatus.blocked &&
        fallback.status == ConversationWorkflowTaskStatus.completed) {
      return true;
    }
    return false;
  }

  static String _extractSummary(String response) {
    final lines = response
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map(_normalizeLine)
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final summary = lines.isEmpty ? response.trim() : lines.first;
    if (summary.length <= 180) {
      return summary;
    }
    return '${summary.substring(0, 177).trimRight()}...';
  }

  static String _normalizeLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed == '```') {
      return '';
    }
    return trimmed.replaceFirst(RegExp(r'^[-*#>\d.\s]+'), '').trim();
  }

  static bool _containsAny(String value, Iterable<String> signals) {
    for (final signal in signals) {
      if (value.contains(signal)) {
        return true;
      }
    }
    return false;
  }
}
