import 'dart:async';

import '../../domain/entities/chat_turn_owner.dart';
import 'chat_state.dart';

/// Messages typed while some thread was busy, kept per thread.
///
/// Each entry retains its original thread and terminal owner receipt.
class ThreadScopedMessageQueue {
  final List<QueuedChatMessage> _messages = <QueuedChatMessage>[];
  final Set<String> _drainingOwners = <String>{};
  final Map<String, Completer<ChatTurnOwner?>> _turnOwnerReceipts =
      <String, Completer<ChatTurnOwner?>>{};

  bool get isEmpty => _messages.isEmpty;
  int get length => _messages.length;

  Future<ChatTurnOwner?> add(QueuedChatMessage message) {
    _messages.add(message);
    return _turnOwnerReceiptFor(message.id);
  }

  void completeTurnOwner(QueuedChatMessage message, ChatTurnOwner? owner) {
    final receipt = _turnOwnerReceipts.remove(message.id);
    if (receipt != null && !receipt.isCompleted) receipt.complete(owner);
  }

  bool canStart(
    QueuedChatMessage message,
    String? visibleOwner,
    bool fromQueue,
  ) {
    final owner = message.conversationId;
    return owner?.trim().isEmpty != true &&
        (!fromQueue || owner != null) &&
        (owner == null || owner == visibleOwner);
  }

  String? ownerFor(
    QueuedChatMessage message,
    String? visibleOwner,
    String? currentOwner,
  ) {
    final owner = message.conversationId ?? currentOwner;
    if (owner == null ||
        owner.trim().isEmpty ||
        (visibleOwner != null && visibleOwner != owner) ||
        currentOwner != owner) {
      return null;
    }
    return owner;
  }

  bool beginDrain(String owner) => _drainingOwners.add(owner);
  void endDrain(String owner) => _drainingOwners.remove(owner);
  bool shouldEnqueue(String? owner) =>
      owner != null &&
      (pendingFor(owner) > 0 || _drainingOwners.contains(owner));
  bool contains(QueuedChatMessage message) => _messages.contains(message);

  Future<ChatTurnOwner?> restoreFirstForThread(
    QueuedChatMessage message,
    String conversationId,
  ) {
    _messages.insert(
      0,
      message.conversationId == conversationId
          ? message
          : QueuedChatMessage(
              id: message.id,
              content: message.content,
              imageBase64: message.imageBase64,
              imageMimeType: message.imageMimeType,
              originalImagePath: message.originalImagePath,
              originalImageMimeType: message.originalImageMimeType,
              languageCode: message.languageCode,
              isVoiceMode: message.isVoiceMode,
              bypassPlanMode: message.bypassPlanMode,
              origin: message.origin,
              conversationId: conversationId,
            ),
    );
    return _turnOwnerReceiptFor(message.id);
  }

  /// Removes [id] from any thread. Returns whether anything was removed.
  bool remove(String id) {
    final before = _messages.length;
    _messages.removeWhere((message) => message.id == id);
    final removed = _messages.length != before;
    if (removed) {
      final receipt = _turnOwnerReceipts.remove(id);
      if (receipt != null && !receipt.isCompleted) receipt.complete(null);
    }
    return removed;
  }

  /// The queue as [conversationId] sees it, including a null-owned draft only
  /// while no conversation has been assigned.
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

  void clear() {
    _messages.clear();
    for (final receipt in _turnOwnerReceipts.values) {
      if (!receipt.isCompleted) receipt.complete(null);
    }
    _turnOwnerReceipts.clear();
  }

  bool _belongsTo(QueuedChatMessage message, String? conversationId) {
    return message.conversationId == conversationId;
  }

  Future<ChatTurnOwner?> _turnOwnerReceiptFor(String messageId) {
    return _turnOwnerReceipts
        .putIfAbsent(messageId, Completer<ChatTurnOwner?>.new)
        .future;
  }
}
