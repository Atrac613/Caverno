// ChatNotifier decomposition collaborator: loaded-skill-memory

/// Remembers which skills a thread has loaded, so the one it is working from
/// can be repeated into the turns that follow.
///
/// A `load_skill` result lives for exactly the turn that produced it:
/// `StickyToolResultPolicy` and `RecentReadResultCarry` both resolve over the
/// current turn's executed results, and across a turn boundary that list starts
/// empty. Session fd153d88 is the cost — the skill was loaded in turn 2 and the
/// write it governed happened in turn 4, against a convention the skill states
/// and the model could no longer see.
///
/// Keyed by conversation rather than by turn, because the span that matters is
/// the task: the load and the work it governs are deliberately in different
/// turns, which is the whole problem.
///
/// In memory on purpose. The failure is inside one task, and a record that
/// survives a restart would mean persisting it on the conversation entity —
/// codegen and a migration for a case nobody has observed. If a skill-governed
/// task does turn out to span a restart it is visible from the outside: the
/// index shows the skill's name with no carry.
final class LoadedSkillMemory {
  final Map<String, List<String>> _refsByConversation = {};

  /// Records that [skillRef] — an id, or a name when that is all the call
  /// carried — was loaded in [conversationId]. The most recent wins, so
  /// reloading a skill moves it to the front rather than duplicating it.
  void record({required String conversationId, required String skillRef}) {
    final ref = skillRef.trim();
    if (conversationId.isEmpty || ref.isEmpty) return;
    final refs = _refsByConversation.putIfAbsent(
      conversationId,
      () => <String>[],
    )..remove(ref);
    refs.add(ref);
  }

  /// The skill to carry in full: the one most recently loaded.
  String? carriedRefFor(String conversationId) {
    final refs = _refsByConversation[conversationId];
    return (refs == null || refs.isEmpty) ? null : refs.last;
  }

  /// Every skill loaded in this thread, including the carried one.
  Set<String> loadedRefsFor(String conversationId) =>
      _refsByConversation[conversationId]?.toSet() ?? const <String>{};

  void forget(String conversationId) =>
      _refsByConversation.remove(conversationId);
}
