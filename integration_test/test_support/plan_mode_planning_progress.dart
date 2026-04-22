bool planningLogsContainWorkflowDraftReady(List<String> logs) {
  return logs.any(
    (line) =>
        line.contains('[Workflow] Workflow proposal ready') ||
        line.contains('[Workflow] Workflow proposal recovered on retry') ||
        line.contains('[Workflow] Using fallback proposal'),
  );
}

bool planningLogsContainTaskDraftReady(List<String> logs) {
  return logs.any(
    (line) =>
        line.contains('[Workflow] Task proposal ready') ||
        line.contains('[Workflow] Task proposal recovered on retry') ||
        line.contains(
          '[Workflow] Task proposal recovered from truncated reasoning fallback',
        ),
  );
}

bool isPlanningProposalReady({
  required bool hasWorkflowDraft,
  required bool hasTaskDraft,
  required bool hasPendingDecision,
  required String? workflowError,
  required String? taskError,
  required List<String> logs,
}) {
  if (hasPendingDecision || workflowError != null || taskError != null) {
    return false;
  }
  final resolvedWorkflowDraft =
      hasWorkflowDraft || planningLogsContainWorkflowDraftReady(logs);
  final resolvedTaskDraft =
      hasTaskDraft || planningLogsContainTaskDraftReady(logs);
  return resolvedWorkflowDraft && resolvedTaskDraft;
}

String resolvePlanningSubphase({
  required bool hasPendingDecision,
  required bool hasWorkflowDraft,
  required bool hasTaskDraft,
  required bool isGeneratingWorkflowProposal,
  required bool isGeneratingTaskProposal,
  required List<String> logs,
}) {
  if (hasPendingDecision) {
    return 'decision';
  }
  if (isPlanningProposalReady(
    hasWorkflowDraft: hasWorkflowDraft,
    hasTaskDraft: hasTaskDraft,
    hasPendingDecision: hasPendingDecision,
    workflowError: null,
    taskError: null,
    logs: logs,
  )) {
    return 'taskDraftReady';
  }
  if (hasTaskDraft) {
    return 'taskDraftReady';
  }
  if (hasWorkflowDraft) {
    return 'workflowDraftReady';
  }
  if (isGeneratingTaskProposal) {
    return 'taskProposal';
  }
  if (isGeneratingWorkflowProposal) {
    return 'workflowProposal';
  }
  return 'proposal';
}
