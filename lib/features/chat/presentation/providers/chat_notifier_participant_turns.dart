// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierParticipantTurns on ChatNotifier {
  void requestParticipantTurnStop() {
    final runtime = state.participantTurnRuntime;
    if (runtime == null || runtime.paused) return;
    _participantTurnStopRequested = true;
    state = state.copyWith(
      participantTurnRuntime: runtime.copyWith(stopRequested: true),
    );
  }

  Future<void> continueParticipantTurns() async {
    if (state.isLoading) return;
    final cursor = _pausedParticipantTurnCursor;
    final config = _pausedParticipantTurnConfig;
    final targetConversationId = _pausedParticipantTurnConversationId;
    if (cursor == null || config == null || targetConversationId == null) {
      return;
    }

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation?.id != targetConversationId) {
      return;
    }

    final participants = _pausedParticipantTurnParticipants;
    if (participants.isEmpty) {
      _clearPausedParticipantTurn();
      state = state.copyWith(participantTurnRuntime: null);
      return;
    }

    _participantTurnStopRequested = false;
    final interactionGeneration = _beginInteractionGeneration();
    conversationId = targetConversationId;
    _llmSessionLogContextsByGeneration[interactionGeneration] =
        _buildLlmSessionLogContext(targetConversationId: targetConversationId);
    _registerActiveResponse(
      generation: interactionGeneration,
      targetConversationId: targetConversationId,
      messages: state.messages,
    );
    state = state.copyWith(
      isLoading: true,
      error: null,
      participantTurnRuntime: state.participantTurnRuntime?.copyWith(
        paused: false,
        stopRequested: false,
      ),
    );
    _onSendStarted();
    try {
      await _runParticipantTurnLoop(
        interactionGeneration: interactionGeneration,
        targetConversationId: targetConversationId,
        participants: participants,
        config: config,
        initialCursor: cursor,
      );
    } finally {
      _activeInteractionOrigin = ChatInteractionOrigin.local;
    }
  }

  Future<void> _sendWithParticipantTurns({
    required int interactionGeneration,
    required Conversation currentConversation,
    required ConversationsNotifier conversationsNotifier,
  }) async {
    _clearPausedParticipantTurn();
    _participantTurnStopRequested = false;
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
      state = state.copyWith(isLoading: false, participantTurnRuntime: null);
      _clearActiveResponseForGeneration(interactionGeneration);
      await _drainQueuedChatMessagesIfIdle();
      return;
    }

    await _runParticipantTurnLoop(
      interactionGeneration: interactionGeneration,
      targetConversationId: currentConversation.id,
      participants: participants,
      config: currentConversation.participantTurnConfig,
      initialCursor: const ParticipantTurnCursor(),
    );
  }

  Future<void> _runParticipantTurnLoop({
    required int interactionGeneration,
    required String targetConversationId,
    required List<ConversationParticipant> participants,
    required ParticipantTurnConfig config,
    required ParticipantTurnCursor initialCursor,
  }) async {
    const coordinator = ParticipantTurnCoordinator();
    var cursor = initialCursor;
    String completedContent = '';

    while (_isCurrentInteractionGeneration(interactionGeneration)) {
      final decision = coordinator.nextSpeaker(
        participants: participants,
        config: config,
        cursor: cursor,
      );
      if (!decision.hasParticipant) {
        await _completeParticipantTurns(
          generation: interactionGeneration,
          completedContent: completedContent,
        );
        return;
      }

      final participant = decision.participant!;
      final isFinalTurn = decision.completed;
      _setParticipantTurnRuntime(
        participant: participant,
        config: config,
        roundNumber: decision.roundNumber,
        paused: false,
      );
      completedContent = await _streamParticipantTurn(
        interactionGeneration: interactionGeneration,
        participant: participant,
        participants: participants,
        isFinalTurn: isFinalTurn,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;

      cursor = decision.cursor;
      if (_participantTurnStopRequested && !isFinalTurn) {
        await _pauseParticipantTurns(
          generation: interactionGeneration,
          targetConversationId: targetConversationId,
          participants: participants,
          config: config,
          cursor: cursor,
          completedContent: completedContent,
        );
        return;
      }

      if (isFinalTurn) {
        await _completeParticipantTurns(
          generation: interactionGeneration,
          completedContent: completedContent,
        );
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
        state = state.copyWith(participantTurnRuntime: null);
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

  Future<void> _pauseParticipantTurns({
    required int generation,
    required String targetConversationId,
    required List<ConversationParticipant> participants,
    required ParticipantTurnConfig config,
    required ParticipantTurnCursor cursor,
    required String completedContent,
  }) async {
    _pausedParticipantTurnCursor = cursor;
    _pausedParticipantTurnParticipants = List.unmodifiable(participants);
    _pausedParticipantTurnConfig = config;
    _pausedParticipantTurnConversationId = targetConversationId;
    _participantTurnStopRequested = false;
    final runtime = state.participantTurnRuntime;
    state = state.copyWith(
      isLoading: false,
      participantTurnRuntime: runtime?.copyWith(
        activeParticipantId: null,
        activeParticipantName: '',
        activeParticipantRoleLabel: '',
        activeParticipantColorValue: null,
        stopRequested: true,
        paused: true,
      ),
    );
    _clearActiveResponseForGeneration(generation);
    _contentToolContinuationCount = 0;
    _onResponseCompleted(completedContent);
    await _drainQueuedChatMessagesIfIdle();
  }

  Future<void> _completeParticipantTurns({
    required int generation,
    required String completedContent,
  }) async {
    _clearPausedParticipantTurn();
    _participantTurnStopRequested = false;
    state = state.copyWith(isLoading: false, participantTurnRuntime: null);
    _clearActiveResponseForGeneration(generation);
    _contentToolContinuationCount = 0;
    _onResponseCompleted(completedContent);
    await _drainQueuedChatMessagesIfIdle();
  }

  void _setParticipantTurnRuntime({
    required ConversationParticipant participant,
    required ParticipantTurnConfig config,
    required int roundNumber,
    required bool paused,
  }) {
    final multiRound = config.depth == ParticipantTurnDepth.multiRound;
    final maxRounds = multiRound
        ? (config.maxRounds < 1 ? 1 : config.maxRounds)
        : 1;
    state = state.copyWith(
      participantTurnRuntime: ParticipantTurnRuntime(
        activeParticipantId: participant.id,
        activeParticipantName: participant.effectiveDisplayName,
        activeParticipantRoleLabel: participant.effectiveRoleLabel,
        activeParticipantColorValue: participant.colorValue,
        currentRound: roundNumber,
        maxRounds: maxRounds,
        multiRound: multiRound,
        stopRequested: _participantTurnStopRequested,
        paused: paused,
      ),
    );
  }

  void _clearPausedParticipantTurn() {
    _pausedParticipantTurnCursor = null;
    _pausedParticipantTurnParticipants = const [];
    _pausedParticipantTurnConfig = null;
    _pausedParticipantTurnConversationId = null;
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
