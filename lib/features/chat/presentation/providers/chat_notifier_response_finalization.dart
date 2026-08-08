// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierResponseFinalization on ChatNotifier {
  void _failResponseMessagesMissing(int generation) => _failRuntimeTurn(
    generation,
    code: 'response_messages_missing',
    message: 'The response messages could not be finalized.',
  );

  int _updateTokenUsage(ChatTurnOwner owner) {
    final usage =
        _responseMetadata.metadataFor(owner)?.usage ?? TokenUsage.zero;
    if (usage.totalTokens <= 0) return 0;
    if (owner.conversationId == conversationId) {
      state = state.copyWith(
        promptTokens: usage.promptTokens,
        completionTokens: usage.completionTokens,
        totalTokens: usage.totalTokens,
      );
    }
    _runtimeEvents.emitRuntimeUsage(owner.interactionGeneration, usage);
    return usage.totalTokens;
  }

  MessageResponseMetrics? _turnResponseMetrics(
    ChatTurnOwner owner,
    TurnFinalMessage finalMessage,
  ) {
    if (finalMessage.dropLastAssistant) {
      _responseMetadata.discard(owner);
      return null;
    }
    return _responseMetadata.consume(owner);
  }

  Future<void> _writeConversationMessages(
    String conversationId,
    List<Message> messages,
  ) async {
    if (!ref.mounted) return;
    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateConversationMessages(conversationId, messages);
  }

  /// Persists a turn's messages to the thread they belong to. Both arguments
  /// default to the visible thread; a turn finalizing in the background must
  /// pass its own, or its work lands on whichever thread is on screen.
  Future<List<Message>> _saveMessages({
    bool updateSessionMemory = true,
    List<Message>? messages,
    required String conversationId,
    List<ToolResultInfo> memoryToolResults = const [],
  }) async {
    final persistence = await _messagePersistence.persistTurn(
      conversationId: conversationId,
      messages: messages ?? state.messages,
    );
    if (updateSessionMemory && persistence.targetAssistantMessageId != null) {
      unawaited(
        _updateSessionMemory(
          conversationId,
          persistence.modelHistoryMessages,
          persistence.targetAssistantMessageId!,
          memoryToolResults,
        ),
      );
    }
    return _conversationForId(conversationId)?.messages ??
        persistence.visibleMessages;
  }

  Future<void> _finishDetachedActiveResponse(int generation) async {
    if (!_isCurrentInteractionGeneration(generation)) return;
    final snapshot = _turnOwnerSnapshotForGeneration(generation);
    final owner = snapshot?.owner;
    if (owner == null) {
      return _handleTurnOwnerSnapshotUnavailable(generation);
    }

    final targetConversationId = _activeResponseConversationIdForGeneration(
      generation,
    );
    final activeMessages = _activeResponseMessagesForGeneration(generation);
    if (targetConversationId == null ||
        activeMessages == null ||
        activeMessages.isEmpty) {
      _failRuntimeTurn(
        generation,
        code: 'detached_response_missing',
        message: 'The detached response could not be finalized.',
      );
      return;
    }

    final finalMessage = _resolveTurnFinalMessage(activeMessages.last, owner);
    final shouldDropLastAssistant = finalMessage.dropLastAssistant;
    final goalTokenUsageDelta = _updateTokenUsage(owner);
    final finishReason = _responseMetadata.finishReasonFor(owner) ?? '';
    final updatedMessages = finalMessage.apply(
      activeMessages,
      metrics: _turnResponseMetrics(owner, finalMessage),
      truncated: ProposalParsingTextUtils.isCompletionTruncated(finishReason),
    );
    _contentToolTurns.setContinuationFallback(owner, null);
    if (await _finishEphemeralHiddenResponse(
      snapshot: snapshot!,
      updatedMessages: updatedMessages,
      shouldDropLastAssistant: shouldDropLastAssistant,
      turnThreadId: targetConversationId,
      finishReason: finishReason,
    )) {
      return;
    }
    _clearHiddenPromptMirrorForSnapshot(snapshot);

    // A background turn ends here rather than in _finishStreaming, so without
    // this its exit reason never reached the session log and the triage
    // tooling saw only the turns that happened to finish on screen.
    await _logTurnExitReason(
      owner: owner,
      finalizedMessages: updatedMessages,
      shouldDropLastAssistant: shouldDropLastAssistant,
      finishReason: finishReason,
    );
    if (!_activeResponseRegistry.containsOwner(owner)) return;
    final turnLogContext = _llmSessionLogContextForGeneration(generation);
    final explicitTerminalSuccessSummary =
        _explicitTerminalSuccessSummariesByGeneration.remove(generation);

    final messagesToSave = updatedMessages
        .where((message) => !message.isStreaming)
        .where(_messagePersistence.shouldKeepVisibleMessage)
        .toList(growable: false);

    await _messagePersistence.persistMessages(
      targetConversationId,
      messagesToSave,
    );
    if (!_activeResponseRegistry.containsOwner(owner)) return;

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
      final completionEvidence = await _finalizeGoalTurn(
        owner: owner,
        assistantResponse:
            explicitTerminalSuccessSummary?.trim().isNotEmpty == true
            ? explicitTerminalSuccessSummary!
            : finalizedLastMessage.content,
        tokenUsageDelta: goalTokenUsageDelta,
        context: turnLogContext,
      );
      if (completionEvidence == null) return;
      if (!_activeResponseRegistry.containsOwner(owner)) return;
    }

    _contentToolTurns.resetContinuationCount(owner);
    _onResponseCompleted(completedContent);
    _completeRuntimeTurn(generation, content: completedContent);
  }

  Future<bool> _finishEphemeralHiddenResponse({
    required TurnOwnerSnapshot snapshot,
    required List<Message> updatedMessages,
    required bool shouldDropLastAssistant,
    required String? turnThreadId,
    required String? finishReason,
  }) async {
    final hiddenPrompt = snapshot.hiddenPrompt;
    if (hiddenPrompt == null || snapshot.persistHiddenPromptAssistantResponse) {
      return false;
    }
    final owner = snapshot.owner;
    if (!shouldDropLastAssistant && updatedMessages.isNotEmpty) {
      _recordHiddenEvidence(owner, updatedMessages.last.content);
    }
    final cleanedMessages = shouldDropLastAssistant || updatedMessages.isEmpty
        ? updatedMessages
        : updatedMessages.sublist(0, updatedMessages.length - 1);
    _activeResponseRegistry.cacheMessagesForOwner(owner, cleanedMessages);
    _clearHiddenPromptMirrorForSnapshot(snapshot);

    await _logTurnExitReason(
      owner: owner,
      finalizedMessages: updatedMessages,
      shouldDropLastAssistant: shouldDropLastAssistant,
      finishReason: finishReason,
    );
    if (!_activeResponseRegistry.containsOwner(owner)) return true;
    if (conversationId == owner.conversationId) {
      state = state.copyWith(messages: cleanedMessages, isLoading: false);
    }

    _contentToolTurns.resetContinuationCount(owner);
    _onResponseCompleted('');
    _completeRuntimeTurn(owner.interactionGeneration, content: '');
    await _drainQueuedChatMessagesForThreadIfIdle(turnThreadId ?? '');
    return true;
  }

  void _clearHiddenPromptMirrorForSnapshot(TurnOwnerSnapshot snapshot) {
    if (_interactionGeneration != snapshot.owner.interactionGeneration ||
        _hiddenPrompt?.id != snapshot.hiddenPrompt?.id) {
      return;
    }
    _hiddenPrompt = null;
  }
}
