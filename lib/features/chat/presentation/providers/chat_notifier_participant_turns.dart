// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

class _ParticipantTurnCompletion {
  const _ParticipantTurnCompletion({
    required this.content,
    this.handoffTargetParticipantId,
  });

  final String content;
  final String? handoffTargetParticipantId;
}

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
        initialPreferredParticipantId: _pausedParticipantTurnPreferredId,
        initialLastSpeakerParticipantId: _pausedParticipantTurnLastSpeakerId,
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
    String? initialPreferredParticipantId,
    String? initialLastSpeakerParticipantId,
  }) async {
    const coordinator = ParticipantTurnCoordinator();
    var cursor = initialCursor;
    String completedContent = '';
    String? preferredParticipantId = initialPreferredParticipantId;
    String? lastSpeakerParticipantId = initialLastSpeakerParticipantId;

    while (_isCurrentInteractionGeneration(interactionGeneration)) {
      final decision = coordinator.nextSpeaker(
        participants: participants,
        config: config,
        cursor: cursor,
        preferredParticipantId: preferredParticipantId,
        lastSpeakerParticipantId: lastSpeakerParticipantId,
      );
      preferredParticipantId = null;
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
      final completion = await _streamParticipantTurn(
        interactionGeneration: interactionGeneration,
        participant: participant,
        participants: participants,
        isFinalTurn: isFinalTurn,
      );
      completedContent = completion.content;
      lastSpeakerParticipantId = participant.id;
      preferredParticipantId = completion.handoffTargetParticipantId;
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;

      cursor = decision.cursor;
      if (_participantTurnStopRequested && !isFinalTurn) {
        await _pauseParticipantTurns(
          generation: interactionGeneration,
          targetConversationId: targetConversationId,
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
        await _completeParticipantTurns(
          generation: interactionGeneration,
          completedContent: completedContent,
        );
        return;
      }
    }
  }

  Future<_ParticipantTurnCompletion> _streamParticipantTurn({
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
    const coordinator = ParticipantTurnCoordinator();
    final participantRolePrompt = coordinator.buildRolePromptForParticipant(
      target: participant,
      participants: participants,
    );
    final promptMessages = coordinator.buildMessagesForParticipant(
      target: participant,
      participants: participants,
      transcript: _prepareMessagesForLLM(
        interactionGeneration: interactionGeneration,
        participantRolePrompt: participantRolePrompt,
      ),
      includeRolePrompt: false,
    );
    final participantToolDefinitions = _participantToolDefinitionsFor(
      participant,
    );
    final usedParticipantToolNames = <String>[];

    try {
      final participantLogContext =
          _llmSessionLogContextForGeneration(
            interactionGeneration,
          ).withParticipant(
            participantId: participant.id,
            participantName: participant.effectiveDisplayName,
            participantRoleLabel: participant.effectiveRoleLabel,
            toolsEnabled: participant.toolsEnabled,
            toolNames: participantToolDefinitions
                .map(ParticipantToolPolicy.toolNameFromDefinition)
                .nonNulls
                .toList(growable: false),
            phase: 'participant_turn',
          );
      await LlmSessionLogContext.run(
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
                      participant: participant,
                    );
                    if (result.isSuccess) {
                      usedParticipantToolNames.add(toolCall.name);
                    }
                    return result;
                  },
          ),
          shouldContinue: () =>
              _isCurrentInteractionGeneration(interactionGeneration),
          onChunk: (chunk) {
            _appendToLastMessageForGeneration(
              interactionGeneration,
              chunk,
              scanForTools: false,
            );
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
      return const _ParticipantTurnCompletion(content: '');
    }

    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return const _ParticipantTurnCompletion(content: '');
    }
    return _finalizeParticipantTurnMessage(
      generation: interactionGeneration,
      isFinalTurn: isFinalTurn,
      participant: participant,
      participants: participants,
      participantToolNames: usedParticipantToolNames,
    );
  }

  List<Map<String, dynamic>> _participantToolDefinitionsFor(
    ConversationParticipant participant,
  ) {
    if (!participant.toolsEnabled || !_supportsToolAwareRequests) {
      return const <Map<String, dynamic>>[];
    }
    final mcpToolService = _mcpToolService;
    if (mcpToolService == null) {
      return const <Map<String, dynamic>>[];
    }
    return const ParticipantToolPolicy().filterDefinitions(
      mcpToolService.getOpenAiToolDefinitions(),
    );
  }

  Future<McpToolResult> _executeParticipantToolCall(
    ToolCallInfo toolCall, {
    required ConversationParticipant participant,
  }) async {
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

    final approvalFailure = await _resolveParticipantToolApproval(
      toolCall,
      participant: participant,
    );
    if (approvalFailure != null) {
      return approvalFailure;
    }

    appLog(
      '[ParticipantTool] executing ${toolCall.name} for ${participant.id} '
      'with approvalMode=${participant.toolApprovalMode.name}',
    );
    _setParticipantToolActivity(
      participant: participant,
      toolName: toolCall.name,
    );
    try {
      final result = await mcpToolService.executeTool(
        name: toolCall.name,
        arguments: toolCall.arguments,
      );
      _conversationTaintState.recordToolResult(toolCall.name);
      return result;
    } finally {
      _clearParticipantToolActivity(
        participant: participant,
        toolName: toolCall.name,
      );
    }
  }

  Future<McpToolResult?> _resolveParticipantToolApproval(
    ToolCallInfo toolCall, {
    required ConversationParticipant participant,
  }) async {
    final gate = await _resolveToolApprovalGate(
      toolCall: toolCall,
      actionKind: 'participant_read_only_tool',
      mode: participant.toolApprovalMode,
      reviewDomain: ToolApprovalAutoReviewDomain.participant,
      fullAccessEligible: true,
      buildReviewRequest: () async => _buildAutoReviewRequest(
        toolCall: toolCall,
        actionKind: 'participant_read_only_tool',
        arguments: _participantToolReviewArguments(
          toolCall,
          participant: participant,
        ),
        reason: toolCall.arguments['reason'] as String?,
      ),
    );

    if (gate.isDenied) {
      return _autoReviewDeniedResult(
        toolName: toolCall.name,
        rationale: gate.deniedRationale!,
      );
    }

    if (!gate.needsManual) {
      return null;
    }

    final approved = await requestParticipantToolApproval(
      toolCall: toolCall,
      participant: participant,
    );
    if (approved) {
      return null;
    }
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

  Map<String, dynamic> _participantToolReviewArguments(
    ToolCallInfo toolCall, {
    required ConversationParticipant participant,
  }) {
    return {
      'participantId': participant.id,
      'participantName': participant.effectiveDisplayName,
      'participantRoleLabel': participant.effectiveRoleLabel,
      'toolArguments': toolCall.arguments,
    };
  }

  Future<bool> requestParticipantToolApproval({
    required ToolCallInfo toolCall,
    required ConversationParticipant participant,
  }) {
    final completer = Completer<bool>();
    final reason = toolCall.arguments['reason'] as String?;
    final pending = PendingParticipantToolApproval(
      id: const Uuid().v4(),
      participantName: participant.effectiveDisplayName,
      participantRoleLabel: participant.effectiveRoleLabel,
      toolName: toolCall.name,
      arguments: Map<String, dynamic>.from(toolCall.arguments),
      reason: reason,
      completer: completer,
    );
    state = state.copyWith(pendingParticipantToolApproval: pending);
    _emitRuntimeApprovalRequired(
      id: pending.id,
      capability: 'participant_tool',
      summary: reason?.trim().isNotEmpty == true
          ? reason!.trim()
          : '${participant.effectiveDisplayName}: ${toolCall.name}',
      target: participant.effectiveDisplayName,
    );
    return completer.future;
  }

  void resolveParticipantToolApproval({
    required String id,
    required bool approved,
  }) {
    final pending = state.pendingParticipantToolApproval;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
    state = state.copyWith(pendingParticipantToolApproval: null);
  }

  void _setParticipantToolActivity({
    required ConversationParticipant participant,
    required String toolName,
  }) {
    final runtime = state.participantTurnRuntime;
    if (runtime == null || runtime.activeParticipantId != participant.id) {
      return;
    }
    state = state.copyWith(
      participantTurnRuntime: runtime.copyWith(activeToolName: toolName),
    );
  }

  void _clearParticipantToolActivity({
    required ConversationParticipant participant,
    required String toolName,
  }) {
    final runtime = state.participantTurnRuntime;
    if (runtime == null ||
        runtime.activeParticipantId != participant.id ||
        runtime.activeToolName != toolName) {
      return;
    }
    state = state.copyWith(
      participantTurnRuntime: runtime.copyWith(activeToolName: ''),
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

  Future<_ParticipantTurnCompletion> _finalizeParticipantTurnMessage({
    required int generation,
    required bool isFinalTurn,
    required ConversationParticipant participant,
    required List<ConversationParticipant> participants,
    List<String> participantToolNames = const <String>[],
  }) async {
    if (!_isCurrentInteractionGeneration(generation)) {
      return const _ParticipantTurnCompletion(content: '');
    }

    final isDetached = _isActiveResponseDetachedForGeneration(generation);
    final sourceMessages = isDetached
        ? _activeResponseMessagesForGeneration(generation)
        : state.messages;
    if (sourceMessages == null || sourceMessages.isEmpty) {
      return const _ParticipantTurnCompletion(content: '');
    }

    final updatedMessages = [...sourceMessages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    final isTruncated = _isCompletionTruncated(_latestFinishReason() ?? '');
    final handoff = isTruncated
        ? null
        : const ParticipantTurnCoordinator().extractHandoffDirective(
            content: lastMessage.content,
            participants: participants,
            sourceParticipantId: participant.id,
          );
    final handoffTarget = _participantTurnHandoffTarget(
      participants: participants,
      targetParticipantId: handoff?.targetParticipantId,
    );
    final visibleContent = handoff?.content ?? lastMessage.content;
    final shouldDropLastAssistant =
        lastMessage.role == MessageRole.assistant &&
        !_assistantMessageHasVisibleContent(visibleContent);

    _updateTokenUsage();
    final responseMetrics = shouldDropLastAssistant
        ? null
        : _takeResponseMetricsForGeneration(generation);
    if (shouldDropLastAssistant) {
      _discardResponseMetricsForGeneration(generation);
      updatedMessages.removeAt(lastIndex);
    } else {
      final finalizedContent = isTruncated
          ? TruncationNotice.withMaxTokenNotice(visibleContent)
          : visibleContent;
      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: finalizedContent,
        isStreaming: false,
        participantToolNames: _dedupeParticipantToolNames(participantToolNames),
        handoffTargetParticipantId: handoffTarget?.id,
        handoffTargetDisplayName: handoffTarget?.effectiveDisplayName,
        handoffTargetRoleLabel: handoffTarget?.effectiveRoleLabel,
        responseMetrics: responseMetrics,
      );
    }

    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
    if (isDetached) {
      final targetConversationId = _activeResponseConversationIdForGeneration(
        generation,
      );
      if (targetConversationId == null) {
        return _ParticipantTurnCompletion(
          content: '',
          handoffTargetParticipantId: handoff?.targetParticipantId,
        );
      }
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
      return _ParticipantTurnCompletion(
        content: '',
        handoffTargetParticipantId: handoff?.targetParticipantId,
      );
    }
    final finalizedLastMessage = updatedMessages.last;
    if (!isDetached &&
        isFinalTurn &&
        _settings.autoReadEnabled &&
        _settings.ttsEnabled &&
        finalizedLastMessage.content.isNotEmpty) {
      _onAutoRead(finalizedLastMessage.content);
    }
    return _ParticipantTurnCompletion(
      content: finalizedLastMessage.content,
      handoffTargetParticipantId: handoff?.targetParticipantId,
    );
  }

  List<String> _dedupeParticipantToolNames(List<String> toolNames) {
    final seen = <String>{};
    final deduped = <String>[];
    for (final toolName in toolNames) {
      final normalized = toolName.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      deduped.add(normalized);
    }
    return deduped;
  }

  ConversationParticipant? _participantTurnHandoffTarget({
    required List<ConversationParticipant> participants,
    required String? targetParticipantId,
  }) {
    final normalizedTargetId = targetParticipantId?.trim();
    if (normalizedTargetId == null || normalizedTargetId.isEmpty) {
      return null;
    }
    for (final participant in participants) {
      if (participant.id == normalizedTargetId) {
        return participant;
      }
    }
    return null;
  }

  Future<void> _pauseParticipantTurns({
    required int generation,
    required String targetConversationId,
    required List<ConversationParticipant> participants,
    required ParticipantTurnConfig config,
    required ParticipantTurnCursor cursor,
    required String? preferredParticipantId,
    required String? lastSpeakerParticipantId,
    required String completedContent,
  }) async {
    _pausedParticipantTurnCursor = cursor;
    _pausedParticipantTurnParticipants = List.unmodifiable(participants);
    _pausedParticipantTurnConfig = config;
    _pausedParticipantTurnConversationId = targetConversationId;
    _pausedParticipantTurnPreferredId = preferredParticipantId;
    _pausedParticipantTurnLastSpeakerId = lastSpeakerParticipantId;
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
    _pausedParticipantTurnPreferredId = null;
    _pausedParticipantTurnLastSpeakerId = null;
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
