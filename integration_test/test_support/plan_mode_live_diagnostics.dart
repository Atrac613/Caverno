enum PlanModeFailureClass {
  passed,
  planningTimeout,
  executionTimeout,
  executionHang,
  blockedExecution,
  executionDrift,
  overallTimeout,
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
    required this.budgetPhase,
    required this.activeTaskTitle,
    required this.toolResultCount,
    required this.fileWriteCount,
    required this.phaseTimings,
    required this.budgets,
    required this.recentLogTail,
  });

  final PlanModeFailureClass failureClass;
  final String? lastToolName;
  final String? lastToolFailure;
  final String? lastAssistantSummary;
  final String? lastWorkflowSnapshot;
  final int? stallDurationMs;
  final String? budgetPhase;
  final String? activeTaskTitle;
  final int? toolResultCount;
  final int? fileWriteCount;
  final Map<String, String?> phaseTimings;
  final Map<String, int?> budgets;
  final List<String> recentLogTail;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'failureClass': failureClass.name,
      'lastToolName': lastToolName,
      'lastToolFailure': lastToolFailure,
      'lastAssistantSummary': lastAssistantSummary,
      'lastWorkflowSnapshot': lastWorkflowSnapshot,
      'stallDurationMs': stallDurationMs,
      'budgetPhase': budgetPhase,
      'activeTaskTitle': activeTaskTitle,
      'toolResultCount': toolResultCount,
      'fileWriteCount': fileWriteCount,
      'phaseTimings': phaseTimings,
      'budgets': budgets,
      'recentLogTail': recentLogTail,
    };
  }
}

PlanModeFailureDiagnostics buildPlanModeFailureDiagnostics({
  required List<String> logs,
  String? errorText,
  String? lastWorkflowSnapshot,
  int? stallDurationMs,
  String? budgetPhase,
  String? activeTaskTitle,
  int? toolResultCount,
  int? fileWriteCount,
  Map<String, String?> phaseTimings = const <String, String?>{},
  Map<String, int?> budgets = const <String, int?>{},
}) {
  final normalizedError = (errorText ?? '').trim();
  final failureClass = _classifyFailure(logs: logs, errorText: normalizedError);
  return PlanModeFailureDiagnostics(
    failureClass: failureClass,
    lastToolName: _extractLastToolName(logs),
    lastToolFailure: _extractLastToolFailure(logs),
    lastAssistantSummary: _extractLastAssistantSummary(logs),
    lastWorkflowSnapshot:
        lastWorkflowSnapshot ?? _extractLastWorkflowSnapshot(normalizedError),
    stallDurationMs: stallDurationMs,
    budgetPhase: budgetPhase ?? _defaultBudgetPhaseForFailure(failureClass),
    activeTaskTitle:
        activeTaskTitle ?? _extractActiveTaskTitle(normalizedError),
    toolResultCount:
        toolResultCount ??
        _extractNamedIntField(normalizedError, 'toolresults'),
    fileWriteCount:
        fileWriteCount ?? _extractNamedIntField(normalizedError, 'filewrites'),
    phaseTimings: Map<String, String?>.unmodifiable(
      Map<String, String?>.from(phaseTimings),
    ),
    budgets: Map<String, int?>.unmodifiable(Map<String, int?>.from(budgets)),
    recentLogTail: _extractRecentLogTail(logs),
  );
}

String? _defaultBudgetPhaseForFailure(PlanModeFailureClass failureClass) {
  switch (failureClass) {
    case PlanModeFailureClass.planningTimeout:
      return 'planning';
    case PlanModeFailureClass.executionTimeout:
    case PlanModeFailureClass.executionHang:
    case PlanModeFailureClass.blockedExecution:
    case PlanModeFailureClass.executionDrift:
    case PlanModeFailureClass.executionStall:
      return 'execution';
    case PlanModeFailureClass.overallTimeout:
      return 'overall';
    case PlanModeFailureClass.passed:
    case PlanModeFailureClass.streamDisconnect:
    case PlanModeFailureClass.unknownTool:
    case PlanModeFailureClass.workflowBlocked:
    case PlanModeFailureClass.workflowProposalParse:
    case PlanModeFailureClass.planningLoop:
    case PlanModeFailureClass.warningFailure:
    case PlanModeFailureClass.toolExecutionFailure:
    case PlanModeFailureClass.unclassified:
      return null;
  }
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

  if (normalizedError.contains('planning phase timed out')) {
    return PlanModeFailureClass.planningTimeout;
  }
  if (normalizedError.contains('execution phase timed out')) {
    final workflowSnapshot = _extractLastWorkflowSnapshot(errorText) ?? '';
    final isLoading = _extractNamedBoolField(errorText, 'isLoading');
    final fileWrites = _extractNamedIntField(errorText, 'fileWrites') ?? 0;
    final toolResults = _extractNamedIntField(errorText, 'toolResults') ?? 0;
    if (workflowSnapshot.contains(':blocked')) {
      return PlanModeFailureClass.blockedExecution;
    }
    if (isLoading == true) {
      return PlanModeFailureClass.executionHang;
    }
    if (_looksLikeExecutionDrift(
      errorText,
      logs,
      fileWrites: fileWrites,
      toolResults: toolResults,
    )) {
      return PlanModeFailureClass.executionDrift;
    }
    return PlanModeFailureClass.executionTimeout;
  }
  if (normalizedError.contains('overall live run timed out')) {
    return PlanModeFailureClass.overallTimeout;
  }
  if (normalizedError.contains('workflow execution stalled')) {
    return PlanModeFailureClass.executionStall;
  }
  if (normalizedError.contains('workflow execution remained blocked')) {
    return PlanModeFailureClass.workflowBlocked;
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
  if (logsContain('run timed out after')) {
    return PlanModeFailureClass.overallTimeout;
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

String? _extractActiveTaskTitle(String errorText) {
  if (errorText.isEmpty) {
    return null;
  }
  final match = RegExp(r'activeTask=([^,\n]+)').firstMatch(errorText);
  return match?.group(1)?.trim();
}

int? _extractNamedIntField(String errorText, String fieldName) {
  if (errorText.isEmpty) {
    return null;
  }
  final pattern = RegExp('$fieldName=(\\d+)', caseSensitive: false);
  final match = pattern.firstMatch(errorText);
  return int.tryParse(match?.group(1) ?? '');
}

bool? _extractNamedBoolField(String errorText, String fieldName) {
  if (errorText.isEmpty) {
    return null;
  }
  final pattern = RegExp('$fieldName=(true|false)', caseSensitive: false);
  final match = pattern.firstMatch(errorText);
  if (match == null) {
    return null;
  }
  return match.group(1)?.toLowerCase() == 'true';
}

bool _looksLikeExecutionDrift(
  String errorText,
  List<String> logs, {
  required int fileWrites,
  required int toolResults,
}) {
  final normalizedError = errorText.toLowerCase();
  const driftFragments = <String>[
    'readme.py',
    'subsequent tasks should involve',
    'argparse, click, or typer',
    'host input: cli arguments',
    'saved task drift',
    'task drift',
  ];
  if (driftFragments.any(normalizedError.contains)) {
    return true;
  }

  final normalizedLogs = logs.map((line) => line.toLowerCase()).toList();
  if (normalizedLogs.any(
    (line) =>
        driftFragments.any(line.contains) ||
        line.contains('[workflow] task proposal quality gate requested retry'),
  )) {
    return true;
  }

  return fileWrites > 0 && toolResults <= 1;
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
