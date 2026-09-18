import '../entities/chat_turn_owner.dart';

// ChatNotifier decomposition collaborator: material-assumption-ask-memory

/// Remembers which material assumptions a turn has already put in front of the
/// user, so a dismissal outlives the tool-loop iteration it was made in.
///
/// [MaterialAssumptionConfirmationGate] asks about an item at most once per
/// gate, which was written as the property that keeps a declined assumption
/// from spinning a dialog. The gate's lifetime turned out to be shorter than
/// the promise: production builds one in `_executeToolLoopBatch`, which the
/// turn runs once per iteration, so a decline at iteration 1 was asked again at
/// iterations 2 and 3 with the identical modal. Measured 2026-09-18: three
/// iterations, three dialogs, one answer.
///
/// Keyed by [ChatTurnOwner] rather than by interaction generation alone,
/// because a second thread running its own batch must not be able to forget
/// what this turn already asked. Decline memory is per turn on purpose — a
/// revised assumption gets a new item id and is asked again, and going back to
/// a dismissal deliberately belongs to a persistent surface, not to an
/// interrupt that reopens itself.
final class MaterialAssumptionAskMemory {
  final Map<ChatTurnOwner, MaterialAssumptionAskScope> _scopesByOwner = {};

  /// The ask memory for [owner]'s turn, created on first use.
  MaterialAssumptionAskScope scopeFor(ChatTurnOwner owner) =>
      _scopesByOwner.putIfAbsent(owner, MaterialAssumptionAskScope.new);

  bool get isEmpty => _scopesByOwner.isEmpty;

  bool removeOwner(ChatTurnOwner owner) => _scopesByOwner.remove(owner) != null;

  void clearConversation(String conversationId) {
    _scopesByOwner.removeWhere(
      (owner, _) => owner.conversationId == conversationId,
    );
  }

  void clear() => _scopesByOwner.clear();
}

/// One turn's record of the assumptions it has already asked about.
final class MaterialAssumptionAskScope {
  final Set<String> _askedItemIds = <String>{};

  bool hasAsked(String itemId) => _askedItemIds.contains(itemId);

  void markAsked(String itemId) => _askedItemIds.add(itemId);
}
