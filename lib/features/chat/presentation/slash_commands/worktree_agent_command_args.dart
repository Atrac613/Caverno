final class WorktreeAgentCommandArgs {
  const WorktreeAgentCommandArgs({
    required this.prompt,
    this.verificationCommand = '',
    this.hasVerificationMarker = false,
    this.objectiveAcceptanceCriteria = const <String>[],
    this.hasAcceptanceMarker = false,
    this.runAfterQueue = false,
  });

  final String prompt;
  final String verificationCommand;
  final bool hasVerificationMarker;
  final List<String> objectiveAcceptanceCriteria;
  final bool hasAcceptanceMarker;
  final bool runAfterQueue;
}

WorktreeAgentCommandArgs parseWorktreeAgentCommandArgs(String args) {
  final trimmed = args.trim();
  final verifyMatch = RegExp(r'(^|\s)--verify(?:\s+|$)').firstMatch(trimmed);
  final verifyMarkerStart = verifyMatch == null
      ? trimmed.length
      : verifyMatch.start + (verifyMatch.group(1)?.length ?? 0);
  final beforeVerify = trimmed.substring(0, verifyMarkerStart).trim();
  final runMarker = RegExp(r'(^|\s)--run(?=\s|$)');
  final runAfterQueue = runMarker.hasMatch(beforeVerify);
  final cleanedBeforeVerify = beforeVerify.replaceFirst(runMarker, ' ').trim();
  final acceptMatch = RegExp(
    r'(^|\s)--accept(?:\s+|$)',
  ).firstMatch(cleanedBeforeVerify);
  final acceptMarkerStart = acceptMatch == null
      ? cleanedBeforeVerify.length
      : acceptMatch.start + (acceptMatch.group(1)?.length ?? 0);
  final prompt = cleanedBeforeVerify.substring(0, acceptMarkerStart).trim();
  final acceptanceCriterion = acceptMatch == null
      ? ''
      : cleanedBeforeVerify.substring(acceptMatch.end).trim();
  return WorktreeAgentCommandArgs(
    prompt: prompt,
    verificationCommand: verifyMatch == null
        ? ''
        : trimmed.substring(verifyMatch.end).trim(),
    hasVerificationMarker: verifyMatch != null,
    objectiveAcceptanceCriteria: acceptanceCriterion.isEmpty
        ? const <String>[]
        : <String>[acceptanceCriterion],
    hasAcceptanceMarker: acceptMatch != null,
    runAfterQueue: runAfterQueue,
  );
}

String worktreeAgentTaskTitle(String prompt) {
  final firstLine = prompt
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => 'Worktree agent');
  const maxTitleLength = 80;
  if (firstLine.length <= maxTitleLength) {
    return firstLine;
  }
  return '${firstLine.substring(0, maxTitleLength - 3).trimRight()}...';
}
