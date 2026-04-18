enum PlanModeFailureClass {
  passed,
  executionStall,
  streamDisconnect,
  unknownTool,
  workflowBlocked,
  workflowProposalParse,
  planningLoop,
  warningFailure,
  toolExecutionFailure,
  unclassified,
}

class PlanModeFailureDiagnostics {
  const PlanModeFailureDiagnostics({
    required this.failureClass,
    required this.lastToolName,
    required this.lastToolFailure,
    required this.lastAssistantSummary,
    required this.lastWorkflowSnapshot,
    required this.stallDurationMs,
    required this.recentLogTail,
  });

  final PlanModeFailureClass failureClass;
  final String? lastToolName;
  final String? lastToolFailure;
  final String? lastAssistantSummary;
  final String? lastWorkflowSnapshot;
  final int? stallDurationMs;
  final List<String> recentLogTail;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'failureClass': failureClass.name,
      'lastToolName': lastToolName,
      'lastToolFailure': lastToolFailure,
      'lastAssistantSummary': lastAssistantSummary,
      'lastWorkflowSnapshot': lastWorkflowSnapshot,
      'stallDurationMs': stallDurationMs,
      'recentLogTail': recentLogTail,
    };
  }
}

PlanModeFailureDiagnostics buildPlanModeFailureDiagnostics({
  required List<String> logs,
  String? errorText,
  String? lastWorkflowSnapshot,
  int? stallDurationMs,
}) {
  final normalizedError = (errorText ?? '').trim();
  return PlanModeFailureDiagnostics(
    failureClass: _classifyFailure(logs: logs, errorText: normalizedError),
    lastToolName: _extractLastToolName(logs),
    lastToolFailure: _extractLastToolFailure(logs),
    lastAssistantSummary: _extractLastAssistantSummary(logs),
    lastWorkflowSnapshot:
        lastWorkflowSnapshot ?? _extractLastWorkflowSnapshot(normalizedError),
    stallDurationMs: stallDurationMs,
    recentLogTail: _extractRecentLogTail(logs),
  );
}

PlanModeFailureClass _classifyFailure({
  required List<String> logs,
  required String errorText,
}) {
  if (errorText.isEmpty) {
    return PlanModeFailureClass.passed;
  }

  final normalizedError = errorText.toLowerCase();
  final normalizedLogs = logs.map((line) => line.toLowerCase()).toList();

  bool logsContain(String pattern) {
    final normalizedPattern = pattern.toLowerCase();
    return normalizedLogs.any((line) => line.contains(normalizedPattern));
  }

  if (normalizedError.contains('workflow execution stalled')) {
    return PlanModeFailureClass.executionStall;
  }
  if (normalizedError.contains('connection closed before full header')) {
    return PlanModeFailureClass.streamDisconnect;
  }
  if (normalizedError.contains('no matching tool available')) {
    return PlanModeFailureClass.unknownTool;
  }
  if (normalizedError.contains(
    'workflow execution finished in a blocked state',
  )) {
    return PlanModeFailureClass.workflowBlocked;
  }
  if (normalizedError.contains('plan proposal did not become ready')) {
    return PlanModeFailureClass.workflowProposalParse;
  }
  if (normalizedError.contains('planning decisions did not settle')) {
    return PlanModeFailureClass.planningLoop;
  }
  if (normalizedError.contains('scenario emitted warnings')) {
    return PlanModeFailureClass.warningFailure;
  }
  if (normalizedError.contains('[contenttool] execution failed')) {
    return PlanModeFailureClass.toolExecutionFailure;
  }

  if (logsContain('connection closed before full header') ||
      logsContain('[llm] streamchatcompletion error:') ||
      logsContain('[llm] createchatcompletion error:')) {
    return PlanModeFailureClass.streamDisconnect;
  }
  if (logsContain('no matching tool available')) {
    return PlanModeFailureClass.unknownTool;
  }
  if (logsContain('[workflow] workflow proposal parse failed')) {
    return PlanModeFailureClass.workflowProposalParse;
  }
  if (logsContain('[contenttool] execution failed:')) {
    return PlanModeFailureClass.toolExecutionFailure;
  }

  return PlanModeFailureClass.unclassified;
}

String? _extractLastToolName(List<String> logs) {
  final pattern = RegExp(r'^\[ContentTool\]\s+-\s+([A-Za-z0-9_]+):');
  for (final line in logs.reversed) {
    final match = pattern.firstMatch(line);
    if (match != null) {
      return match.group(1);
    }
  }
  return null;
}

String? _extractLastToolFailure(List<String> logs) {
  for (final line in logs.reversed) {
    if (line.contains('[ContentTool] Execution failed:')) {
      return line;
    }
  }
  return null;
}

String? _extractLastAssistantSummary(List<String> logs) {
  for (final line in logs.reversed) {
    if (!_isAssistantContentLine(line)) {
      continue;
    }
    return _trimLogLine(line, maxLength: 240);
  }
  return null;
}

bool _isAssistantContentLine(String line) {
  if (!line.startsWith('[LLM] ')) {
    return false;
  }
  const excludedFragments = <String>[
    '===',
    'model:',
    'finishReason:',
    'toolCalls count:',
    'Sending request...',
    'stackTrace:',
    '=== End',
    '=== Request',
    'assistantContent:',
  ];
  for (final fragment in excludedFragments) {
    if (line.contains(fragment)) {
      return false;
    }
  }
  return line.contains('<think>') ||
      line.startsWith('[LLM] `') ||
      line.startsWith('[LLM] The') ||
      line.startsWith('[LLM] I ') ||
      line.startsWith('[LLM] Next') ||
      line.startsWith('[LLM] Task') ||
      line.startsWith('[LLM] Plan') ||
      line.startsWith('[LLM] To ');
}

String? _extractLastWorkflowSnapshot(String errorText) {
  if (errorText.isEmpty) {
    return null;
  }
  final taskPattern = RegExp(r'tasks=([^\n]+)');
  final match = taskPattern.firstMatch(errorText);
  if (match == null) {
    return null;
  }
  return match.group(1)?.trim();
}

List<String> _extractRecentLogTail(List<String> logs, {int limit = 12}) {
  final relevant = logs
      .where(
        (line) =>
            line.contains('[Workflow]') ||
            line.contains('[LLM]') ||
            line.contains('[ContentTool]') ||
            line.contains('[Tool]') ||
            line.contains('[ChatNotifier]'),
      )
      .toList(growable: false);
  if (relevant.length <= limit) {
    return relevant;
  }
  return relevant.sublist(relevant.length - limit);
}

String _trimLogLine(String line, {required int maxLength}) {
  final trimmed = line.substring(6).trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }
  return '${trimmed.substring(0, maxLength - 1)}…';
}
