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

  static const _blockerSignatureStopWords = <String>{
    'a',
    'after',
    'am',
    'an',
    'are',
    'because',
    'been',
    'being',
    'blocked',
    'blocker',
    'by',
    'can',
    'cannot',
    'due',
    'for',
    'from',
    'i',
    'is',
    'it',
    'of',
    'on',
    'proceed',
    'proceeding',
    't',
    'the',
    'to',
    'was',
    'we',
    'were',
    'when',
    'while',
    'with',
  };

  static const _permissionActionAliases = <String, String>{
    'execute': 'executing',
    'executing': 'executing',
    'open': 'opening',
    'opening': 'opening',
    'read': 'reading',
    'reading': 'reading',
    'run': 'running',
    'running': 'running',
    'write': 'writing',
    'writing': 'writing',
  };

  // Goal-scoped claims may positionally override earlier incomplete narration
  // (unlike _genericCompletionSignals, which any incomplete phrase disables).
  // Accepted residual miss: a subset-qualified claim after a remaining-work
  // statement — e.g. "残りはAPI側です。UI側はすべて完了しました。" — still
  // completes the goal; substrings cannot see the 〜は topic marker scoping
  // すべて完了 to a component. Kept deliberately: tool-backed turns are guarded
  // by ToolResultCompletionEvidence.hasBlockingEvidence, /goal resume recovers
  // a wrong completion, and chains are budget-bounded. Do not add more lexical
  // rules here; if this hurts in practice, escalate to a secondary-LLM verdict
  // instead (see FOR_ME.md, Lesson 9).
  static const _goalScopedCompletionSignals = <String>[
    'goal is complete',
    'goal complete',
    'goal completed',
    'task is complete',
    'all tasks are complete',
    'all tasks completed',
    'all checks passed',
    'all verification checks passed',
    'passes all verification checks',
    'verifier exited with code 0',
    '\u3059\u3079\u3066\u5b8c\u4e86',
    '\u5168\u3066\u5b8c\u4e86',
    '\u3059\u3079\u3066\u306e\u30c1\u30a7\u30c3\u30af\u304c\u901a\u308a\u307e\u3057\u305f',
    '\u5168\u3066\u306e\u30c1\u30a7\u30c3\u30af\u304c\u901a\u308a\u307e\u3057\u305f',
    '\u691c\u8a3c\u304c\u3059\u3079\u3066\u901a\u308a\u307e\u3057\u305f',
    '\u691c\u8a3c\u304c\u5168\u3066\u901a\u308a\u307e\u3057\u305f',
  ];

  static const _genericCompletionSignals = <String>[
    'task complete',
    'task completed',
    'work is complete',
    'work complete',
    'work completed',
    'implementation is complete',
    'implementation complete',
    'implementation completed',
    'tests passed',
    'validation passed',
    'validated successfully',
    'completed successfully',
    'successfully completed',
    '\u5b8c\u4e86\u3057\u307e\u3057\u305f',
    '\u5b8c\u4e86\u6e08\u307f',
    '\u4fdd\u5b58\u3057\u307e\u3057\u305f',
    '\u4fdd\u5b58\u6e08\u307f',
    '\u66f4\u65b0\u3057\u307e\u3057\u305f',
    '\u4f5c\u6210\u3057\u307e\u3057\u305f',
    '\u8ffd\u52a0\u3057\u307e\u3057\u305f',
    '\u5b9f\u88c5\u3057\u307e\u3057\u305f',
    '\u691c\u8a3c\u304c\u901a\u308a\u307e\u3057\u305f',
    '\u30c6\u30b9\u30c8\u304c\u901a\u308a\u307e\u3057\u305f',
    '\u691c\u8a3c\u6210\u529f',
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
    'remaining work',
    'remaining task',
    'remaining tasks',
    'remaining validation',
    'remaining check',
    'remaining checks',
    'remaining step',
    'remaining steps',
    'remaining file',
    'remaining files',
    'remaining item',
    'remaining items',
    'remaining issue',
    'remaining issues',
    'remaining blocker',
    'remaining blockers',
    'remaining change',
    'remaining changes',
    'remaining implementation',
    'remaining edits',
    'left to do',
    'still remain',
    'still remains',
    'remains to be done',
    'still need',
    'still needs',
    'pending',
    'blocked',
    'cannot proceed',
    'can\'t proceed',
    'unable to proceed',
    '\u5b8c\u4e86\u3057\u3066\u3044\u307e\u305b\u3093',
    '\u672a\u5b8c\u4e86',
    '\u6b8b\u3063\u3066\u3044\u307e\u3059',
    '\u6b8b\u308a',
    '\u4fdd\u7559\u4e2d',
    '\u30d6\u30ed\u30c3\u30af',
    '\u9032\u3081\u307e\u305b\u3093',
    '\u7d9a\u884c\u3067\u304d\u307e\u305b\u3093',
  ];

  static const _recoverableFailureSignals = <String>[
    'failed',
    'failure',
    '\u5931\u6557',
  ];

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
    '\u901a\u308a\u307e\u3057\u305f',
    '\u6210\u529f\u3057\u307e\u3057\u305f',
    '\u89e3\u6d88\u3057\u307e\u3057\u305f',
    '\u4fee\u6b63\u3057\u307e\u3057\u305f',
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
    final taskList = tasks.toList(growable: false);
    final normalizedResponse = assistantResponse.trim();
    final lowercaseResponse = normalizedResponse.toLowerCase();
    final summary = _extractSummary(normalizedResponse);

    if (_allTasksCompleted(taskList)) {
      return ConversationGoalProgressInferenceResult(
        status: ConversationGoalStatus.completed,
        completionSummary: summary.isEmpty
            ? 'All saved workflow tasks are complete.'
            : summary,
      );
    }

    // A task-scoped execution turn can truthfully report completion while
    // later saved tasks are still pending. In that case the persisted task
    // states, rather than lexical completion in the assistant response, own
    // the aggregate goal lifecycle.
    if (taskList.isEmpty && _looksComplete(lowercaseResponse)) {
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
        .replaceAll(
          RegExp(r'\baccess\s+(?:was\s+)?denied\b'),
          'permission denied',
        )
        .replaceAll(
          RegExp(r'\bpermission\s+(?:was\s+)?denied\b'),
          'permission denied',
        )
        .replaceAll(
          RegExp(r'\bwaiting\s+(?:on|for)\s+(?:the\s+)?user\b'),
          'waiting user',
        )
        .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final tokens = normalized
        .split(' ')
        .where((token) => token.isNotEmpty)
        .where((token) => !_blockerSignatureStopWords.contains(token))
        .toList(growable: false);
    final permissionDeniedSignature = _permissionDeniedSignature(tokens);
    final signature = permissionDeniedSignature ?? tokens.join(' ');
    final fallback = signature.isEmpty ? normalized : signature;
    if (fallback.length <= 96) {
      return fallback;
    }
    return fallback.substring(0, 96).trimRight();
  }

  static String? _permissionDeniedSignature(List<String> tokens) {
    final permissionIndex = tokens.indexOf('permission');
    if (permissionIndex < 0 ||
        permissionIndex + 1 >= tokens.length ||
        tokens[permissionIndex + 1] != 'denied') {
      return null;
    }
    for (final token in tokens.skip(permissionIndex + 2)) {
      final action = _permissionActionAliases[token];
      if (action != null) {
        return 'permission denied $action';
      }
    }
    return 'permission denied';
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
    final incompleteEnd = _lastMatchEndOfAny(
      lowercaseResponse,
      _unresolvedIncompleteSignals,
    );
    final genericCompletionIndex = _lastIndexOfAnyAfter(
      lowercaseResponse,
      _genericCompletionSignals,
      start: incompleteEnd == 0 ? 0 : lowercaseResponse.length,
    );
    final goalScopedCompletionIndex = _lastIndexOfAnyAfter(
      lowercaseResponse,
      _goalScopedCompletionSignals,
      start: incompleteEnd,
    );
    final completionIndex = genericCompletionIndex > goalScopedCompletionIndex
        ? genericCompletionIndex
        : goalScopedCompletionIndex;
    if (completionIndex < 0) {
      return false;
    }
    final resolvedFailureIndex = _lastIndexOfAny(
      lowercaseResponse,
      _resolvedFailureSignals,
    );
    final recoverableFailureIndex = _lastIndexOfAny(
      lowercaseResponse,
      _recoverableFailureSignals,
    );
    if (recoverableFailureIndex >= 0 &&
        resolvedFailureIndex < recoverableFailureIndex) {
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

  static int _lastIndexOfAnyAfter(
    String value,
    Iterable<String> signals, {
    required int start,
  }) {
    var latestIndex = -1;
    for (final signal in signals) {
      var searchStart = 0;
      while (searchStart < value.length) {
        final index = value.indexOf(signal, searchStart);
        if (index < 0) {
          break;
        }
        if (index >= start && index > latestIndex) {
          latestIndex = index;
        }
        searchStart = index + signal.length;
      }
    }
    return latestIndex;
  }

  static int _lastIndexOfAny(String value, Iterable<String> signals) {
    var latestIndex = -1;
    for (final signal in signals) {
      final index = value.lastIndexOf(signal);
      if (index > latestIndex) {
        latestIndex = index;
      }
    }
    return latestIndex;
  }

  static int _lastMatchEndOfAny(String value, Iterable<String> signals) {
    var latestEnd = 0;
    for (final signal in signals) {
      final index = value.lastIndexOf(signal);
      if (index < 0) {
        continue;
      }
      final end = index + signal.length;
      if (end > latestEnd) {
        latestEnd = end;
      }
    }
    return latestEnd;
  }
}
