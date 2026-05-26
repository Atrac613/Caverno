import '../entities/conversation_goal.dart';
import '../entities/conversation_workflow.dart';

class ConversationGoalProgressInferenceResult {
  const ConversationGoalProgressInferenceResult({
    this.status,
    this.completionSummary,
    this.blockedReason,
    this.blockerSignature,
  });

  final ConversationGoalStatus? status;
  final String? completionSummary;
  final String? blockedReason;
  final String? blockerSignature;

  bool get hasCompletion => status == ConversationGoalStatus.completed;

  bool get hasBlocker => blockedReason != null && blockerSignature != null;
}

class ConversationGoalProgressInference {
  static const int blockedRepeatThreshold = 3;

  static const _completionSignals = <String>[
    'goal is complete',
    'goal complete',
    'goal completed',
    'work is complete',
    'work complete',
    'work completed',
    'implementation is complete',
    'implementation complete',
    'implementation completed',
    'task is complete',
    'task complete',
    'task completed',
    'all tasks are complete',
    'all tasks completed',
    'all checks passed',
    'tests passed',
    'validation passed',
    'validated successfully',
    'completed successfully',
    'successfully completed',
  ];

  static const _unresolvedIncompleteSignals = <String>[
    'not complete',
    'not completed',
    'not done',
    'not all tests passed',
    'tests did not pass',
    'validation did not pass',
    'checks did not pass',
    'did not pass',
    'do not pass',
    'remaining',
    'still need',
    'still needs',
    'pending',
    'blocked',
    'cannot proceed',
    'can\'t proceed',
    'unable to proceed',
  ];

  static const _recoverableFailureSignals = <String>['failed', 'failure'];

  static const _resolvedFailureSignals = <String>[
    'test exited with code 0',
    'test run exited with code 0',
    'subsequent test run exited with code 0',
    'rerun exited with code 0',
    'exited with code 0',
    'exit code 0',
    'now passes',
    'now pass',
    'confirmed the fix',
    'confirming the fix',
  ];

  static const _blockedSignals = <String>[
    'blocked',
    'cannot proceed',
    'can\'t proceed',
    'unable to proceed',
    'permission denied',
    'access denied',
    'requires user input',
    'need user input',
    'waiting for user',
    'waiting on user',
    'requires approval',
    'missing required',
    'missing information',
    'external service is unavailable',
    'server is unavailable',
  ];

  static const _resolvedBlockerSignals = <String>[
    'unblocked',
    'resolved',
    'fixed',
    'passed',
    'complete',
    'completed',
  ];

  static ConversationGoalProgressInferenceResult infer({
    required String assistantResponse,
    required Iterable<ConversationWorkflowTask> tasks,
  }) {
    final normalizedResponse = assistantResponse.trim();
    final lowercaseResponse = normalizedResponse.toLowerCase();
    final summary = _extractSummary(normalizedResponse);

    if (_allTasksCompleted(tasks)) {
      return ConversationGoalProgressInferenceResult(
        status: ConversationGoalStatus.completed,
        completionSummary: summary.isEmpty
            ? 'All saved workflow tasks are complete.'
            : summary,
      );
    }

    if (_looksComplete(lowercaseResponse)) {
      return ConversationGoalProgressInferenceResult(
        status: ConversationGoalStatus.completed,
        completionSummary: summary.isEmpty
            ? 'The assistant reported that the goal is complete.'
            : summary,
      );
    }

    if (_looksBlocked(lowercaseResponse)) {
      final blockedReason = summary.isEmpty
          ? 'The assistant reported a blocking condition.'
          : summary;
      return ConversationGoalProgressInferenceResult(
        blockedReason: blockedReason,
        blockerSignature: blockerSignatureFor(blockedReason),
      );
    }

    return const ConversationGoalProgressInferenceResult();
  }

  static String blockerSignatureFor(String blockedReason) {
    final normalized = blockedReason
        .toLowerCase()
        .replaceAll(RegExp(r'`[^`]*`'), ' ')
        .replaceAll(RegExp(r'[/\\][^\s,.;:]+'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.length <= 96) {
      return normalized;
    }
    return normalized.substring(0, 96).trimRight();
  }

  static bool _allTasksCompleted(Iterable<ConversationWorkflowTask> tasks) {
    final taskList = tasks.toList(growable: false);
    return taskList.isNotEmpty &&
        taskList.every(
          (task) => task.status == ConversationWorkflowTaskStatus.completed,
        );
  }

  static bool _looksComplete(String lowercaseResponse) {
    if (lowercaseResponse.isEmpty) {
      return false;
    }
    if (!_containsAny(lowercaseResponse, _completionSignals)) {
      return false;
    }
    if (_containsAny(lowercaseResponse, _unresolvedIncompleteSignals)) {
      return false;
    }
    if (_containsAny(lowercaseResponse, _recoverableFailureSignals) &&
        !_containsAny(lowercaseResponse, _resolvedFailureSignals)) {
      return false;
    }
    return true;
  }

  static bool _looksBlocked(String lowercaseResponse) {
    if (lowercaseResponse.isEmpty) {
      return false;
    }
    if (!_containsAny(lowercaseResponse, _blockedSignals)) {
      return false;
    }
    return !_containsAny(lowercaseResponse, _resolvedBlockerSignals);
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
