import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'goal_update_ack.dart';
import 'project_task_status_contract.dart';

/// The reconciled implementation or subtask verdict, independent of model prose.
final class ProjectTaskTerminalStatus {
  ProjectTaskTerminalStatus({
    required this.outcome,
    List<String> gaps = const [],
  }) : gapCodes = const [],
       gaps = List.unmodifiable(gaps),
       subtaskId = null,
       _subtaskAccepted = null;

  ProjectTaskTerminalStatus.subtask({
    required String? taskId,
    required bool accepted,
    List<String> gaps = const [],
    List<String> gapCodes = const [],
  }) : gapCodes = List.unmodifiable(gapCodes),
       outcome = null,
       subtaskId = taskId,
       _subtaskAccepted = accepted,
       gaps = List.unmodifiable(gaps);

  static const toolName = 'coding_task_status';
  static const subtaskDoneMarker = projectTaskSubtaskDoneMarker;
  final List<String> gapCodes;
  final GoalUpdateAckOutcome? outcome;
  final List<String> gaps;
  final String? subtaskId;
  final bool? _subtaskAccepted;
  bool get isSubtask => _subtaskAccepted != null;

  bool get completionAccepted =>
      _subtaskAccepted ?? outcome == GoalUpdateAckOutcome.completionRecorded;

  bool get requiresMemoryGuard => isSubtask || !completionAccepted;

  String get memorySummary => isSubtask && completionAccepted
      ? 'The current project subtask is complete; the overall task remains active.'
      : incompleteSummary;

  String get memoryNextStep => isSubtask && completionAccepted
      ? 'Continue with the remaining project subtasks.'
      : nextStep;

  String correctResponse(String content) {
    if (completionAccepted) return content;
    if (isSubtask ||
        outcome == GoalUpdateAckOutcome.completionRejected ||
        outcome == GoalUpdateAckOutcome.blockerLogged) {
      return incompleteResponse;
    }
    final report = content
        .split('\n')
        .where((line) => line.trim() != 'PROJECT_TASK_READY_FOR_REVIEW')
        .join('\n')
        .trim();
    return report.isEmpty
        ? incompleteResponse
        : '$incompleteResponse\n\n$report';
  }

  String get incompleteSummary => isSubtask
      ? 'The current project subtask remains incomplete; completion was not recorded.'
      : 'The project task remains incomplete; completion was not recorded.';

  String get nextStep => isSubtask
      ? 'Resolve the recorded subtask requirements before continuing.'
      : 'Resolve the recorded project task completion gaps.';

  String get incompleteResponse =>
      '$incompleteSummary\n\n'
      '${gaps.isEmpty ? nextStep : 'Remaining requirements:\n${gaps.map((gap) => '- $gap').join('\n')}'}';

  Map<String, dynamic> toJson() => {
    'result_origin': 'harness',
    'scope': isSubtask ? 'subtask' : 'implementation',
    'status': isSubtask
        ? (completionAccepted ? 'subtaskCompleted' : 'subtaskIncomplete')
        : outcome?.name ?? 'missing',
    'completionAccepted': completionAccepted,
    if (isSubtask) 'subtaskId': subtaskId,
    'gaps': gaps,
    if (gapCodes.isNotEmpty) 'gapCodes': gapCodes,
  };

  ToolResultInfo toToolResult(String id) => ToolResultInfo(
    id: id,
    name: toolName,
    arguments: const {},
    result: jsonEncode(toJson()),
  );

  static ProjectTaskTerminalStatus? fromToolResults(
    List<ToolResultInfo> results,
  ) {
    for (final result in results.reversed) {
      if (result.name != toolName) continue;
      try {
        final payload = jsonDecode(result.result);
        if (payload is! Map || payload['result_origin'] != 'harness') continue;
        final gaps = payload['gaps'] is List
            ? (payload['gaps'] as List).whereType<String>().toList()
            : const <String>[];
        if (payload['scope'] == 'subtask') {
          return ProjectTaskTerminalStatus.subtask(
            taskId: payload['subtaskId'] as String?,
            accepted:
                payload['status'] == 'subtaskCompleted' &&
                payload['completionAccepted'] == true &&
                gaps.isEmpty,
            gaps: gaps,
            gapCodes: payload['gapCodes'] is List
                ? (payload['gapCodes'] as List).whereType<String>().toList()
                : const [],
          );
        }
        GoalUpdateAckOutcome? outcome;
        for (final candidate in GoalUpdateAckOutcome.values) {
          if (candidate.name == payload['status']) outcome = candidate;
        }
        return ProjectTaskTerminalStatus(outcome: outcome, gaps: gaps);
      } on FormatException {
        // The terminal result is small and should survive prompt budgeting.
      }
    }
    return null;
  }
}
