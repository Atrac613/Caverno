bool planningLogsContainWorkflowDraftReady(List<String> logs) {
  return logs.any(
    (line) =>
        line.contains('[Workflow] Workflow proposal ready') ||
        line.contains('[Workflow] Workflow proposal recovered on retry') ||
        line.contains('[Workflow] Using fallback proposal'),
  );
}

bool planningLogsContainWorkflowDraftPersisted(List<String> logs) {
  return logs.any(
    (line) =>
        line.contains('[Workflow] Workflow plan artifact draft persisted'),
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

bool planningLogsContainTaskDraftPersisted(List<String> logs) {
  return logs.any(
    (line) => line.contains('[Workflow] Task plan artifact draft persisted'),
  );
}

bool planningLogsContainReadyDraftState(List<String> logs) {
  final workflowReady =
      planningLogsContainWorkflowDraftReady(logs) ||
      planningLogsContainWorkflowDraftPersisted(logs);
  final taskReady =
      planningLogsContainTaskDraftReady(logs) ||
      planningLogsContainTaskDraftPersisted(logs);
  return workflowReady && taskReady;
}

bool isPlanningProposalReady({
  required bool hasWorkflowDraft,
  required bool hasTaskDraft,
  required bool hasPendingDecision,
  required bool approvalUiVisible,
  required String? workflowError,
  required String? taskError,
  required List<String> logs,
}) {
  final workflowReadyFromLogs = planningLogsContainWorkflowDraftReady(logs);
  final workflowPersistedFromLogs = planningLogsContainWorkflowDraftPersisted(
    logs,
  );
  final taskReadyFromLogs = planningLogsContainTaskDraftReady(logs);
  final taskPersistedFromLogs = planningLogsContainTaskDraftPersisted(logs);
  if (planningLogsContainReadyDraftState(logs)) {
    return true;
  }
  final resolvedWorkflowDraft =
      hasWorkflowDraft || workflowReadyFromLogs || workflowPersistedFromLogs;
  final resolvedTaskDraft =
      hasTaskDraft || taskReadyFromLogs || taskPersistedFromLogs;
  if (resolvedWorkflowDraft && resolvedTaskDraft) {
    return !hasPendingDecision;
  }
  if (workflowError != null || taskError != null) {
    return false;
  }
  return false;
}

String resolvePlanningSubphase({
  required bool hasPendingDecision,
  required bool hasWorkflowDraft,
  required bool hasTaskDraft,
  required bool approvalUiVisible,
  required bool isGeneratingWorkflowProposal,
  required bool isGeneratingTaskProposal,
  required List<String> logs,
}) {
  if (hasPendingDecision) {
    return 'decision';
  }
  if (planningLogsContainReadyDraftState(logs)) {
    return 'taskDraftReady';
  }
  if (isPlanningProposalReady(
    hasWorkflowDraft: hasWorkflowDraft,
    hasTaskDraft: hasTaskDraft,
    hasPendingDecision: hasPendingDecision,
    approvalUiVisible: approvalUiVisible,
    workflowError: null,
    taskError: null,
    logs: logs,
  )) {
    return 'taskDraftReady';
  }
  if (approvalUiVisible &&
      (hasWorkflowDraft || planningLogsContainWorkflowDraftReady(logs))) {
    return 'workflowDraftReady';
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
