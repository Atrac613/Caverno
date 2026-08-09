import 'final_answer_claim_detector.dart';

class ConversationExecutionProgressInferenceResult {
  const ConversationExecutionProgressInferenceResult({
    required this.summary,
    required this.reportsCompletion,
    required this.reportsBlocker,
    required this.reportsValidationSuccess,
    required this.hasUnexecutedEvidence,
  });

  final String summary;
  final bool reportsCompletion;
  final bool reportsBlocker;
  final bool reportsValidationSuccess;
  final bool hasUnexecutedEvidence;
}

/// Extracts advisory claims from assistant task narration.
///
/// This service intentionally cannot import workflow entities or return task
/// and validation status. Saved target state, typed command outcomes, and tool
/// result completion assessments own those verdicts. Callers may use these
/// claims to select a summary or trigger a grounded check, never as terminal
/// evidence by themselves.
abstract final class ConversationExecutionProgressInference {
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
    required String taskTitle,
    required bool isValidationRun,
    String? fallbackAssistantResponse,
  }) {
    final primary = _inferSingle(
      assistantResponse: assistantResponse,
      taskTitle: taskTitle,
      isValidationRun: isValidationRun,
    );
    final fallback = fallbackAssistantResponse?.trim();
    if (fallback == null || fallback.isEmpty || primary.hasUnexecutedEvidence) {
      return primary;
    }

    final fallbackResult = _inferSingle(
      assistantResponse: fallback,
      taskTitle: taskTitle,
      isValidationRun: isValidationRun,
    );
    return _shouldPreferFallback(primary: primary, fallback: fallbackResult)
        ? fallbackResult
        : primary;
  }

  static ConversationExecutionProgressInferenceResult _inferSingle({
    required String assistantResponse,
    required String taskTitle,
    required bool isValidationRun,
  }) {
    final normalizedResponse = assistantResponse.trim();
    if (normalizedResponse.isEmpty) {
      return ConversationExecutionProgressInferenceResult(
        summary: isValidationRun
            ? 'Validation ran without a structured assistant summary.'
            : 'Task execution continued without a structured assistant summary.',
        reportsCompletion: false,
        reportsBlocker: false,
        reportsValidationSuccess: false,
        hasUnexecutedEvidence: false,
      );
    }

    final summary = _extractSummary(normalizedResponse);
    final hasUnexecutedEvidence = _hasUnexecutedEvidence(normalizedResponse);
    if (hasUnexecutedEvidence) {
      return ConversationExecutionProgressInferenceResult(
        summary: summary,
        reportsCompletion: false,
        reportsBlocker: false,
        reportsValidationSuccess: false,
        hasUnexecutedEvidence: true,
      );
    }

    final lowercaseResponse = normalizedResponse.toLowerCase();
    final completionEvidenceText = _withoutMarkdownCode(lowercaseResponse);
    final hasBlockedSignal = _containsAny(lowercaseResponse, _blockedSignals);
    final hasCompletionSignal = _containsAny(
      completionEvidenceText,
      _completionSignals,
    );
    final hasValidationPassedSignal =
        _containsAny(completionEvidenceText, _validationPassedSignals) ||
        _looksLikeValidationSuccessNarrative(completionEvidenceText);
    final looksLikeTaskTransitionNarration = _containsAny(
      lowercaseResponse,
      _transitionNarrationSignals,
    );
    final looksLikeRecoverableMissingTargetNarrative =
        _looksLikeRecoverableMissingTargetNarrative(lowercaseResponse);
    final normalizedTaskTitle = taskTitle.trim().toLowerCase();
    final taskTitleIndex = normalizedTaskTitle.isEmpty
        ? -1
        : lowercaseResponse.indexOf(normalizedTaskTitle);
    final mentionsExplicitTaskCompletion =
        taskTitleIndex >= 0 &&
        _containsAny(lowercaseResponse.substring(taskTitleIndex), const [
          'has been completed',
          'is complete',
          'is completed',
          'was completed',
        ]);
    final recoverableBlocker =
        hasBlockedSignal &&
        looksLikeRecoverableMissingTargetNarrative &&
        !hasValidationPassedSignal;
    final completionOverridesBlocker =
        hasBlockedSignal &&
        (hasValidationPassedSignal || mentionsExplicitTaskCompletion);
    final transitionWithoutTaskCompletion =
        looksLikeTaskTransitionNarration &&
        !mentionsExplicitTaskCompletion &&
        !hasValidationPassedSignal;

    return ConversationExecutionProgressInferenceResult(
      summary: summary,
      reportsCompletion:
          !recoverableBlocker &&
          !transitionWithoutTaskCompletion &&
          (!hasBlockedSignal || completionOverridesBlocker) &&
          (hasCompletionSignal ||
              hasValidationPassedSignal ||
              mentionsExplicitTaskCompletion),
      reportsBlocker:
          hasBlockedSignal &&
          !recoverableBlocker &&
          !completionOverridesBlocker,
      reportsValidationSuccess: hasValidationPassedSignal,
      hasUnexecutedEvidence: false,
    );
  }

  static bool _shouldPreferFallback({
    required ConversationExecutionProgressInferenceResult primary,
    required ConversationExecutionProgressInferenceResult fallback,
  }) {
    final primaryHasClaim =
        primary.reportsCompletion ||
        primary.reportsBlocker ||
        primary.reportsValidationSuccess;
    final fallbackHasClaim =
        fallback.reportsCompletion ||
        fallback.reportsBlocker ||
        fallback.reportsValidationSuccess;
    if (!primaryHasClaim && fallbackHasClaim) {
      return true;
    }
    return primary.reportsBlocker && fallback.reportsCompletion;
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

  static bool _hasUnexecutedEvidence(String response) {
    return response.contains(
          FinalAnswerClaimDetector.unexecutedCommandActionNotice,
        ) ||
        response.contains(
          FinalAnswerClaimDetector.unexecutedFileSideEffectNotice,
        ) ||
        response.contains(
          FinalAnswerClaimDetector.unverifiedReadOnlyInspectionNotice,
        );
  }

  static String _withoutMarkdownCode(String value) {
    return value
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'`[^`\n]*`'), ' ');
  }

  static bool _looksLikeValidationSuccessNarrative(String value) {
    final mentionsValidation =
        value.contains('validation command') ||
        value.contains('validation result') ||
        value.contains('validation:') ||
        value.contains('validation step');
    if (!mentionsValidation) {
      return false;
    }
    return value.contains('was successful') ||
        value.contains('succeeded') ||
        value.contains('ran successfully') ||
        value.contains('working as expected') ||
        value.contains('result: success') ||
        value.contains('exit code 0') ||
        value.contains('exit_code: 0');
  }

  static bool _looksLikeRecoverableMissingTargetNarrative(String value) {
    if (!value.contains('validation command')) {
      return false;
    }
    final mentionsMissingTarget =
        value.contains('before the target file existed') ||
        value.contains('before every required target file existed') ||
        value.contains('before the required target file existed');
    if (!mentionsMissingTarget) {
      return false;
    }
    return value.contains('goal now is to implement the task') ||
        value.contains('plan:') ||
        value.contains('create `') ||
        value.contains('create ping_cli.py');
  }
}
