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
  });
}
