import '../../chat/domain/entities/conversation_workflow.dart';
import '../../chat/domain/entities/model_usage_role.dart';
import '../domain/project_task_decomposition_contract.dart';
import '../domain/roadmap_next_task_contract.dart';
import '../domain/roadmap_next_task_extractor.dart';

/// Splits a started roadmap task into the subtasks its thread executes one
/// turn at a time.
///
/// Returns an empty list when the model gives nothing usable or the request
/// fails; the workflow then runs the task as a single step, so a failed
/// decomposition costs the outline, never the task.
final class ProjectTaskDecomposer {
  const ProjectTaskDecomposer({required RoadmapCompletionPort complete})
    : _complete = complete;

  final RoadmapCompletionPort _complete;

  Future<List<ConversationWorkflowTask>> decompose(
    String objective, {
    required String languageCode,
  }) async {
    try {
      final completion = await ModelUsageRole.planning.runWith(
        () => _complete(
          system: projectTaskDecompositionSystemPrompt(languageCode),
          user: 'Task:\n\n$objective',
          schemaName: 'caverno_project_task_decomposition',
          schema: projectTaskDecompositionSchema,
          maxTokens: 1200,
        ),
      );
      final subtasks = parseProjectTaskDecomposition(
        decodeJsonObject(completion.content),
      );
      return [
        for (final (index, subtask) in subtasks.indexed)
          ConversationWorkflowTask(
            id: 'project-subtask-${index + 1}',
            title: subtask.title,
            targetFiles: subtask.targetFiles,
          ),
      ];
    } on Object {
      return const [];
    }
  }
}
