import '../entities/conversation_goal.dart';
import '../entities/conversation_workflow.dart';

class ConversationGoalProgressInferenceResult {
  const ConversationGoalProgressInferenceResult({
    this.status,
    this.completionSummary,
  });

  final ConversationGoalStatus? status;
  final String? completionSummary;

  bool get hasStructuredCompletion =>
      status == ConversationGoalStatus.completed;
}

/// Derives aggregate goal completion only from persisted workflow task state.
///
/// Model prose used to provide a second completion and blocker signal. LL35's
/// grounded comparison found no lexical-only completion rescue across three
/// models and two coding surfaces, while accepted `update_goal` calls were
/// missed lexically in every model/surface cell. Goal lifecycle authority now
/// stays with saved tasks, the explicit goal-update tool, and exact
/// harness-owned completion contracts.
abstract final class ConversationGoalProgressInference {
  static ConversationGoalProgressInferenceResult infer({
    required String assistantResponse,
    required Iterable<ConversationWorkflowTask> tasks,
  }) {
    final taskList = tasks.toList(growable: false);
    if (taskList.isEmpty ||
        taskList.any(
          (task) => task.status != ConversationWorkflowTaskStatus.completed,
        )) {
      return const ConversationGoalProgressInferenceResult();
    }

    final summary = _extractSummary(assistantResponse.trim());
    return ConversationGoalProgressInferenceResult(
      status: ConversationGoalStatus.completed,
      completionSummary: summary.isEmpty
          ? 'All saved workflow tasks are complete.'
          : summary,
    );
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
}
