// Same-library extension; see chat_notifier_git_handlers.dart for rationale.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

/// Re-enters the tool loop once when an apparently final turn still requires
/// recovery, before the response is saved.
extension ChatNotifierTurnFinalizationRecovery on ChatNotifier {
  Future<bool> _recoverBeforeTurnFinalizationIfNeeded({
    required int generation,
    required List<Message> finalizedMessages,
    required bool shouldDropLastAssistant,
  }) async {
    if (shouldDropLastAssistant || finalizedMessages.isEmpty) {
      return false;
    }
    final owner = _turnOwnerForGeneration(generation);
    if (owner == null) return false;
    final lastMessage = finalizedMessages.last;
    if (lastMessage.role != MessageRole.assistant ||
        !TurnFinalMessage.hasVisibleContent(lastMessage.content)) {
      return false;
    }
    final candidateResponse = const TurnFinalizationRecoveryPolicy()
        .turnFinalizationCandidateText(
          content: lastMessage.content,
          streamedFinalAnswer:
              _lastStreamedToolResultFinalAnswersByGeneration[generation],
        );
    if (candidateResponse.isEmpty) return false;
    final completedResults = _turnToolResults.completed(owner);
    final mcpToolService = _mcpToolService;
    if (mcpToolService == null || !_settings.mcpEnabled) return false;
    final allTools = mcpToolService.getOpenAiToolDefinitions();
    if (allTools.isEmpty) return false;
    _synchronizeGoalAutoContinueSafeBoundary();
    final allowVerificationRepair = _turnFinalizationRecoveryGenerations
        .canRepairVerification(generation, completedResults);
    final terminalStatusOnly =
        !allowVerificationRepair &&
        _primaryRoutes.isProjectTaskImplementation(generation) &&
        _turnFinalizationRecoveryGenerations.needsVerificationStatus(
          generation,
          completedResults,
        );
    final plan = TurnFinalizationRecoveryPlan(
      goal: _conversationForId(owner.conversationId)?.goal,
      implementationTurn: _primaryRoutes.isProjectTaskImplementation(
        generation,
      ),
      terminalStatusOnly: terminalStatusOnly,
      allowVerificationRepair: allowVerificationRepair,
      stepTurn: _primaryRoutes.isProjectTaskStep(generation),
      boundarySafe: _turnRuntimeGoalSafeBoundary
          .captureFor(owner, withinTurn: true)
          .isSafe,
      acknowledgement: _turnEnd
          .stateFor(owner)
          ?.goalUpdateAcknowledgement
          ?.outcome,
      parentTurn: _anabasisRoles.isParentTurn(generation),
      response: candidateResponse,
      completedResults: completedResults,
      hasSavedValidation: _toolResultsContainSuccessfulCurrentSavedValidation(
        completedResults,
        generation,
      ),
      hasGitLifecycle: _toolResultsSatisfyCurrentGoalGitLifecycle(
        completedResults,
      ),
      skipCompletedAnswer: _shouldSkipCompletedToolResultFinalAnswerRecovery(
        generation: generation,
        candidateResponse: candidateResponse,
        toolResults: completedResults,
      ),
      allTools: allTools,
      prefixStable: _settings.enablePrefixStableToolLoop,
    );
    _turnEnd.recordFinalAnswerRecoveryDecision(
      owner,
      shouldSkip: plan.skipFinalAnswer,
    );
    if (!plan.shouldRecover) return false;
    final structuredTask = plan.structuredTask;
    final toolSelection = plan.selection;
    final forcedRecoveryCode = plan.forcedCode;
    if (forcedRecoveryCode == null &&
        _codingContinuationRecoveryCode(
              candidateResponse: candidateResponse,
              tools: toolSelection.tools,
              interactionGeneration: generation,
              requireContinuationRequest: false,
            ) ==
            null) {
      return false;
    }

    final claimed = plan.verificationRepair
        ? _turnFinalizationRecoveryGenerations.claimVerificationRepair(
            generation,
            completedResults,
          )
        : _turnFinalizationRecoveryGenerations.claim(
            generation,
            structuredTask: structuredTask || plan.structuredStep,
            results: completedResults,
            statusOnly: terminalStatusOnly,
          );
    if (!claimed) {
      return false;
    }
    appLog('[TurnFinalization] Requesting recovery before saving response');
    final recoveryResult = await _requestCodingContinuationRecovery(
      candidateResponse: candidateResponse,
      tools: plan.requestTools,
      interactionGeneration: generation,
      requireContinuationRequest: false,
      forcedRecoveryCode: forcedRecoveryCode,
      forcedRecoveryPrompt: plan.prompt,
      executedToolResults: completedResults,
    );
    if (!_isCurrentInteractionGeneration(generation)) return true;
    if (!ref.mounted || recoveryResult == null) return false;
    _recordHiddenEvidence(owner, candidateResponse);
    if (!recoveryResult.hasToolCalls ||
        !plan.acceptsCalls(recoveryResult.toolCalls!)) {
      _recordHiddenEvidence(owner, recoveryResult.content);
      if (plan.verificationRepair) {
        // No work ran. Fall through to the bounded status protocol rather
        // than saving an answer with neither repair nor an acknowledgement.
        return _recoverBeforeTurnFinalizationIfNeeded(
          generation: generation,
          finalizedMessages: finalizedMessages,
          shouldDropLastAssistant: shouldDropLastAssistant,
        );
      }
      if (plan.structuredStep) {
        final status = const ProjectTaskStepCompletionPolicy().status(
          response: recoveryResult.content,
          results: completedResults,
          goal: _conversationForId(owner.conversationId)?.goal,
        );
        if (!recoveryResult.hasToolCalls && status.completionAccepted) {
          _lastStreamedToolResultFinalAnswersByGeneration.remove(generation);
          _prepareLastAssistantForTurnFinalizationRecovery(
            generation: generation,
            preRecoveryContent: '',
          );
          _appendRecoveredAssistantResponse(
            recoveryResult.content,
            interactionGeneration: generation,
          );
        }
      } else if (structuredTask) {
        _turnEnd.addTransform(owner, 'coding_task_status_missing');
      } else if (forcedRecoveryCode != null) {
        _turnEnd.addTransform(owner, 'unexecuted_delegation_notice');
        _appendRecoveredAssistantResponse(
          'Delegation was not executed. No spawn_subagent result was recorded.',
          interactionGeneration: generation,
        );
      }
      return false;
    }

    appLog('[TurnFinalization] Recovery requested tool calls');
    _prepareLastAssistantForTurnFinalizationRecovery(
      generation: generation,
      preRecoveryContent: const TurnFinalizationRecoveryPolicy()
          .contentBeforeFinalizationCandidate(
            currentContent: lastMessage.content,
            candidateResponse: candidateResponse,
          ),
    );
    final recoveredToolNames = recoveryResult.toolCalls!.map(
      (toolCall) => toolCall.name,
    );
    await _executeToolCalls(
      recoveryResult.toolCalls!,
      assistantContent: recoveryResult.content.isNotEmpty
          ? recoveryResult.content
          : candidateResponse,
      toolSearchEnabled: toolSelection.toolSearchEnabled,
      selectedToolNames: {
        ...toolSelection.selectedNames,
        ...recoveredToolNames,
      },
      stableToolDefinitions: _settings.enablePrefixStableToolLoop
          ? toolSelection.tools
          : null,
      interactionGeneration: generation,
    );
    return true;
  }

  bool _shouldSkipCompletedToolResultFinalAnswerRecovery({
    required int generation,
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) => const TurnFinalizationRecoveryPolicy()
      .shouldSkipCompletedToolResultFinalAnswerRecovery(
        _turnFinalizationRecoveryInput(
          candidateResponse: candidateResponse,
          streamedFinalAnswer:
              _lastStreamedToolResultFinalAnswersByGeneration[generation],
          toolResults: toolResults,
          interactionGeneration: generation,
        ),
      );

  @visibleForTesting
  void cacheStreamedToolResultFinalAnswerForTest({
    required int generation,
    required String answer,
  }) {
    _lastStreamedToolResultFinalAnswersByGeneration[generation] = answer;
  }

  @visibleForTesting
  bool shouldSkipCompletedToolResultFinalAnswerRecoveryForTest({
    required int generation,
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    return _shouldSkipCompletedToolResultFinalAnswerRecovery(
      generation: generation,
      candidateResponse: candidateResponse,
      toolResults: toolResults,
    );
  }

  TurnFinalizationRecoveryInput _turnFinalizationRecoveryInput({
    required String candidateResponse,
    required String? streamedFinalAnswer,
    required List<ToolResultInfo> toolResults,
    int? interactionGeneration,
  }) => TurnFinalizationRecoveryInputBuilder.build(
    candidateResponse,
    streamedFinalAnswer,
    toolResults,
    timedOut: _hasTimedOutCommandResult(toolResults),
    failedValidation: _toolResultsContainFailedCommandValidation(toolResults),
    savedValidation:
        interactionGeneration != null &&
        _toolResultsContainSuccessfulCurrentSavedValidation(
          toolResults,
          interactionGeneration,
        ),
  );

  bool _shouldSkipCompletedToolResultCodingContinuationRecovery({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required int interactionGeneration,
  }) => const TurnFinalizationRecoveryPolicy()
      .shouldSkipCompletedToolResultCodingContinuationRecovery(
        _turnFinalizationRecoveryInput(
          candidateResponse: candidateResponse,
          streamedFinalAnswer: null,
          toolResults: toolResults,
          interactionGeneration: interactionGeneration,
        ),
      );

  void _prepareLastAssistantForTurnFinalizationRecovery({
    required int generation,
    required String preRecoveryContent,
  }) {
    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return;
      final updatedMessages = [...activeMessages];
      final lastIndex = updatedMessages.length - 1;
      final lastMessage = updatedMessages[lastIndex];
      if (lastMessage.role != MessageRole.assistant) return;
      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: preRecoveryContent,
        isStreaming: true,
      );
      _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
      return;
    }

    if (!ref.mounted || state.messages.isEmpty) return;
    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    if (lastMessage.role != MessageRole.assistant) return;
    updatedMessages[lastIndex] = lastMessage.copyWith(
      content: preRecoveryContent,
      isStreaming: true,
    );
    state = state.copyWith(
      messages: updatedMessages,
      isLoading: true,
      error: null,
    );
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
  }
}
