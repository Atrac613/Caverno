// Same-library extension on [ChatNotifier]; see chat_notifier_git_handlers.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

/// Turn-finalization recovery, extracted verbatim from `ChatNotifier` to keep
/// the file within its F1 line-count budget. Behavior-neutral move: these
/// helpers decide whether an apparently-final assistant turn should re-enter the
/// tool loop for one bounded recovery pass before the response is saved.
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
    final lastMessage = finalizedMessages.last;
    if (lastMessage.role != MessageRole.assistant ||
        !_assistantMessageHasVisibleContent(lastMessage.content)) {
      return false;
    }
    final candidateResponse = _turnFinalizationCandidateText(
      lastMessage.content,
      generation: generation,
    );
    if (candidateResponse.isEmpty) {
      return false;
    }
    if (_hasTerminalGoalSuccessToolResults(_latestCompletedToolResults)) {
      appLog(
        '[TurnFinalization] Skipping coding continuation recovery after terminal goal success',
      );
      return false;
    }
    if (_shouldSkipCompletedToolResultFinalAnswerRecovery(
      generation: generation,
      candidateResponse: candidateResponse,
      toolResults: _latestCompletedToolResults,
    )) {
      appLog(
        '[TurnFinalization] Skipping coding continuation recovery after completed tool-result final answer',
      );
      return false;
    }
    final mcpToolService = _mcpToolService;
    if (mcpToolService == null || !_settings.mcpEnabled) {
      return false;
    }
    final allTools = mcpToolService.getOpenAiToolDefinitions();
    if (allTools.isEmpty) {
      return false;
    }
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
    if (!_isCurrentInteractionGeneration(generation)) {
      return true;
    }
    if (!ref.mounted || recoveryResult == null) {
      return false;
    }
    _recordHiddenAssistantResponse(candidateResponse);
    if (!recoveryResult.hasToolCalls) {
      _recordHiddenAssistantResponse(recoveryResult.content);
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

  bool _hasTerminalGoalSuccessToolResults(List<ToolResultInfo> toolResults) {
    if (toolResults.isEmpty) {
      return false;
    }
    return _toolResultsContainSuccessfulCurrentSavedValidation(toolResults) ||
        _toolResultsSatisfyCurrentGoalGitLifecycle(toolResults);
  }

  bool _shouldSkipCompletedToolResultFinalAnswerRecovery({
    required int generation,
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    final candidate = candidateResponse.trim();
    final streamedFinalAnswer =
        _lastStreamedToolResultFinalAnswersByGeneration[generation]?.trim();
    if (streamedFinalAnswer != null &&
        streamedFinalAnswer.isNotEmpty &&
        candidate != streamedFinalAnswer) {
      return false;
    }
    return _shouldSkipCompletedToolResultCodingContinuationRecovery(
      candidateResponse: candidate,
      toolResults: toolResults,
    );
  }

  bool _shouldSkipCompletedToolResultCodingContinuationRecovery({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    final candidate = candidateResponse.trim();
    if (candidate.isEmpty) {
      return false;
    }
    if (_hasTimedOutCommandResult(toolResults) ||
        _toolResultsContainFailedCommandValidation(toolResults) ||
        _hasUnexecutedCommandActionResult(toolResults) ||
        _hasUnexecutedFileSideEffectResult(toolResults)) {
      return false;
    }
    if (!_hasSuccessfulFinalAnswerToolEvidence(toolResults)) {
      return false;
    }
    return _looksLikeCompletedCodingFinalAnswer(candidate) &&
        !_looksLikeCodingFutureAction(candidate);
  }

  bool _hasSuccessfulFinalAnswerToolEvidence(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
          return _isFileMutationToolName(toolResult.name) &&
              _isSuccessfulFileMutationToolResult(toolResult);
        }) ||
        _hasSuccessfulCommandExecutionResult(toolResults);
  }

  bool _looksLikeCompletedCodingFinalAnswer(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty || normalized.length > 1600) {
      return false;
    }
    final hasTarget =
        _containsAny(normalized, const [
          'code',
          'source',
          'file',
          'project',
          'dart',
          'python',
          'script',
          'logic',
          'entrypoint',
          'implementation',
          'pubspec',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x30b3, 0x30fc, 0x30c9],
          [0x30bd, 0x30fc, 0x30b9],
          [0x30d5, 0x30a1, 0x30a4, 0x30eb],
          [0x30d7, 0x30ed, 0x30b8, 0x30a7, 0x30af, 0x30c8],
          [0x30b9, 0x30af, 0x30ea, 0x30d7, 0x30c8],
          [0x30ed, 0x30b8, 0x30c3, 0x30af],
          [0x65e2, 0x5b58],
        ]);
    if (!hasTarget) {
      return false;
    }
    return _containsAny(normalized, const [
          'completed',
          'complete',
          'created',
          'implemented',
          'updated',
          'modified',
          'wrote',
          'written',
          'saved',
          'verified',
          'confirmed',
          'checked',
          'tested',
          'ran',
          'executed',
          'successfully',
          'passed',
          'passes',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x3057, 0x307e, 0x3057, 0x305f],
          [0x5b8c, 0x4e86],
          [0x6210, 0x529f],
          [0x6e08, 0x307f],
        ]);
  }

  bool _looksLikeCodingFutureAction(String content) {
    final normalized = content.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return _containsAny(normalized, const [
          'i will inspect',
          'i will check',
          'i will read',
          'i will port',
          'i will implement',
          'i will update',
          'i will edit',
          'i will modify',
          'i will write',
          'i will create',
          "i'll inspect",
          "i'll check",
          "i'll read",
          "i'll port",
          "i'll implement",
          "i'll update",
          "i'll edit",
          "i'll modify",
          "i'll write",
          "i'll create",
          'i am going to inspect',
          'i am going to check',
          'i am going to read',
          'i am going to port',
          'i am going to implement',
          'i am going to update',
          'i am going to edit',
          'i am going to modify',
          'i am going to write',
          'i am going to create',
          'next i will',
          'now i will',
        ]) ||
        _containsAnyCodeUnitSequence(content, const [
          [0x78ba, 0x8a8d, 0x3057, 0x307e, 0x3059],
          [0x8abf, 0x67fb, 0x3057, 0x307e, 0x3059],
          [0x8aad, 0x307f, 0x307e, 0x3059],
          [
            0x30dd,
            0x30fc,
            0x30c6,
            0x30a3,
            0x30f3,
            0x30b0,
            0x3057,
            0x307e,
            0x3059,
          ],
          [0x79fb, 0x690d, 0x3057, 0x307e, 0x3059],
          [0x5b9f, 0x88c5, 0x3057, 0x307e, 0x3059],
          [0x66f4, 0x65b0, 0x3057, 0x307e, 0x3059],
          [0x7de8, 0x96c6, 0x3057, 0x307e, 0x3059],
          [0x4f5c, 0x6210, 0x3057, 0x307e, 0x3059],
          [0x66f8, 0x304d, 0x307e, 0x3059],
        ]);
  }

  String _turnFinalizationCandidateText(
    String content, {
    required int generation,
  }) {
    final streamedFinalAnswer =
        _lastStreamedToolResultFinalAnswersByGeneration[generation]?.trim();
    if (streamedFinalAnswer != null && streamedFinalAnswer.isNotEmpty) {
      return streamedFinalAnswer;
    }
    return ContentParser.stripToolArtifacts(content).trim();
  }

  String _contentBeforeFinalizationCandidate({
    required String currentContent,
    required String candidateResponse,
  }) {
    final candidate = candidateResponse.trim();
    if (candidate.isEmpty) {
      return currentContent.trimRight();
    }
    final index = currentContent.lastIndexOf(candidate);
    if (index < 0) {
      return '';
    }
    return currentContent.substring(0, index).trimRight();
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
