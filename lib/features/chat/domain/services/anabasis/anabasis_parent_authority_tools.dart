/// Names whose parent authority the generic capability classifier cannot infer.
abstract final class AnabasisParentAuthorityTools {
  /// The parent's route to effect on the workspace.
  static const delegation = <String>{'spawn_subagent'};

  /// Named exceptions whose authority the generic classifier cannot infer.
  static const all = <String>{
    ...delegation,
    'tool_search',
    'accept_task',
    'update_goal',
    'ask_user_question',
  };
}
