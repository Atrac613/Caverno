import 'chat_state.dart';

/// Messages typed while some thread was busy, kept per thread.
///
/// Extracted from ChatNotifier, where the queue was one flat list that was
/// cleared on every thread switch: a message typed behind another thread's
/// running turn silently disappeared as soon as the user navigated away, and
/// a message that survived would have been sent to whichever thread happened
/// to be open when the queue drained.
class ThreadScopedMessageQueue {
  final List<QueuedChatMessage> _messages = <QueuedChatMessage>[];

  bool get isEmpty => _messages.isEmpty;

  int get length => _messages.length;

  void add(QueuedChatMessage message) => _messages.add(message);

  /// Removes [id] from any thread. Returns whether anything was removed.
  bool remove(String id) {
    final before = _messages.length;
    _messages.removeWhere((message) => message.id == id);
    return _messages.length != before;
  }

  /// The queue as [conversationId] sees it. Messages with no thread of their
  /// own belong to whoever is asking, which keeps pre-existing behaviour for
  /// conversations that have not been assigned an id yet.
  List<QueuedChatMessage> forThread(String? conversationId) {
    return List<QueuedChatMessage>.unmodifiable(
      _messages.where((message) => _belongsTo(message, conversationId)),
    );
  }

  int pendingFor(String? conversationId) {
    return _messages.where((m) => _belongsTo(m, conversationId)).length;
  }

  /// Removes and returns the next message [conversationId] should send, or
  /// null when that thread has nothing queued. Other threads' messages stay.
  QueuedChatMessage? takeNextForThread(String? conversationId) {
    for (var index = 0; index < _messages.length; index += 1) {
      if (_belongsTo(_messages[index], conversationId)) {
        return _messages.removeAt(index);
      }
    }
    return null;
  }

  void clear() => _messages.clear();

  bool _belongsTo(QueuedChatMessage message, String? conversationId) {
    final owner = message.conversationId;
    return owner == null || owner == conversationId;
  }
}
