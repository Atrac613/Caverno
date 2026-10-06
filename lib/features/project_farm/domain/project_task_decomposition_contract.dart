/// Splits a started roadmap task into ordered subtasks for the sidebar and
/// for one implementation turn each.
///
/// The subtasks are a progress outline, not a contract: they carry no
/// validation command, because a command the model wrote would then sit in
/// the thread's plan as if a person had approved it (farm invariant 2). Pure
/// Dart, like the other farm contracts.
library;

const int projectTaskMaxSubtasks = 6;

const Map<String, dynamic> projectTaskDecompositionSchema = {
  'type': 'object',
  'additionalProperties': false,
  'properties': {
    'subtasks': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          'title': {'type': 'string'},
          'target_files': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['title', 'target_files'],
      },
    },
  },
  'required': ['subtasks'],
};

String projectTaskDecompositionSystemPrompt(String languageCode) =>
    '''You split one software task into an ordered list of implementation subtasks.

Rules:
- Return 1 to $projectTaskMaxSubtasks subtasks. A small task is one subtask; do not pad.
- Each subtask is one concrete, verifiable step in the order it should be done, phrased as an imperative title of at most 12 words.
- Put verification inside the subtask it checks rather than as a separate final step.
- Do not include committing, pushing, code review, or updating the roadmap: the workflow does those itself.
- target_files lists repository-relative paths the subtask will likely touch, or is empty when unknown. Do not invent paths you cannot infer from the task.
- Write titles in the language whose code is "$languageCode".''';

/// One subtask as decoded from the model.
final class DecomposedSubtask {
  const DecomposedSubtask({required this.title, required this.targetFiles});

  final String title;
  final List<String> targetFiles;
}

/// The usable subtasks in [decoded], in order: blank titles are dropped and
/// the list is capped at [projectTaskMaxSubtasks]. Empty when the response
/// has no usable subtask.
List<DecomposedSubtask> parseProjectTaskDecomposition(
  Map<String, dynamic>? decoded,
) {
  final raw = decoded?['subtasks'];
  if (raw is! List) return const [];
  return [
    for (final entry in raw)
      if (entry is Map && entry['title'] is String)
        if ((entry['title'] as String).trim() case final title
            when title.isNotEmpty)
          DecomposedSubtask(
            title: title,
            targetFiles: [
              if (entry['target_files'] case final List files)
                for (final file in files)
                  if (file is String && file.trim().isNotEmpty) file.trim(),
            ],
          ),
  ].take(projectTaskMaxSubtasks).toList(growable: false);
}
