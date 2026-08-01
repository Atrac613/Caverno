import 'dart:async';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/message.dart';

typedef ConversationMessagesWriter =
    Future<void> Function(String conversationId, List<Message> messages);
typedef CurrentConversationIdResolver = String? Function();

/// Prepares and serializes message persistence for completed chat turns.
///
/// Cancellation owns a separate admission tail so a runtime flush can observe
/// the save immediately, while all writes still share one conversation-order
/// queue.
final class TurnMessagePersistenceCoordinator {
  TurnMessagePersistenceCoordinator({
    required ConversationMessagesWriter writeConversationMessages,
    required CurrentConversationIdResolver currentConversationId,
    void Function(String message)? log,
  }) : _writeConversationMessages = writeConversationMessages,
       _currentConversationId = currentConversationId,
       _log = log ?? appLog;

  final ConversationMessagesWriter _writeConversationMessages;
  final CurrentConversationIdResolver _currentConversationId;
  final void Function(String message) _log;

  final Map<String, Future<void>> _conversationTails = {};
  Future<void> _cancelledTurnTail = Future<void>.value();

  TurnMessagePersistenceSnapshot prepareTurn(List<Message> messages) {
    final visibleMessages = List<Message>.unmodifiable(
      messages
          .where((message) => !message.isStreaming)
          .where(shouldKeepVisibleMessage),
    );
    String? targetAssistantMessageId;
    for (var index = visibleMessages.length - 1; index >= 0; index--) {
      if (visibleMessages[index].role == MessageRole.assistant) {
        targetAssistantMessageId = visibleMessages[index].id;
        break;
      }
    }
    final modelHistoryMessages = List<Message>.unmodifiable(
      visibleMessages
          .map(sanitizeMessageForModelHistory)
          .where(shouldKeepMessageForModelHistory),
    );
    return TurnMessagePersistenceSnapshot(
      visibleMessages: visibleMessages,
      modelHistoryMessages: modelHistoryMessages,
      targetAssistantMessageId: targetAssistantMessageId,
    );
  }

  Future<TurnMessagePersistenceSnapshot> persistTurn({
    required String? conversationId,
    required List<Message> messages,
  }) async {
    final snapshot = prepareTurn(messages);
    await persistMessages(conversationId, snapshot.visibleMessages);
    return snapshot;
  }

  Future<void> persistMessages(String? conversationId, List<Message> messages) {
    if (conversationId == null) return Future<void>.value();
    final messagesSnapshot = List<Message>.unmodifiable(messages);
    final previousWrite =
        _conversationTails[conversationId] ?? Future<void>.value();
    final write = previousWrite.then(
      (_) => _writeConversationMessages(conversationId, messagesSnapshot),
    );
    final safeWrite = write.catchError((Object error, StackTrace stackTrace) {
      _logPersistenceFailure('Conversation message', error, stackTrace);
    });
    _conversationTails[conversationId] = safeWrite;
    unawaited(
      safeWrite.whenComplete(() {
        if (identical(_conversationTails[conversationId], safeWrite)) {
          _conversationTails.remove(conversationId);
        }
      }),
    );
    return write;
  }

  Future<void> persistCurrentMessages(List<Message> messages) =>
      persistMessages(_currentConversationId(), messages);

  Future<void> enqueueCancelledTurn({
    required String conversationId,
    required List<Message> messages,
  }) {
    final messagesSnapshot = List<Message>.unmodifiable(messages);
    final save = _cancelledTurnTail.then<void>(
      (_) async => persistTurn(
        conversationId: conversationId,
        messages: messagesSnapshot,
      ),
    );
    _cancelledTurnTail = save.catchError((Object error, StackTrace stackTrace) {
      _logPersistenceFailure('Cancelled message', error, stackTrace);
    });
    return _cancelledTurnTail;
  }

  Future<void> flush() async {
    await _cancelledTurnTail;
    await Future.wait(_conversationTails.values.toList(growable: false));
  }

  Message sanitizeMessageForModelHistory(Message message) {
    if (message.role != MessageRole.assistant) return message;
    final strippedContent = ContentParser.stripModelHistoryArtifacts(
      message.content,
    );
    return strippedContent == message.content
        ? message
        : message.copyWith(content: strippedContent);
  }

  bool shouldKeepMessageForModelHistory(Message message) =>
      message.role != MessageRole.assistant ||
      message.content.trim().isNotEmpty;

  bool shouldKeepVisibleMessage(Message message) {
    if (message.role != MessageRole.assistant) return true;
    return message.content.trim().isNotEmpty;
  }

  void _logPersistenceFailure(
    String scope,
    Object error,
    StackTrace stackTrace,
  ) {
    _log(
      '[ChatNotifier] $scope persistence failed: '
      '${error.runtimeType}: $error',
    );
    _log('[ChatNotifier] stackTrace: $stackTrace');
  }
}

final class TurnMessagePersistenceSnapshot {
  const TurnMessagePersistenceSnapshot({
    required this.visibleMessages,
    required this.modelHistoryMessages,
    required this.targetAssistantMessageId,
  });

  final List<Message> visibleMessages;
  final List<Message> modelHistoryMessages;
  final String? targetAssistantMessageId;
}
