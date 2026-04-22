bool executionLogsContainWorkflowCompleted(List<String> logs) {
  const completionMarkers = <String>[
    'all planned tasks are complete',
    'all planned tasks have been completed',
    'all scheduled tasks are complete',
    'all scheduled tasks have been completed',
    'all saved tasks are complete',
    'すべての予定されていたタスクが完了しました',
  ];
  return logs.any((line) {
    final normalized = line.trim().toLowerCase();
    return completionMarkers.any(normalized.contains);
  }) ||
      _logsShowFinalTaskCompletion(logs);
}

bool _logsShowFinalTaskCompletion(List<String> logs) {
  var lastTaskCompletionIndex = -1;
  var lastNextTaskHandoffIndex = -1;

  for (var index = 0; index < logs.length; index++) {
    final normalized = logs[index].trim().toLowerCase();
    if (normalized.contains(
      'the previous saved task is complete. continue immediately with the next pending saved task',
    )) {
      lastNextTaskHandoffIndex = index;
    }
    if ((normalized.contains('the task "') &&
            normalized.contains('has been completed successfully')) ||
        (normalized.contains('the task "') &&
            normalized.contains('" is complete')) ||
        normalized.contains('the final saved task is complete') ||
        normalized.contains(
          'the saved task is complete and no pending saved tasks remain',
        )) {
      lastTaskCompletionIndex = index;
    }
  }

  if (lastTaskCompletionIndex < 0 ||
      lastTaskCompletionIndex <= lastNextTaskHandoffIndex) {
    return false;
  }

  return logs.skip(lastTaskCompletionIndex).any((line) {
    final normalized = line.trim().toLowerCase();
    return normalized.contains('[tool] resending tool results as user message') ||
        normalized.contains('[llm] ========== streamchatcompletion ==========');
  });
}
