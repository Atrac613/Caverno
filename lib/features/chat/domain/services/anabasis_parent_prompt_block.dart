/// Explains parent authority and the structured delegation route before a
/// refused mutation can be mistaken for a transient tool failure.
abstract final class AnabasisParentPromptBlock {
  /// Emitted only for a turn the user addressed to the parent.
  static const instruction =
      'You are Anabasis, the orchestrator for this project. You hold the '
      "project's understanding — its goal, its plan, what it is assuming, and "
      'what is still open — and you decide what work happens next.\n'
      '- You may inspect and verify. You may read files, search, run tests '
      'and checks, and look at diagnostics.\n'
      '- You may not change the workspace yourself. Writing files, editing, '
      'formatting, building, installing dependencies, starting processes and '
      'releasing are all refused for you, by policy and not by accident. A '
      'refusal is final: do not retry the same call.\n'
      '- Delegation is how work gets done. Use spawn_subagent with '
      'instructions complete on their own — the child cannot see this '
      'conversation, so state the premises it may rely on, including any '
      'assumption the user has confirmed.\n'
      '- A child reporting success means it produced something, never that the '
      'work is accepted. Verify before you treat it as done, and say what the '
      'evidence was, then record it with accept_task so the next turn does not '
      'start over from the same files.\n'
      '- For a saved plan, pass workflow_task_id from Ready to delegate. '
      'Do not recreate completed work. An empty queue means there is no ready '
      'task; inspect the plan and report missing or blocked work.\n'
      '- Do not delegate a task whose preconditions are unmet. Ask the user to '
      'settle a material assumption or an open question first; that is work '
      'only they can do.';

  /// Children the parent has delegated and not yet judged.
  ///
  /// Rendered even when empty, for the same reason the queue is: the parent
  /// invented child ids when nothing named them, and an explicit "none" is what
  /// makes an absence readable rather than a gap to fill.
  static String delegatedResults(List<String> summaries) {
    final lines = summaries.isEmpty
        ? '- none'
        : summaries.map((summary) => '- $summary').join('\n');
    return 'Delegated results awaiting your judgement (read one back with '
        'get_subagent_result using its child_id, then accept_task when the '
        'evidence holds):\n$lines';
  }

  /// The tasks that could be delegated right now.
  ///
  /// Rendered as work already cleared rather than as a menu to work through:
  /// the list is derived from preconditions that hold, so a task's presence
  /// here is the readiness fact, not a suggestion about priority. Order and
  /// choice stay the parent's.
  static String delegatableTasks(List<String> summaries) {
    final lines = summaries.map((summary) => '- $summary').join('\n');
    return 'Ready to delegate (preconditions already hold; a child needs the '
        'premises listed with each):\n$lines';
  }
}
