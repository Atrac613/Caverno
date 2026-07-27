// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierResponseFinalization on ChatNotifier {
  /// Persists a turn's messages to the thread they belong to. Both arguments
  /// default to the visible thread; a turn finalizing in the background must
  /// pass its own, or its work lands on whichever thread is on screen.
  Future<void> _saveMessages({
    bool updateSessionMemory = true,
    List<Message>? messages,
    String? conversationId,
  }) async {
    final messagesToSave = (messages ?? state.messages)
        .where((message) => !message.isStreaming)
        .where(_shouldKeepVisibleMessage)
        .toList();
    String? targetAssistantMessageId;
    for (var index = messagesToSave.length - 1; index >= 0; index--) {
      if (messagesToSave[index].role == MessageRole.assistant) {
        targetAssistantMessageId = messagesToSave[index].id;
        break;
      }
    }

    await _onMessagesChanged(messagesToSave, conversationId: conversationId);

    final currentConversationId = conversationId;
    if (!updateSessionMemory ||
        currentConversationId == null ||
        targetAssistantMessageId == null) {
      return;
    }
    final modelHistoryMessages = messagesToSave
        .map(_sanitizeMessageForModelHistory)
        .where(_shouldKeepMessageForModelHistory)
        .toList(growable: false);
    unawaited(
      _updateSessionMemory(
        currentConversationId,
        modelHistoryMessages,
        targetAssistantMessageId,
      ),
    );
  }

  Future<void> _finishDetachedActiveResponse(int generation) async {
    if (!_isCurrentInteractionGeneration(generation)) return;

    final targetConversationId = _activeResponseConversationIdForGeneration(
      generation,
    );
    final activeMessages = _activeResponseMessagesForGeneration(generation);
    if (targetConversationId == null ||
        activeMessages == null ||
        activeMessages.isEmpty) {
      _clearActiveResponseForGeneration(generation);
      _failRuntimeTurn(
        generation,
        code: 'detached_response_missing',
        message: 'The detached response could not be finalized.',
      );
      return;
    }

    final finalMessage = _resolveTurnFinalMessage(activeMessages.last);
    final shouldDropLastAssistant = finalMessage.dropLastAssistant;
    final updatedMessages = finalMessage.apply(
      activeMessages,
      metrics: _turnResponseMetrics(generation, finalMessage),
      truncated: _isCompletionTruncated(_latestFinishReason() ?? ''),
    );
    _pendingContentToolContinuationFallback = null;

    // A background turn ends here rather than in _finishStreaming, so without
    // this its exit reason never reached the session log and the triage
    // tooling saw only the turns that happened to finish on screen.
    await _logTurnExitReason(
      generation: generation,
      finalizedMessages: updatedMessages,
      shouldDropLastAssistant: shouldDropLastAssistant,
    );
    if (!_isCurrentInteractionGeneration(generation)) return;

    final messagesToSave = updatedMessages
        .where((message) => !message.isStreaming)
        .where(_shouldKeepVisibleMessage)
        .toList(growable: false);

    await _onConversationMessagesChanged(targetConversationId, messagesToSave);
    if (!_isCurrentInteractionGeneration(generation)) return;

    if (conversationId == targetConversationId) {
      state = state.copyWith(
        messages: updatedMessages,
        isLoading: false,
        pendingAskUserQuestion: null,
      );
    } else if (!state.busyConversationIds.contains(conversationId)) {
      // Nothing runs on the visible thread: stale isLoading strands its spinner.
      state = state.copyWith(isLoading: false);
    }

    String completedContent = '';
    if (!shouldDropLastAssistant && updatedMessages.isNotEmpty) {
      final finalizedLastMessage = updatedMessages.last;
      if (finalizedLastMessage.role == MessageRole.assistant) {
        completedContent = finalizedLastMessage.content;
      }
    }

    _clearActiveResponseForGeneration(generation);
    _contentToolContinuationCount = 0;
    _onResponseCompleted(completedContent);
    _completeRuntimeTurn(generation, content: completedContent);
  }
}
