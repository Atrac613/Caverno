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
    if (shouldDropLastAssistant ||
        finalizedMessages.isEmpty ||
        _turnFinalizationRecoveryGenerations.contains(generation)) {
      return false;
    }
    final owner = _turnOwnerForGeneration(generation);
    if (owner == null) return false;
    final lastMessage = finalizedMessages.last;
    if (lastMessage.role != MessageRole.assistant ||
        !_assistantMessageHasVisibleContent(lastMessage.content)) {
      return false;
    }
    final candidateResponse = _turnFinalizationCandidateText(
      lastMessage.content,
      generation: generation,
    );
    if (candidateResponse.isEmpty) return false;
    if (_hasTerminalGoalSuccessToolResults(
      _turnToolResults.completed(owner),
      generation,
    )) {
      appLog(
        '[TurnFinalization] Skipping coding continuation recovery after terminal goal success',
      );
      return false;
    }
    if (_shouldSkipCompletedToolResultFinalAnswerRecovery(
      generation: generation,
      candidateResponse: candidateResponse,
      toolResults: _turnToolResults.completed(owner),
    )) {
      appLog(
        '[TurnFinalization] Skipping coding continuation recovery after completed tool-result final answer',
      );
      return false;
    }
    final mcpToolService = _mcpToolService;
    if (mcpToolService == null || !_settings.mcpEnabled) return false;
    final allTools = mcpToolService.getOpenAiToolDefinitions();
    if (allTools.isEmpty) return false;
    final prefixStableToolLoop = _settings.enablePrefixStableToolLoop;
    final toolSelection = prefixStableToolLoop
        ? ToolDefinitionSearchSelection(
            toolSearchEnabled: false,
            toolDefinitions: allTools,
            selectedToolNames:
                ToolDefinitionSearchService.toolNamesFromDefinitions(allTools),
          )
        : ToolDefinitionSearchService.buildInitialSelection(allTools);
    if (_codingContinuationRecoveryCode(
          candidateResponse: candidateResponse,
          tools: toolSelection.toolDefinitions,
          interactionGeneration: generation,
          requireContinuationRequest: false,
        ) ==
        null) {
      return false;
    }

    _turnFinalizationRecoveryGenerations.add(generation);
    appLog('[TurnFinalization] Requesting recovery before saving response');
    final recoveryResult = await _requestCodingContinuationRecovery(
      candidateResponse: candidateResponse,
      tools: toolSelection.toolDefinitions,
      interactionGeneration: generation,
      requireContinuationRequest: false,
    );
    if (!_isCurrentInteractionGeneration(generation)) return true;
    if (!ref.mounted || recoveryResult == null) return false;
    _recordHiddenEvidence(owner, candidateResponse);
    if (!recoveryResult.hasToolCalls) {
      _recordHiddenEvidence(owner, recoveryResult.content);
      return false;
    }

    appLog('[TurnFinalization] Recovery requested tool calls');
    _prepareLastAssistantForTurnFinalizationRecovery(
      generation: generation,
      preRecoveryContent: _contentBeforeFinalizationCandidate(
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
        ...toolSelection.selectedToolNames,
        ...recoveredToolNames,
      },
      stableToolDefinitions: prefixStableToolLoop
          ? toolSelection.toolDefinitions
          : null,
      interactionGeneration: generation,
    );
    return true;
  }

  bool _hasTerminalGoalSuccessToolResults(
    List<ToolResultInfo> toolResults,
    int interactionGeneration,
  ) {
    if (toolResults.isEmpty) return false;
    const terminalSuccessPolicy = ToolTerminalSuccessPolicy();
    return toolResults.any(
          (toolResult) =>
              terminalSuccessPolicy.terminalMessage(toolResult.result) != null,
        ) ||
        _toolResultsContainSuccessfulCurrentSavedValidation(
          toolResults,
          interactionGeneration,
        ) ||
        _toolResultsSatisfyCurrentGoalGitLifecycle(toolResults);
  }

  bool _shouldSkipCompletedToolResultFinalAnswerRecovery({
    required int generation,
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    return const TurnFinalizationRecoveryPolicy()
        .shouldSkipCompletedToolResultFinalAnswerRecovery(
          _turnFinalizationRecoveryInput(
            candidateResponse: candidateResponse,
            streamedFinalAnswer:
                _lastStreamedToolResultFinalAnswersByGeneration[generation],
            toolResults: toolResults,
            interactionGeneration: generation,
          ),
        );
  }

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
  }) {
    return TurnFinalizationRecoveryInput(
      candidateResponse: candidateResponse,
      streamedFinalAnswer: streamedFinalAnswer,
      toolResults: toolResults,
      hasTimedOutCommandResult: _hasTimedOutCommandResult(toolResults),
      hasFailedCommandValidation: _toolResultsContainFailedCommandValidation(
        toolResults,
      ),
      hasUnexecutedCommandActionResult: _claims
          .hasUnexecutedCommandActionResult(toolResults),
      hasUnexecutedFileSideEffectResult: _claims
          .hasUnexecutedFileSideEffectResult(toolResults),
      hasSuccessfulCurrentSavedValidation:
          interactionGeneration != null &&
          _toolResultsContainSuccessfulCurrentSavedValidation(
            toolResults,
            interactionGeneration,
          ),
      hasSuccessfulFileMutationEvidence: toolResults.any(
        (toolResult) =>
            _fileMutationEvidencePolicy.isMutationToolName(toolResult.name) &&
            _fileMutationEvidencePolicy.isSuccessfulResult(toolResult),
      ),
      hasSuccessfulCommandExecutionEvidence: _claims
          .hasSuccessfulCommandExecutionResult(toolResults),
    );
  }

  bool _shouldSkipCompletedToolResultCodingContinuationRecovery({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
    required int interactionGeneration,
  }) {
    return const TurnFinalizationRecoveryPolicy()
        .shouldSkipCompletedToolResultCodingContinuationRecovery(
          _turnFinalizationRecoveryInput(
            candidateResponse: candidateResponse,
            streamedFinalAnswer: null,
            toolResults: toolResults,
            interactionGeneration: interactionGeneration,
          ),
        );
  }

  String _turnFinalizationCandidateText(
    String content, {
    required int generation,
  }) {
    return const TurnFinalizationRecoveryPolicy().turnFinalizationCandidateText(
      content: content,
      streamedFinalAnswer:
          _lastStreamedToolResultFinalAnswersByGeneration[generation],
    );
  }

  String _contentBeforeFinalizationCandidate({
    required String currentContent,
    required String candidateResponse,
  }) {
    return const TurnFinalizationRecoveryPolicy()
        .contentBeforeFinalizationCandidate(
          currentContent: currentContent,
          candidateResponse: candidateResponse,
        );
  }

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
