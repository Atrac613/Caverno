// ChatNotifier decomposition collaborator: running-tool-tracker

/// Maintains the list of tools a turn has started and not yet finished.
///
/// The chat status row used to infer "running tools" from the message
/// content's trailing `</tool_use>` marker, which stays put until the next
/// request streams a token — so it kept claiming tools were running while the
/// model was already thinking again. The execution lifecycle is the ground
/// truth instead, and it carries the tool names the content marker never
/// exposed.
abstract final class RunningToolTracker {
  /// The list after applying [lifecycleState] for [toolName], or null when
  /// nothing changed and the caller should skip the state write.
  ///
  /// `started` is the only state that adds; every terminal state removes, so a
  /// skipped, failed, or aborted call cannot strand a name. `queued` is not a
  /// start — a queued call may never run.
  static List<String>? next(
    List<String> current, {
    required String toolName,
    required String lifecycleState,
  }) {
    if (lifecycleState == 'queued') return null;
    if (lifecycleState == 'started') {
      return <String>[...current, toolName];
    }
    final index = current.indexOf(toolName);
    if (index < 0) return null;
    return <String>[...current]..removeAt(index);
  }
}
