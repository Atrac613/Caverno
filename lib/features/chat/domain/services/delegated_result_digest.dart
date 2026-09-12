import '../entities/subagent_task.dart';

/// What the parent has delegated and not yet judged, named so it can be read
/// back.
///
/// **Measured need.** A child's `task_id` is returned by `spawn_subagent` and
/// then lives nowhere the parent can see again: tool results do not persist into
/// the next turn's history, and no prompt block named them. Asked in a later
/// turn to judge the child's result, the parent invented plausible ids
/// (`task-1789222975930-1`), got nothing back, and re-delegated the task it had
/// already delegated — the exact "start over from the same files" ANA3 exists to
/// stop.
///
/// An already-accepted task is dropped: the parent has judged it, and listing it
/// again invites a second acceptance of the same work.
class DelegatedResultDigest {
  const DelegatedResultDigest();

  List<String> summaries({
    required List<SubagentTask> children,
    required Set<String> acceptedTaskIds,
  }) {
    return <String>[
      for (final child in children)
        if (child.isTerminal && !acceptedTaskIds.contains(child.workflowTaskId))
          [
            child.description.trim().isEmpty
                ? 'Delegated work'
                : child.description.trim(),
            '[child_id: ${child.id}]',
            if (child.workflowTaskId.trim().isNotEmpty)
              '[workflow_task_id: ${child.workflowTaskId}]',
            '— ${child.status.name}',
          ].join(' '),
    ];
  }
}
