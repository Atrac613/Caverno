/// Per-model authority policy for goal-completion claims.
enum GoalCompletionPolicy {
  /// A mechanically admissible `update_goal(completed: true)` closes the goal.
  tool,

  /// Accept the tool, but ask the user when the run reaches an unresolved
  /// budget or no-work boundary without an accepted completion claim.
  toolOrAsk,

  /// Never close from a model claim alone; ask the user to confirm completion.
  ask,
}

extension GoalCompletionPolicyBehavior on GoalCompletionPolicy {
  bool get acceptsToolCompletion => this != GoalCompletionPolicy.ask;

  bool get asksAtBoundary => this != GoalCompletionPolicy.tool;

  bool get allowsCompletionElicitation =>
      this == GoalCompletionPolicy.toolOrAsk;

  bool shouldAskImmediatelyAtBoundary({
    required bool budgetExhausted,
    required bool noRemainingWork,
  }) {
    return (budgetExhausted && asksAtBoundary) ||
        (noRemainingWork && this == GoalCompletionPolicy.ask);
  }
}
