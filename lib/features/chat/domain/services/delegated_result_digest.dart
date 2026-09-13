import '../entities/subagent_task.dart';
import '../entities/worktree_agent_task.dart';

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
///
/// **Each id is labelled with the parameter that consumes it, after the first
/// version labelled them `child_id` / `workflow_task_id` and the parent passed
/// the *workflow* id to `get_subagent_result` — whose parameter is `task_id`, a
/// closer match to the wrong label than to `child_id`.** Naming the tool beside
/// each id is what stops a line that carries two ids from being a guess.
class DelegatedResultDigest {
  const DelegatedResultDigest();

  List<String> summaries({
    required List<SubagentTask> children,
    required Set<String> acceptedTaskIds,
    List<WorktreeAgentTask> worktreeChildren = const <WorktreeAgentTask>[],
  }) {
    return <String>[
      // Worktree children first: they are the evidenced kind, so when both ran
      // for one task the parent should reach for the one an acceptance can rest
      // on. Only those bound to a saved task appear -- the UI's and LL37's
      // branches are not the parent's to judge.
      for (final child in worktreeChildren)
        if (child.isTerminal &&
            child.workflowTaskId.trim().isNotEmpty &&
            !acceptedTaskIds.contains(child.workflowTaskId))
          [
            child.title.trim().isEmpty ? 'Delegated work' : child.title.trim(),
            '(worktree ${child.branchName})',
            '— get_subagent_result task_id: ${child.id}',
            '— accept_task workflow_task_id: ${child.workflowTaskId}',
            '— ${child.status.name}, verified: ${child.verifiedGreen}, '
                '${child.changedFiles.length} changed file(s)',
          ].join(' '),
      for (final child in children)
        if (child.isTerminal && !acceptedTaskIds.contains(child.workflowTaskId))
          [
            child.description.trim().isEmpty
                ? 'Delegated work'
                : child.description.trim(),
            '— get_subagent_result task_id: ${child.id}',
            if (child.workflowTaskId.trim().isNotEmpty)
              '— accept_task workflow_task_id: ${child.workflowTaskId}',
            '— ${child.status.name}',
          ].join(' '),
    ];
  }
}
