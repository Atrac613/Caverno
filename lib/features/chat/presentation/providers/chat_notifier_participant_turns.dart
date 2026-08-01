// Same-library extension; see chat_notifier_git_handlers.dart for lint context.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

typedef _ParticipantTurn = ({int generation, String ownerId});
typedef _ParticipantTurnCompletion = ({String content, String? handoffId});

extension ChatNotifierParticipantTurns on ChatNotifier {
  void requestParticipantTurnStop() {
    final ownerConversationId = conversationId;
    final runtime = state.participantTurnRuntime;
    if (ownerConversationId == null || runtime == null || runtime.paused) {
      return;
    }
    final generation = _activeResponseGenerationForConversation(
      ownerConversationId,
    );
    if (generation == null) return;
    final owner = ChatTurnOwner(
      conversationId: ownerConversationId,
      interactionGeneration: generation,
    );
    if (!_participantTurnControls.requestStop(owner)) return;
    _routeThreadState(
      ownerConversationId,
      (s) => s.copyWith(
        participantTurnRuntime: runtime.copyWith(stopRequested: true),
      ),
    );
  }

  Future<void> continueParticipantTurns() async {
    if (state.isLoading) return;
    final targetConversationId = conversationId;
    if (targetConversationId == null) return;
    final pausedOwner = _participantTurnControls.pausedOwnerForConversation(
      targetConversationId,
    );
    if (pausedOwner == null) return;
    final paused = _participantTurnControls.resume(pausedOwner);
    if (paused == null) return;
    final participants = paused.participants;
    if (participants.isEmpty) {
      _participantTurnControls.consumeCursor(pausedOwner);
      _participantTurnControls.dispose(pausedOwner);
      _routeThreadState(
        targetConversationId,
        (s) => s.copyWith(participantTurnRuntime: null),
      );
      return;
    }
    final generation = _beginInteractionGeneration();
    final turn = (generation: generation, ownerId: targetConversationId);
    final owner = _participantTurnOwner(turn);
    conversationId = targetConversationId;
    _trackActiveResponse(turn.generation, turn.ownerId);
    if (await _startRuntimeTurn(
          generation: turn.generation,
          ownerConversationId: turn.ownerId,
          hidden: false,
        ) ==
        null) {
      _participantTurnControls.clear(pausedOwner);
      _clearActiveResponseForGeneration(turn.generation);
      return;
    }
    if (!_participantTurnControls.begin(owner)) {
      _participantTurnControls.clear(pausedOwner);
      _failRuntimeTurn(
        turn.generation,
        code: 'participant_control_state_unavailable',
        message: 'Participant turn control state could not be initialized.',
      );
      return;
    }
    final cursor = _participantTurnControls.consumeCursor(pausedOwner);
    if (cursor == null) {
      _participantTurnControls.dispose(owner);
      _participantTurnControls.clear(pausedOwner);
      _failRuntimeTurn(
        turn.generation,
        code: 'participant_resume_cursor_unavailable',
        message: 'The paused participant turn cursor is unavailable.',
      );
      return;
    }
    _participantTurnControls.dispose(pausedOwner);
    _routeThreadState(
      turn.ownerId,
      (s) => s.copyWith(
        isLoading: true,
        error: null,
        participantTurnRuntime: s.participantTurnRuntime?.copyWith(
          paused: false,
          stopRequested: false,
        ),
      ),
    );
    _onSendStarted();
    try {
      await _runParticipantTurnLoop(
        turn: turn,
        participants: participants,
        config: paused.config,
        initialCursor: cursor,
        initialPreferredParticipantId: paused.preferredParticipantId,
        initialLastSpeakerParticipantId: paused.lastSpeakerParticipantId,
      );
    } catch (error) {
      await _failParticipantTurn(turn, error);
    } finally {
      _activeInteractionOrigin = ChatInteractionOrigin.local;
    }
  }

  Future<void> _sendWithParticipantTurns({
    required int interactionGeneration,
    required Conversation currentConversation,
    required ConversationsNotifier conversationsNotifier,
  }) async {
    const coordinator = ParticipantTurnCoordinator();
    final ownerId = _activeResponseConversationIdForGeneration(
      interactionGeneration,
    );
    if (ownerId == null || ownerId != currentConversation.id) {
      _failRuntimeTurn(
        interactionGeneration,
        code: 'participant_owner_mismatch',
        message: 'The participant turn owner could not be resolved.',
      );
      return;
    }
    final turn = (generation: interactionGeneration, ownerId: ownerId);
    final owner = _participantTurnOwner(turn);
    final pausedOwner = _participantTurnControls.pausedOwnerForConversation(
      ownerId,
    );
    if (pausedOwner != null && pausedOwner != owner) {
      _participantTurnControls.dispose(pausedOwner);
    }
    if (!_participantTurnControls.begin(owner)) {
      _failRuntimeTurn(
        interactionGeneration,
        code: 'participant_control_state_unavailable',
        message: 'Participant turn control state could not be initialized.',
      );
      return;
    }
    try {
      final participants = List<ConversationParticipant>.unmodifiable(
        coordinator.normalizeParticipants(
          participants: currentConversation.participants,
          primaryModel: _settings.effectiveModel,
        ),
      );
      if (!listEquals(participants, currentConversation.participants)) {
        await conversationsNotifier.updateConversationParticipants(
          ownerId,
          participants: participants,
        );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      }
      if (coordinator.orderedEnabledParticipants(participants).isEmpty) {
        _denyTools(interactionGeneration);
        await _completeParticipantTurns(
          turn,
          '',
          exitReason: 'participant_turn_empty_roster',
        );
        return;
      }
      await _runParticipantTurnLoop(
        turn: turn,
        participants: participants,
        config: currentConversation.participantTurnConfig,
        initialCursor: const ParticipantTurnCursor(),
      );
    } catch (error) {
      await _failParticipantTurn(turn, error);
    }
  }

  Future<void> _runParticipantTurnLoop({
    required _ParticipantTurn turn,
    required List<ConversationParticipant> participants,
    required ParticipantTurnConfig config,
    required ParticipantTurnCursor initialCursor,
    String? initialPreferredParticipantId,
    String? initialLastSpeakerParticipantId,
  }) async {
    const coordinator = ParticipantTurnCoordinator();
    var cursor = initialCursor;
    String completedContent = '';
    String? preferredParticipantId = initialPreferredParticipantId;
    String? lastSpeakerParticipantId = initialLastSpeakerParticipantId;
    while (_isCurrentInteractionGeneration(turn.generation)) {
      final decision = coordinator.nextSpeaker(
        participants: participants,
        config: config,
        cursor: cursor,
        preferredParticipantId: preferredParticipantId,
        lastSpeakerParticipantId: lastSpeakerParticipantId,
      );
      preferredParticipantId = null;
      if (!decision.hasParticipant) {
        await _completeParticipantTurns(turn, completedContent);
        return;
      }
      final participant = decision.participant!;
      final isFinalTurn = decision.completed;
      _setParticipantTurnRuntime(
        turn,
        participant,
        config,
        decision.roundNumber,
      );
      final completion = await _streamParticipantTurn(
        turn,
        participant,
        participants,
        isFinalTurn,
      );
      if (completion == null) return;
      completedContent = completion.content;
      lastSpeakerParticipantId = participant.id;
      preferredParticipantId = completion.handoffId;
      if (!_isCurrentInteractionGeneration(turn.generation)) return;
      cursor = decision.cursor;
      if (_participantTurnControls.stopRequested(_participantTurnOwner(turn)) &&
          !isFinalTurn) {
        await _pauseParticipantTurns(
          turn: turn,
          participants: participants,
          config: config,
          cursor: cursor,
          preferredParticipantId: preferredParticipantId,
          lastSpeakerParticipantId: lastSpeakerParticipantId,
          completedContent: completedContent,
        );
        return;
      }
      if (isFinalTurn) {
        await _completeParticipantTurns(turn, completedContent);
        return;
      }
    }
  }

  Future<_ParticipantTurnCompletion?> _streamParticipantTurn(
    _ParticipantTurn turn,
    ConversationParticipant participant,
    List<ConversationParticipant> participants,
    bool isFinalTurn,
  ) async {
    final owner = _participantTurnOwner(turn);
    try {
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
      _appendParticipantPlaceholder(turn.generation, participantMessage);
      if (!_responseMetadata.start(owner)) {
        throw StateError(
          'Participant response metadata state could not be initialized.',
        );
      }
      final model = participant.model.trim().isEmpty
          ? _settings.effectiveModel
          : participant.model.trim();
      const coordinator = ParticipantTurnCoordinator();
      final participantRolePrompt = coordinator.buildRolePromptForParticipant(
        target: participant,
        participants: participants,
      );
      final promptMessages = coordinator.buildMessagesForParticipant(
        target: participant,
        participants: participants,
        transcript: _prepareMessagesForLLM(
          interactionGeneration: turn.generation,
          participantRolePrompt: participantRolePrompt,
        ),
        includeRolePrompt: false,
      );
      final participantToolDefinitions = _toolDefinitionsFor(participant);
      final participantToolNames = participantToolDefinitions
          .map(ParticipantToolPolicy.toolNameFromDefinition)
          .nonNulls
          .toSet();
      _activeResponseRegistry.setTools(turn.generation, participantToolNames);
      final usedParticipantToolNames = <String>[];
      final participantLogContext =
          _llmSessionLogContextForGeneration(turn.generation).withParticipant(
            participantId: participant.id,
            participantName: participant.effectiveDisplayName,
            participantRoleLabel: participant.effectiveRoleLabel,
            toolsEnabled: participant.toolsEnabled,
            toolNames: participantToolNames.toList(growable: false),
            phase: 'participant_turn',
          );
      final terminalMetadata = await LlmSessionLogContext.run(
        participantLogContext,
        () => _participantCompletionRunner.stream(
          primary: _dataSource,
          settings: _settings,
          request: ParticipantCompletionRequest(
            participant: participant,
            messages: promptMessages,
            model: model,
            temperature: _assistantRequestTemperature,
            maxTokens: _settings.maxTokens,
            toolDefinitions: participantToolDefinitions,
            executeToolCall: participantToolDefinitions.isEmpty
                ? null
                : (toolCall) async {
                    final result = await _executeParticipantToolCall(
                      toolCall,
                      turn,
                      participant,
                    );
                    if (result.isSuccess) {
                      usedParticipantToolNames.add(toolCall.name);
                    }
                    return result;
                  },
          ),
          shouldContinue: () =>
              _isCurrentInteractionGeneration(turn.generation),
          onChunk: (chunk) {
            _appendToLastMessageForGeneration(
              turn.generation,
              chunk,
              scanForTools: false,
            );
          },
        ),
      );
      if (terminalMetadata == null) {
        _responseMetadata.discard(owner);
        return (content: '', handoffId: null);
      }
      if (!_responseMetadata.capture(owner, terminalMetadata)) {
        return (content: '', handoffId: null);
      }
      if (!_isCurrentInteractionGeneration(turn.generation)) {
        _responseMetadata.discard(owner);
        return (content: '', handoffId: null);
      }
      return await _finalizeParticipantMessage(
        turn,
        isFinalTurn,
        participant,
        participants,
        usedParticipantToolNames,
      );
    } catch (error) {
      _responseMetadata.discard(owner);
      await _failParticipantTurn(turn, error);
      return null;
    }
  }

  List<Map<String, dynamic>> _toolDefinitionsFor(
    ConversationParticipant participant,
  ) {
    final service = _mcpToolService;
    if (!participant.toolsEnabled ||
        !_supportsToolAwareRequests ||
        service == null) {
      return const <Map<String, dynamic>>[];
    }
    return const ParticipantToolPolicy().filterDefinitions(
      service.getOpenAiToolDefinitions(),
    );
  }

  Future<McpToolResult> _executeParticipantToolCall(
    ToolCallInfo toolCall,
    _ParticipantTurn turn,
    ConversationParticipant participant,
  ) async {
    final denied = const ParticipantToolPolicy().enforce(toolCall);
    if (denied != null) {
      appLog(
        '[ParticipantTool] denied ${toolCall.name} for ${participant.id}: '
        '${denied.errorMessage}',
      );
      return denied;
    }
    final mcpToolService = _mcpToolService;
    if (mcpToolService == null) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'Participant tool service is unavailable.',
      );
    }
    final approvalCache = _approvalCacheForGeneration(turn.generation);
    if (approvalCache == null || !_ownsParticipantTurn(turn)) {
      return _inactiveToolResult(toolCall.name);
    }
    final approvalFailure = await _resolveParticipantToolApproval(
      toolCall,
      turn,
      participant,
      approvalCache,
    );
    if (approvalFailure != null) return approvalFailure;
    if (!_isApprovalOwnerCurrent(approvalCache.owner)) {
      return _inactiveToolResult(toolCall.name);
    }
    appLog(
      '[ParticipantTool] executing ${toolCall.name} for ${participant.id} '
      'with approvalMode=${participant.toolApprovalMode.name}',
    );
    _setParticipantToolActivity(turn, participant, toolCall.name);
    try {
      final result = await mcpToolService.executeTool(
        name: toolCall.name,
        arguments: toolCall.arguments,
      );
      ToolResultTaintRecorder.record(
        state: _conversationTaintState,
        owner: approvalCache.owner,
        result: result,
      );
      return result;
    } finally {
      _setParticipantToolActivity(turn, participant, '');
    }
  }

  Future<McpToolResult?> _resolveParticipantToolApproval(
    ToolCallInfo toolCall,
    _ParticipantTurn turn,
    ConversationParticipant participant,
    OwnerToolApprovalCache approvalCache,
  ) async {
    final ownerMessages = _activeResponseMessagesForGeneration(turn.generation);
    if (ownerMessages == null) {
      return _inactiveToolResult(toolCall.name);
    }
    final gate = await _resolveToolApprovalGate(
      approvalCache,
      toolCall: toolCall,
      actionKind: 'participant_read_only_tool',
      mode: participant.toolApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.participant,
      fullAccessEligible: true,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        approvalCache.owner,
        toolCall: toolCall,
        actionKind: 'participant_read_only_tool',
        arguments: {
          'participantId': participant.id,
          'participantName': participant.effectiveDisplayName,
          'participantRoleLabel': participant.effectiveRoleLabel,
          'toolArguments': toolCall.arguments,
        },
        reason: toolCall.arguments['reason'] as String?,
        conversationMessages: List<Message>.unmodifiable(ownerMessages),
      ),
    );
    if (!_isApprovalOwnerCurrent(approvalCache.owner)) {
      return _inactiveToolResult(toolCall.name);
    }
    if (gate.isDenied) {
      return _autoReviewDeniedResult(
        toolName: toolCall.name,
        rationale: gate.deniedRationale!,
      );
    }
    if (!gate.needsManual) return null;
    final approved = await _requestParticipantToolApproval(
      toolCall,
      approvalCache.owner,
      participant,
    );
    if (!_isApprovalOwnerCurrent(approvalCache.owner)) {
      return _inactiveToolResult(toolCall.name);
    }
    if (approved) return null;
    return McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({
        'ok': false,
        'code': 'approval_denied',
        'error': 'User denied the participant tool action.',
        'nextAction':
            'Ask the user for explicit approval before retrying this participant tool.',
      }),
      isSuccess: false,
      errorMessage: 'User denied participant tool action.',
    );
  }

  McpToolResult _inactiveToolResult(String toolName) => McpToolResult(
    toolName: toolName,
    result: '',
    isSuccess: false,
    errorMessage: 'The participant turn is no longer active.',
  );
  Future<bool> _requestParticipantToolApproval(
    ToolCallInfo toolCall,
    ChatTurnOwner owner,
    ConversationParticipant participant,
  ) {
    final completer = Completer<bool>();
    final reason = toolCall.arguments['reason'] as String?;
    final pending = PendingParticipantToolApproval(
      owner: owner,
      id: const Uuid().v4(),
      participantId: participant.id,
      participantName: participant.effectiveDisplayName,
      participantRoleLabel: participant.effectiveRoleLabel,
      toolName: toolCall.name,
      arguments: Map<String, dynamic>.from(toolCall.arguments),
      reason: reason,
      completer: completer,
    );
    return _registerPendingToolApproval(
      pending,
      (s) => s.copyWith(pendingParticipantToolApproval: pending),
      'participant_tool',
      _approvalSummary(
        reason,
        '${participant.effectiveDisplayName}: ${toolCall.name}',
      ),
      participant.effectiveDisplayName,
    );
  }

  bool resolveParticipantToolApproval({
    required String id,
    required bool approved,
  }) => _completeApproval<bool, PendingParticipantToolApproval>(
    id,
    (_) => approved,
  );

  void _setParticipantToolActivity(
    _ParticipantTurn turn,
    ConversationParticipant participant,
    String activeToolName,
  ) {
    if (!_ownsParticipantTurn(turn)) return;
    _routeThreadState(turn.ownerId, (s) {
      final runtime = s.participantTurnRuntime;
      if (runtime == null || runtime.activeParticipantId != participant.id) {
        return s;
      }
      return s.copyWith(
        participantTurnRuntime: runtime.copyWith(
          activeToolName: activeToolName,
        ),
      );
    });
  }

  void _appendParticipantPlaceholder(int generation, Message message) {
    final messages = [
      ...?_activeResponseMessagesForGeneration(generation),
      message,
    ];
    _cacheActiveResponseMessagesForGeneration(generation, messages);
    if (!_isActiveResponseDetachedForGeneration(generation) && ref.mounted) {
      state = state.copyWith(messages: messages);
    }
  }

  Future<_ParticipantTurnCompletion> _finalizeParticipantMessage(
    _ParticipantTurn turn,
    bool isFinalTurn,
    ConversationParticipant participant,
    List<ConversationParticipant> participants, [
    List<String> participantToolNames = const <String>[],
  ]) async {
    final owner = _participantTurnOwner(turn);
    if (!_isCurrentInteractionGeneration(turn.generation)) {
      _responseMetadata.discard(owner);
      return (content: '', handoffId: null);
    }
    final isDetached = _isActiveResponseDetachedForGeneration(turn.generation);
    final sourceMessages = _activeResponseMessagesForGeneration(
      turn.generation,
    );
    if (sourceMessages == null || sourceMessages.isEmpty) {
      _responseMetadata.discard(owner);
      return (content: '', handoffId: null);
    }
    final updatedMessages = [...sourceMessages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    final isTruncated = _isCompletionTruncated(
      _responseMetadata.finishReasonFor(owner) ?? '',
    );
    final handoff = isTruncated
        ? null
        : const ParticipantTurnCoordinator().extractHandoffDirective(
            content: lastMessage.content,
            participants: participants,
            sourceParticipantId: participant.id,
          );
    final handoffId = handoff?.targetParticipantId?.trim();
    final handoffTarget = handoffId?.isNotEmpty == true
        ? participants.where((item) => item.id == handoffId).firstOrNull
        : null;
    final visibleContent = handoff?.content ?? lastMessage.content;
    final shouldDropLastAssistant =
        lastMessage.role == MessageRole.assistant &&
        !_assistantMessageHasVisibleContent(visibleContent);
    _updateTokenUsage(owner);
    final responseMetrics = shouldDropLastAssistant
        ? null
        : _responseMetadata.consume(owner);
    if (shouldDropLastAssistant) {
      _responseMetadata.discard(owner);
      updatedMessages.removeAt(lastIndex);
    } else {
      final finalizedContent = isTruncated
          ? TruncationNotice.withMaxTokenNotice(visibleContent)
          : visibleContent;
      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: finalizedContent,
        isStreaming: false,
        participantToolNames: participantToolNames
            .map((name) => name.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList(growable: false),
        handoffTargetParticipantId: handoffTarget?.id,
        handoffTargetDisplayName: handoffTarget?.effectiveDisplayName,
        handoffTargetRoleLabel: handoffTarget?.effectiveRoleLabel,
        responseMetrics: responseMetrics,
      );
    }
    _cacheActiveResponseMessagesForGeneration(turn.generation, updatedMessages);
    if (!isDetached) {
      state = state.copyWith(
        messages: updatedMessages,
        isLoading: !isFinalTurn,
      );
    }
    await _messagePersistence.persistMessages(
      turn.ownerId,
      updatedMessages
          .where((message) => !message.isStreaming)
          .where(_messagePersistence.shouldKeepVisibleMessage)
          .toList(growable: false),
    );
    if (shouldDropLastAssistant || updatedMessages.isEmpty) {
      return (content: '', handoffId: handoff?.targetParticipantId);
    }
    final finalizedLastMessage = updatedMessages.last;
    if (!isDetached &&
        isFinalTurn &&
        _settings.autoReadEnabled &&
        _settings.ttsEnabled &&
        finalizedLastMessage.content.isNotEmpty) {
      _onAutoRead(finalizedLastMessage.content);
    }
    return (
      content: finalizedLastMessage.content,
      handoffId: handoff?.targetParticipantId,
    );
  }

  Future<void> _pauseParticipantTurns({
    required _ParticipantTurn turn,
    required List<ConversationParticipant> participants,
    required ParticipantTurnConfig config,
    required ParticipantTurnCursor cursor,
    required String? preferredParticipantId,
    required String? lastSpeakerParticipantId,
    required String completedContent,
  }) async {
    final owner = _participantTurnOwner(turn);
    final paused = _participantTurnControls.pause(
      owner,
      ParticipantTurnPauseSnapshot(
        cursor: cursor,
        participants: participants,
        config: config,
        preferredParticipantId: preferredParticipantId,
        lastSpeakerParticipantId: lastSpeakerParticipantId,
      ),
    );
    if (!paused) {
      await _failParticipantTurn(
        turn,
        StateError('Participant turn control state is unavailable.'),
      );
      return;
    }
    _routeThreadState(
      turn.ownerId,
      (s) => s.copyWith(
        isLoading: false,
        participantTurnRuntime: s.participantTurnRuntime?.copyWith(
          activeParticipantId: null,
          activeParticipantName: '',
          activeParticipantRoleLabel: '',
          activeParticipantColorValue: null,
          stopRequested: true,
          paused: true,
        ),
      ),
    );
    await _terminalizeParticipantTurn(
      turn,
      completedContent,
      'participant_turn_paused',
    );
  }

  Future<void> _completeParticipantTurns(
    _ParticipantTurn turn,
    String completedContent, {
    String exitReason = 'participant_turn_completed',
  }) async {
    _participantTurnControls.dispose(_participantTurnOwner(turn));
    _routeThreadState(
      turn.ownerId,
      (s) => s.copyWith(isLoading: false, participantTurnRuntime: null),
    );
    await _terminalizeParticipantTurn(turn, completedContent, exitReason);
  }

  Future<void> _terminalizeParticipantTurn(
    _ParticipantTurn turn,
    String content,
    String exitReason,
  ) async {
    _onResponseCompleted(content);
    _completeRuntimeTurn(
      turn.generation,
      content: content,
      exitReason: exitReason,
    );
    await _drainQueuedChatMessagesForThreadIfIdle(turn.ownerId);
  }

  void _setParticipantTurnRuntime(
    _ParticipantTurn turn,
    ConversationParticipant participant,
    ParticipantTurnConfig config,
    int roundNumber,
  ) {
    if (!_ownsParticipantTurn(turn)) return;
    final multiRound = config.depth == ParticipantTurnDepth.multiRound;
    _routeThreadState(
      turn.ownerId,
      (s) => s.copyWith(
        participantTurnRuntime: ParticipantTurnRuntime(
          activeParticipantId: participant.id,
          activeParticipantName: participant.effectiveDisplayName,
          activeParticipantRoleLabel: participant.effectiveRoleLabel,
          activeParticipantColorValue: participant.colorValue,
          currentRound: roundNumber,
          maxRounds: multiRound
              ? (config.maxRounds < 1 ? 1 : config.maxRounds)
              : 1,
          multiRound: multiRound,
          stopRequested: _participantTurnControls.stopRequested(
            _participantTurnOwner(turn),
          ),
        ),
      ),
    );
  }

  Future<void> _failParticipantTurn(_ParticipantTurn turn, Object error) async {
    if (!_ownsParticipantTurn(turn)) return;
    final displayError = ChatErrorMessageBuilder.build(
      error.toString(),
      baseUrl: _settings.baseUrl,
    );
    final sourceMessages =
        _activeResponseMessagesForGeneration(turn.generation) ??
        const <Message>[];
    final updatedMessages = [...sourceMessages];
    if (updatedMessages.isNotEmpty &&
        updatedMessages.last.role == MessageRole.assistant) {
      updatedMessages[updatedMessages.length - 1] = updatedMessages.last
          .copyWith(isStreaming: false, error: displayError);
    } else {
      updatedMessages.add(
        Message(
          id: _uuid.v4(),
          content: '',
          role: MessageRole.assistant,
          timestamp: DateTime.now(),
          error: displayError,
        ),
      );
    }
    _cacheActiveResponseMessagesForGeneration(turn.generation, updatedMessages);
    try {
      await _messagePersistence.persistMessages(
        turn.ownerId,
        updatedMessages
            .where((message) => !message.isStreaming)
            .where(
              (message) =>
                  message.error != null ||
                  _messagePersistence.shouldKeepVisibleMessage(message),
            )
            .toList(growable: false),
      );
    } catch (persistenceError) {
      appLog('[ParticipantTurn] failure persistence failed: $persistenceError');
    }
    if (!_ownsParticipantTurn(turn)) return;
    if (conversationId == turn.ownerId) {
      state = state.copyWith(messages: updatedMessages);
    }
    _routeThreadState(
      turn.ownerId,
      (s) => s.copyWith(
        isLoading: false,
        error: displayError,
        participantTurnRuntime: null,
      ),
    );
    _participantTurnControls.dispose(_participantTurnOwner(turn));
    final runtimeFailure = _runtimeFailureClassifier.classify(error.toString());
    _failRuntimeTurn(
      turn.generation,
      code: runtimeFailure.code,
      message: displayError,
      exitCode: runtimeFailure.exitCode,
    );
  }

  bool _ownsParticipantTurn(_ParticipantTurn turn) {
    final owner = _turnOwnerForGeneration(turn.generation);
    return owner != null &&
        owner.conversationId == turn.ownerId &&
        _isApprovalOwnerCurrent(owner);
  }

  ChatTurnOwner _participantTurnOwner(_ParticipantTurn turn) => ChatTurnOwner(
    conversationId: turn.ownerId,
    interactionGeneration: turn.generation,
  );
}
