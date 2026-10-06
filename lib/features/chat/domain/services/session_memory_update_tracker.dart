/// Prevents delayed extraction from replacing a newer turn's memory.
final class SessionMemoryUpdateTracker {
  final _pending = <String, Object>{};

  Object begin(String conversationId) {
    final token = Object();
    _pending[conversationId] = token;
    return token;
  }

  bool isCurrent(String conversationId, Object token) =>
      identical(_pending[conversationId], token);

  void finish(String conversationId, Object token) {
    if (isCurrent(conversationId, token)) _pending.remove(conversationId);
  }
}
