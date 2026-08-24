// Same-library extension; see chat_notifier_git_handlers.dart for lint context.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

typedef _ParticipantTurn = ({int generation, String ownerId});
typedef _ParticipantTurnCompletion = ({String content, String? handoffId});

extension ChatNotifierParticipantTurns on ChatNotifier {
  void _disposeAllParticipantTurnControls() {
    for (final owner in _participantTurnControls.owners) {
      _participantTurnControls.dispose(owner);
    }
  }

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
          origin: ChatInteractionOrigin.local,
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
      final initialPlan = const ParticipantTurnPlanner().start(
        owner: owner,
        participants: participants,
        primaryModel: _primaryModelForGeneration(turn.generation),
        config: paused.config,
        cursor: cursor,
        preferredParticipantId: paused.preferredParticipantId,
        lastSpeakerParticipantId: paused.lastSpeakerParticipantId,
      );
      await _runParticipantTurnLoop(turn: turn, initialPlan: initialPlan);
    } catch (error) {
      await _failParticipantTurn(turn, error);
    } finally {
      _activeInteractionOrigin = ChatInteractionOrigin.local;
      _activeRemoteDeviceId = null;
    }
  }

  Future<void> _sendWithParticipantTurns({
    required int interactionGeneration,
    required Conversation currentConversation,
    required ConversationsNotifier conversationsNotifier,
  }) async {
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
      final initialPlan = const ParticipantTurnPlanner().start(
        owner: owner,
        participants: currentConversation.participants,
        primaryModel: _primaryModelForGeneration(interactionGeneration),
        config: currentConversation.participantTurnConfig,
      );
      if (initialPlan.participantsChanged) {
        await conversationsNotifier.updateConversationParticipants(
          ownerId,
          participants: initialPlan.state.participants,
        );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      }
      await _runParticipantTurnLoop(turn: turn, initialPlan: initialPlan);
    } catch (error) {
      await _failParticipantTurn(turn, error);
    }
  }

  Future<void> _runParticipantTurnLoop({
    required _ParticipantTurn turn,
    required ParticipantTurnPlan initialPlan,
  }) async {
    const planner = ParticipantTurnPlanner();
    final owner = _participantTurnOwner(turn);
    var plan = initialPlan;
    while (_isCurrentInteractionGeneration(turn.generation)) {
      if (plan.state.owner != owner || !_ownsParticipantTurn(turn)) return;
      switch (plan.kind) {
        case ParticipantTurnStepKind.noParticipants:
          _denyTools(turn.generation);
          await _completeParticipantTurns(
            turn,
            plan.state.completedContent,
            exitReason: plan.exitReason!,
          );
          return;
        case ParticipantTurnStepKind.pause:
          await _pauseParticipantTurns(turn: turn, plan: plan);
          return;
        case ParticipantTurnStepKind.complete:
          await _completeParticipantTurns(
            turn,
            plan.state.completedContent,
            exitReason: plan.exitReason!,
          );
          return;
        case ParticipantTurnStepKind.streamParticipant:
          final participant = plan.participant!;
          final runtime = plan.runtime!;
          if (!_projectParticipantTurnRuntime(turn, runtime)) return;
          final completion = await _streamParticipantTurn(
            turn,
            participant,
            plan.state.participants,
            plan.state.awaitingFinalTurn,
          );
          if (completion == null || !_ownsParticipantTurn(turn)) return;
          plan = planner.advance(
            state: plan.state,
            completedContent: completion.content,
            handoffParticipantId: completion.handoffId,
            stopRequested: _participantTurnControls.stopRequested(owner),
          );
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
          ? _primaryModelForGeneration(turn.generation)
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
      final participantToolSession = _participantToolSession(turn, participant);
      final participantToolRuntime = _participantToolRuntime(turn, participant);
      final participantToolDefinitions = participantToolRuntime.definitionsFor(
        participantToolSession,
      );
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
          primary: _primaryDataSourceForGeneration(turn.generation),
          settings: _settings,
          request: ParticipantCompletionRequest(
            participant: participant,
            messages: promptMessages,
            model: model,
            temperature: _primaryAssistantTemperatureForGeneration(
              turn.generation,
            ),
            maxTokens: _settings.maxTokens,
            toolDefinitions: participantToolDefinitions,
            executeToolCall: participantToolDefinitions.isEmpty
                ? null
                : (toolCall) async {
                    final result = await _executeParticipantToolCall(
                      toolCall,
                      participantToolSession,
                      participantToolRuntime,
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
      return await _finalizeParticipantTurnMessage(
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

  ParticipantToolSession _participantToolSession(
    _ParticipantTurn turn,
    ConversationParticipant participant,
  ) => ParticipantToolSession(
    owner: _participantTurnOwner(turn),
    participant: participant,
    supportsToolAwareRequests: _supportsToolAwareRequests,
    availableDefinitions:
        _mcpToolService?.getOpenAiToolDefinitions() ??
        const <Map<String, dynamic>>[],
    conversationMessages:
        _activeResponseMessagesForGeneration(turn.generation) ??
        const <Message>[],
    hasUntrustedInfluence: _conversationTaintState.hasUntrustedInfluence(
      owner: _participantTurnOwner(turn),
    ),
  );

  ParticipantToolRuntimeAdapter _participantToolRuntime(
    _ParticipantTurn turn,
    ConversationParticipant participant,
  ) {
    final owner = _participantTurnOwner(turn);
    final service = _mcpToolService;
    final ports = ParticipantToolProductionPorts(
      scope: ParticipantToolScope(owner: owner, participantId: participant.id),
      participantDisplayName: participant.effectiveDisplayName,
      requestManualApproval: (identity, arguments) =>
          _requestParticipantToolApproval(
            ToolCallInfo(
              id: identity.toolCallId,
              name: identity.toolName,
              arguments: arguments,
            ),
            identity.owner,
            participant,
          ),
      autoReviewPort: CallbackToolApprovalAutoReviewPort(
        (owner, request, {required domain}) =>
            _runApprovalAutoReview(request, domain: domain),
      ),
      recordAudit: (identity, record) => _recordApprovalAudit(
        identity.owner,
        toolCall: ToolCallInfo(
          id: identity.toolCallId,
          name: identity.toolName,
          arguments: record.arguments,
        ),
        actionKind: record.actionKind,
        domain: record.domain,
        mode: record.mode,
        outcome: record.outcome,
        decisionSource: record.decisionSource,
        rationale: record.rationale,
        riskLevel: record.riskLevel,
      ),
      ownerPort: CallbackToolApprovalOwnerPort(_isApprovalOwnerCurrent),
      executeEffect: service == null
          ? null
          : (identity, arguments) async {
              appLog(
                '[ParticipantTool] executing ${identity.toolName} for '
                '${participant.id} with '
                'approvalMode=${participant.toolApprovalMode.name}',
              );
              var authorizedArguments = arguments;
              if (service.ownsBuiltInFilesystemEffects) {
                final authorization = await const ProjectReadToolAuthorizer()
                    .authorize(
                      toolName: identity.toolName,
                      arguments: arguments,
                      projectRoot: _getActiveProjectRootPath(),
                    );
                if (!authorization.isAllowed) {
                  return authorization.deniedResult!;
                }
                authorizedArguments = authorization.arguments!;
              }
              return service.executeTool(
                name: identity.toolName,
                arguments: authorizedArguments,
              );
            },
      projectActivity: (_, activeToolName) =>
          _setParticipantToolActivity(turn, participant, activeToolName),
      recordTaint: (identity, result) => ToolResultTaintRecorder.record(
        state: _conversationTaintState,
        owner: identity.owner,
        result: result,
      ),
    );
    return ParticipantToolRuntimeAdapter(
      resolveApproval: ports.resolveApproval,
      execute: ports.execute,
      projectActivity: ports.projectActivity,
      recordTaint: ports.recordTaint,
    );
  }

  Future<McpToolResult> _executeParticipantToolCall(
    ToolCallInfo toolCall,
    ParticipantToolSession session,
    ParticipantToolRuntimeAdapter runtime,
  ) async {
    final completion = await runtime.handle(session, toolCall);
    if (completion.disposition == ParticipantToolRuntimeDisposition.rejected) {
      appLog(
        '[ParticipantTool] rejected ${toolCall.name} for '
        '${session.participant.id}: ${completion.result.errorMessage}',
      );
    }
    return completion.result;
  }

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

  bool _setParticipantToolActivity(
    _ParticipantTurn turn,
    ConversationParticipant participant,
    String activeToolName,
  ) {
    if (!_ownsParticipantTurn(turn)) return false;
    final runtime = turn.ownerId == conversationId
        ? state.participantTurnRuntime
        : _threadStates[turn.ownerId]?.participantTurnRuntime;
    if (runtime == null || runtime.activeParticipantId != participant.id) {
      return false;
    }
    _routeThreadState(turn.ownerId, (s) {
      return s.copyWith(
        participantTurnRuntime: runtime.copyWith(
          activeToolName: activeToolName,
        ),
      );
    });
    return true;
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

  Future<_ParticipantTurnCompletion> _finalizeParticipantTurnMessage(
    _ParticipantTurn turn,
    bool isFinalTurn,
    ConversationParticipant participant,
    List<ConversationParticipant> participants, [
    List<String> participantToolNames = const <String>[],
  ]) async {
    final owner = _participantTurnOwner(turn);
    final ownerIsCurrent = _isCurrentInteractionGeneration(turn.generation);
    const finalizer = ParticipantMessageFinalizer();
    final plan = finalizer.plan(
      ParticipantMessageFinalizationInput(
        owner: owner,
        ownerIsCurrent: ownerIsCurrent,
        sourceMessages: ownerIsCurrent
            ? _activeResponseMessagesForGeneration(turn.generation)
            : null,
        isFinalTurn: isFinalTurn,
        participant: participant,
        participants: participants,
        participantToolNames: participantToolNames,
        finishReason: ownerIsCurrent
            ? _responseMetadata.finishReasonFor(owner) ?? ''
            : '',
        isDetached:
            ownerIsCurrent &&
            _isActiveResponseDetachedForGeneration(turn.generation),
        autoReadEnabled: _settings.autoReadEnabled,
        ttsEnabled: _settings.ttsEnabled,
      ),
    );
    if (plan.shouldUpdateTokenUsage) {
      _updateTokenUsage(owner);
    }
    final result = switch (plan.metricsDisposition) {
      ParticipantResponseMetricsDisposition.consume => finalizer.applyMetrics(
        plan,
        _responseMetadata.consume(owner),
      ),
      ParticipantResponseMetricsDisposition.discard => () {
        _responseMetadata.discard(owner);
        return finalizer.completeAfterDiscard(plan);
      }(),
    };
    if (result.shouldApplyOwnerMessages) {
      _cacheActiveResponseMessagesForGeneration(
        turn.generation,
        result.updatedMessages,
      );
    }
    if (result.shouldUpdateVisibleState) {
      state = state.copyWith(
        messages: result.updatedMessages,
        isLoading: result.visibleIsLoading!,
      );
    }
    if (result.shouldPersist) {
      await _messagePersistence.persistMessages(
        turn.ownerId,
        result.messagesToSave,
      );
    }
    final autoReadContent = result.autoReadContent;
    if (autoReadContent != null) {
      _onAutoRead(autoReadContent);
    }
    return (
      content: result.content,
      handoffId: result.handoffTargetParticipantId,
    );
  }

  Future<void> _pauseParticipantTurns({
    required _ParticipantTurn turn,
    required ParticipantTurnPlan plan,
  }) async {
    final owner = _participantTurnOwner(turn);
    if (plan.state.owner != owner ||
        plan.kind != ParticipantTurnStepKind.pause ||
        plan.runtime == null) {
      await _failParticipantTurn(
        turn,
        StateError('Participant pause plan does not match the active owner.'),
      );
      return;
    }
    final paused = _participantTurnControls.pause(
      owner,
      ParticipantTurnPauseSnapshot(
        cursor: plan.state.cursor,
        participants: plan.state.participants,
        config: plan.state.config,
        preferredParticipantId: plan.state.preferredParticipantId,
        lastSpeakerParticipantId: plan.state.lastSpeakerParticipantId,
      ),
    );
    if (!paused) {
      await _failParticipantTurn(
        turn,
        StateError('Participant turn control state is unavailable.'),
      );
      return;
    }
    if (!_projectParticipantTurnRuntime(
      turn,
      plan.runtime!,
      isLoading: false,
    )) {
      _participantTurnControls.dispose(owner);
      return;
    }
    await _terminalizeParticipantTurn(
      turn,
      plan.state.completedContent,
      plan.exitReason!,
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

  bool _projectParticipantTurnRuntime(
    _ParticipantTurn turn,
    ParticipantTurnRuntimeProjection projection, {
    bool? isLoading,
  }) {
    if (!_ownsParticipantTurn(turn)) return false;
    _routeThreadState(turn.ownerId, (s) {
      final projected = s.copyWith(
        participantTurnRuntime: ParticipantTurnRuntime(
          activeParticipantId: projection.activeParticipantId,
          activeParticipantName: projection.activeParticipantName,
          activeParticipantRoleLabel: projection.activeParticipantRoleLabel,
          activeParticipantColorValue: projection.activeParticipantColorValue,
          currentRound: projection.currentRound,
          maxRounds: projection.maxRounds,
          multiRound: projection.multiRound,
          stopRequested: projection.stopRequested,
          paused: projection.paused,
          activeToolName: projection.activeToolName,
        ),
      );
      return isLoading == null
          ? projected
          : projected.copyWith(isLoading: isLoading);
    });
    return true;
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
