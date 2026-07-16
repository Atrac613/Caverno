// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierResponseFinalization on ChatNotifier {
  /// Persists the current conversation messages.
  Future<void> _saveMessages({bool updateSessionMemory = true}) async {
    final messagesToSave = state.messages
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

    await _onMessagesChanged(messagesToSave);

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

    final updatedMessages = [...activeMessages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    final fallbackContent = _pendingContentToolContinuationFallback?.trim();
    final shouldUseContentToolContinuationFallback =
        lastMessage.role == MessageRole.assistant &&
        !_assistantMessageHasVisibleContent(lastMessage.content) &&
        fallbackContent != null &&
        fallbackContent.isNotEmpty;
    final shouldDropLastAssistant =
        lastMessage.role == MessageRole.assistant &&
        !_assistantMessageHasVisibleContent(lastMessage.content) &&
        !shouldUseContentToolContinuationFallback;
    final responseMetrics = shouldDropLastAssistant
        ? null
        : _takeResponseMetricsForGeneration(generation);
    if (shouldDropLastAssistant) {
      _discardResponseMetricsForGeneration(generation);
    }

    if (shouldUseContentToolContinuationFallback) {
      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: fallbackContent,
        isStreaming: false,
        responseMetrics: responseMetrics,
      );
    } else if (shouldDropLastAssistant) {
      updatedMessages.removeAt(lastIndex);
    } else {
      final finalizedContent =
          _isCompletionTruncated(_latestFinishReason() ?? '')
          ? TruncationNotice.withMaxTokenNotice(lastMessage.content)
          : lastMessage.content;
      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: finalizedContent,
        isStreaming: false,
        responseMetrics: responseMetrics,
      );
    }
    _pendingContentToolContinuationFallback = null;

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
