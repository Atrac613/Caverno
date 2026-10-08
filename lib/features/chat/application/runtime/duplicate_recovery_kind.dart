/// The two bounded recoveries offered when a whole batch repeats earlier calls.
enum DuplicateRecoveryKind {
  inspection(
    label: 'Duplicate inspection',
    detectedLog: 'Duplicate read-only follow-up tool calls detected',
    messageIdPrefix: 'tool_recovery',
    logLabel: 'duplicate inspection recovery',
  ),
  followUp(
    label: 'Duplicate follow-up',
    detectedLog: 'Duplicate follow-up tool calls detected',
    messageIdPrefix: 'tool_followup_recovery',
    logLabel: 'duplicate follow-up recovery',
  );

  const DuplicateRecoveryKind({
    required this.label,
    required this.detectedLog,
    required this.messageIdPrefix,
    required this.logLabel,
  });

  final String label;
  final String detectedLog;
  final String messageIdPrefix;
  final String logLabel;
}
