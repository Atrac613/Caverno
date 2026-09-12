/// Tool names that are the Anabasis parent's own authority rather than a change
/// to the workspace.
///
/// Extracted from `AnabasisParentAuthorityGuard` when the list stopped being
/// one name: the guard is at its size ceiling, and this is policy the guard
/// reads rather than logic it performs.
///
/// **Measured, not reasoned.** A live run had the parent's `accept_task`
/// refused by the guard in 0 ms -- before the acceptance handler's own five
/// grounds could be reached -- and a probe of the rest found `update_goal` and
/// `ask_user_question` refused the same way. All three classify as `unknown`,
/// which the guard refuses by design, and all three are things the parent's own
/// prompt tells it to do: record the acceptance with `accept_task`, own the goal
/// state, and ask the user to settle what only they can settle.
///
/// The refusal's advice is what made it unrecoverable. "Delegate this to a child
/// with spawn_subagent" cannot work for any of them: `accept_task` refuses a
/// non-parent as `acceptance_not_parent`, so between the two guards the tool had
/// no caller left at all, and a child cannot ask the user on the parent's
/// behalf either.
///
/// `create_routine` is deliberately absent. It schedules real runs, nothing in
/// the parent's instructions asks for it, and the keep-it-closed default the
/// guard documents is the right answer for a tool with no such claim.
abstract final class AnabasisParentAuthorityTools {
  /// The parent's route to effect on the workspace.
  static const delegation = <String>{'spawn_subagent'};

  /// Everything the parent may run that is not inspection or verification.
  static const all = <String>{
    ...delegation,
    'accept_task',
    'update_goal',
    'ask_user_question',
  };
}
