/// What the Anabasis parent is told about its own boundary.
///
/// **A guard without this is a dead end.** `AnabasisParentAuthorityGuard`
/// refuses a mutation with a structured result, and a model that has not been
/// told it cannot edit will read that as a transient failure and try again —
/// the refusal loop ANA0's ordering constraint exists to prevent. The way out
/// has to be stated before the door is closed, so the block names delegation
/// as the route rather than only naming what is forbidden.
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
      'evidence was.\n'
      '- Do not delegate a task whose preconditions are unmet. Ask the user to '
      'settle a material assumption or an open question first; that is work '
      'only they can do.';

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
