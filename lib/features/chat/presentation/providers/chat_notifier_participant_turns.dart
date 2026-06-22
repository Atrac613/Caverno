// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierParticipantTurns on ChatNotifier {
  Future<void> _sendWithParticipantTurns({
    required int interactionGeneration,
    required Conversation currentConversation,
    required ConversationsNotifier conversationsNotifier,
  }) async {
    const coordinator = ParticipantTurnCoordinator();
    var participants = coordinator.normalizeParticipants(
      participants: currentConversation.participants,
      primaryModel: _settings.effectiveModel,
    );
    if (!_sameParticipants(participants, currentConversation.participants)) {
      await conversationsNotifier.updateConversationParticipants(
        currentConversation.id,
        participants: participants,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
    }

    final enabledParticipants = coordinator.orderedEnabledParticipants(
      participants,
    );
    if (enabledParticipants.isEmpty) {
      state = state.copyWith(isLoading: false);
      _clearActiveResponseForGeneration(interactionGeneration);
      await _drainQueuedChatMessagesIfIdle();
      return;
    }

    var cursor = const ParticipantTurnCursor();
    String completedContent = '';

    while (_isCurrentInteractionGeneration(interactionGeneration)) {
      final decision = coordinator.nextSpeaker(
        participants: participants,
        config: currentConversation.participantTurnConfig,
        cursor: cursor,
      );
      if (!decision.hasParticipant) {
        state = state.copyWith(isLoading: false);
        _clearActiveResponseForGeneration(interactionGeneration);
        _onResponseCompleted(completedContent);
        await _drainQueuedChatMessagesIfIdle();
        return;
      }

      final participant = decision.participant!;
      final isFinalTurn = decision.completed;
      completedContent = await _streamParticipantTurn(
        interactionGeneration: interactionGeneration,
        participant: participant,
        participants: participants,
        isFinalTurn: isFinalTurn,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;

      cursor = decision.cursor;
      if (isFinalTurn) {
        _clearActiveResponseForGeneration(interactionGeneration);
        _contentToolContinuationCount = 0;
        _onResponseCompleted(completedContent);
        await _drainQueuedChatMessagesIfIdle();
        return;
      }
    }
  }

  Future<String> _streamParticipantTurn({
    required int interactionGeneration,
    required ConversationParticipant participant,
    required List<ConversationParticipant> participants,
    required bool isFinalTurn,
  }) async {
    final participantMessage = Message(
      id: _uuid.v4(),
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isStreaming: true,
      participantId: participant.id,
      participantDisplayName: participant.effectiveDisplayName,
      participantRoleLabel: participant.effectiveRoleLabel,
      participantColorValue: participant.colorValue,
    );
    _appendParticipantPlaceholder(
      generation: interactionGeneration,
      message: participantMessage,
    );
    _startResponseMetricsTimer(interactionGeneration);

    final model = participant.model.trim().isEmpty
        ? _settings.effectiveModel
        : participant.model.trim();
    final promptMessages = const ParticipantTurnCoordinator()
        .buildMessagesForParticipant(
          target: participant,
          participants: participants,
          transcript: _prepareMessagesForLLM(
            interactionGeneration: interactionGeneration,
          ),
        );

    try {
      await _runWithLlmSessionLogContextForGeneration(
        interactionGeneration,
        () => _runSecondaryCompletion<void>(
          endpointId: participant.endpointId,
          model: model,
          call: (dataSource, resolvedModel) async {
            final stream = dataSource.streamChatCompletion(
              messages: promptMessages,
              model: resolvedModel,
              temperature: _assistantRequestTemperature,
              maxTokens: _settings.maxTokens,
            );
            await for (final chunk in stream) {
              if (!_isCurrentInteractionGeneration(interactionGeneration)) {
                return;
              }
              _appendToLastMessageForGeneration(
                interactionGeneration,
                chunk,
                scanForTools: false,
              );
            }
          },
        ),
      );
    } catch (error, stackTrace) {
      appLog(
        '[ParticipantTurn] stream failed for ${participant.id}: ${error.runtimeType}: $error',
      );
      appLog('[ParticipantTurn] stackTrace: $stackTrace');
      if (_isCurrentInteractionGeneration(interactionGeneration)) {
        _handleError(error.toString());
      }
      return '';
    }

    if (!_isCurrentInteractionGeneration(interactionGeneration)) return '';
    return _finalizeParticipantTurnMessage(
      generation: interactionGeneration,
      isFinalTurn: isFinalTurn,
    );
  }

  void _appendParticipantPlaceholder({
    required int generation,
    required Message message,
  }) {
    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages =
          _activeResponseMessagesForGeneration(generation) ?? const <Message>[];
      _cacheActiveResponseMessagesForGeneration(generation, [
        ...activeMessages,
        message,
      ]);
      return;
    }

    if (!ref.mounted) return;
    state = state.copyWith(messages: [...state.messages, message]);
    _cacheActiveResponseMessagesForGeneration(generation, state.messages);
  }

  Future<String> _finalizeParticipantTurnMessage({
    required int generation,
    required bool isFinalTurn,
  }) async {
    if (!_isCurrentInteractionGeneration(generation)) return '';

    final isDetached = _isActiveResponseDetachedForGeneration(generation);
    final sourceMessages = isDetached
        ? _activeResponseMessagesForGeneration(generation)
        : state.messages;
    if (sourceMessages == null || sourceMessages.isEmpty) return '';

    final updatedMessages = [...sourceMessages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    final shouldDropLastAssistant =
        lastMessage.role == MessageRole.assistant &&
        !_assistantMessageHasVisibleContent(lastMessage.content);

    _updateTokenUsage();
    final responseMetrics = shouldDropLastAssistant
        ? null
        : _takeResponseMetricsForGeneration(generation);
    if (shouldDropLastAssistant) {
      _discardResponseMetricsForGeneration(generation);
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

    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
    if (isDetached) {
      final targetConversationId = _activeResponseConversationIdForGeneration(
        generation,
      );
      if (targetConversationId == null) return '';
      final messagesToSave = updatedMessages
          .where((message) => !message.isStreaming)
          .where(_shouldKeepVisibleMessage)
          .toList(growable: false);
      await _onConversationMessagesChanged(
        targetConversationId,
        messagesToSave,
      );
    } else {
      state = state.copyWith(
        messages: updatedMessages,
        isLoading: !isFinalTurn,
      );
      await _saveMessages();
    }

    if (shouldDropLastAssistant || updatedMessages.isEmpty) {
      return '';
    }
    final finalizedLastMessage = updatedMessages.last;
    if (!isDetached &&
        isFinalTurn &&
        _settings.autoReadEnabled &&
        _settings.ttsEnabled &&
        finalizedLastMessage.content.isNotEmpty) {
      _onAutoRead(finalizedLastMessage.content);
    }
    return finalizedLastMessage.content;
  }

  bool _sameParticipants(
    List<ConversationParticipant> a,
    List<ConversationParticipant> b,
  ) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
