// Same-library extension on [ChatNotifier] for streamed tool-result final
// answers and their bounded recovery paths.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierFinalAnswerRecovery on ChatNotifier {
  Future<String> _streamToolResultAnswerWithContextRetry({
    required List<ToolResultInfo> toolResults,
    required int interactionGeneration,
    ToolResultCompletionEvidence? completionEvidence,
    bool deferIncompleteLengthRecovery = false,
  }) async {
    Future<ChatCompletionResult?> requestConciseRecovery({
      required FinalAnswerRecoveryReason reason,
      required bool forceCompaction,
    }) async {
      final retryMessages = _prepareMessagesForLLM(
        forceCompaction: forceCompaction,
        toolDefinitionsOverride: const <Map<String, dynamic>>[],
        interactionGeneration: interactionGeneration,
      );
      retryMessages.addAll(
        _buildToolResultAnswerMessages(
          toolResults,
          budgetMode: ToolResultPromptBudgetMode.compact,
          completionEvidence: completionEvidence,
        ),
      );
      retryMessages.add(
        Message(
          id: 'final_answer_recovery',
          content: _finalAnswerRecoveryPolicy.buildRetryPrompt(reason),
          role: MessageRole.user,
          timestamp: DateTime.now(),
        ),
      );
      final configuredMaxTokens = _settings.maxTokens;
      final retryMaxTokens =
          configuredMaxTokens > 0 &&
              configuredMaxTokens < FinalAnswerRecoveryPolicy.maxRetryTokens
          ? configuredMaxTokens
          : FinalAnswerRecoveryPolicy.maxRetryTokens;
      appLog(
        '[FinalAnswerRecovery] Retrying the tool-result final answer once; '
        'reason=${reason.logToken}, maxTokens=$retryMaxTokens',
      );
      try {
        return await _dataSource.createChatCompletion(
          messages: retryMessages,
          tools: const <Map<String, dynamic>>[],
          model: _settings.model,
          temperature: FinalAnswerRecoveryPolicy.retryTemperature,
          maxTokens: retryMaxTokens,
        );
      } catch (error) {
        appLog(
          '[FinalAnswerRecovery] Concise retry failed; retaining the first '
          'answer (${error.runtimeType}: $error)',
        );
        return null;
      }
    }

    Future<String> streamAnswer({
      required bool forceCompaction,
      required ToolResultPromptBudgetMode budgetMode,
    }) async {
      return _runWithLlmSessionLogContextForGeneration(
        interactionGeneration,
        () async {
          final streamedAnswer = StringBuffer();
          final messagesForLLM = _prepareMessagesForLLM(
            forceCompaction: forceCompaction,
            toolDefinitionsOverride: const <Map<String, dynamic>>[],
            interactionGeneration: interactionGeneration,
          );
          messagesForLLM.addAll(
            _buildToolResultAnswerMessages(
              toolResults,
              budgetMode: budgetMode,
              completionEvidence: completionEvidence,
            ),
          );

          final preAnswerContent =
              _lastMessageContentForGeneration(interactionGeneration) ?? '';
          _appendToLastMessageForGeneration(interactionGeneration, '<think>');

          final dataSource = _dataSource;
          final stream = dataSource is SessionLoggingChatDataSource
              ? dataSource.streamChatCompletionWithStructuredToolResults(
                  messages: messagesForLLM,
                  toolResults: toolResults,
                  model: _settings.model,
                  temperature: _assistantRequestTemperature,
                  maxTokens: _settings.maxTokens,
                )
              : dataSource.streamChatCompletion(
                  messages: messagesForLLM,
                  model: _settings.model,
                  temperature: _assistantRequestTemperature,
                  maxTokens: _settings.maxTokens,
                );

          var isFirstChunk = true;
          try {
            await for (final chunk in stream.timeout(
              const Duration(minutes: 2),
            )) {
              if (!_isCurrentInteractionGeneration(interactionGeneration)) {
                return '';
              }
              if (!ref.mounted) return '';
              if (isFirstChunk) {
                isFirstChunk = false;
                _removeTrailingThinkTagForGeneration(interactionGeneration);
                final activeMessages =
                    _activeResponseMessagesForGeneration(
                      interactionGeneration,
                    ) ??
                    state.messages;
                if (activeMessages.isNotEmpty &&
                    activeMessages.last.content.isNotEmpty) {
                  _appendToLastMessageForGeneration(
                    interactionGeneration,
                    '\n',
                    scanForTools: false,
                  );
                }
              }
              _appendToLastMessageForGeneration(
                interactionGeneration,
                chunk,
                scanForTools: false,
              );
              streamedAnswer.write(chunk);
            }
          } on TimeoutException {
            _removeTrailingThinkTagForGeneration(interactionGeneration);
            const timeoutResponse =
                'The final response timed out. The task remains incomplete; '
                'continue from the latest diagnostics.';
            _appendRecoveredAssistantResponse(
              timeoutResponse,
              interactionGeneration: interactionGeneration,
            );
            appLog(
              '[FinalAnswerRecovery] Tool-result final stream timed out; '
              'returning incomplete evidence to goal continuation',
            );
            return timeoutResponse;
          }
          if (isFirstChunk) {
            _removeTrailingThinkTagForGeneration(interactionGeneration);
          }
          var rawStreamedAnswer = streamedAnswer.toString();
          final firstFinishReason = _latestFinishReason();
          final recoveryReason = _finalAnswerRecoveryPolicy.recoveryReason(
            content: ContentParser.stripToolArtifacts(rawStreamedAnswer),
            finishReason: firstFinishReason,
          );
          final deferToPendingActionRecovery =
              deferIncompleteLengthRecovery &&
              recoveryReason == FinalAnswerRecoveryReason.lengthTruncated;
          if (deferToPendingActionRecovery) {
            _finalAnswerFinishReasonOverride = firstFinishReason;
            appLog(
              '[PendingActionLengthRecovery] Deferring truncated incomplete '
              'coding work to a tool-aware retry',
            );
          } else if (recoveryReason != null) {
            final retryResult = await requestConciseRecovery(
              reason: recoveryReason,
              forceCompaction: forceCompaction,
            );
            if (!_isCurrentInteractionGeneration(interactionGeneration) ||
                !ref.mounted) {
              return '';
            }
            final rawRetryContent = retryResult?.content.trim() ?? '';
            final visibleRetryContent = ContentParser.stripToolArtifacts(
              rawRetryContent,
            ).trim();
            if (retryResult != null && visibleRetryContent.isNotEmpty) {
              _removeStreamedAnswerSuffixForGeneration(
                interactionGeneration,
                preAnswerContent: preAnswerContent,
              );
              final separator =
                  preAnswerContent.isEmpty || preAnswerContent.endsWith('\n')
                  ? ''
                  : '\n\n';
              _replaceLastMessageContentForGeneration(
                interactionGeneration,
                '$preAnswerContent$separator$visibleRetryContent',
              );
              rawStreamedAnswer = rawRetryContent;
              final retryFinishReason = retryResult.finishReason.trim();
              _finalAnswerFinishReasonOverride = retryFinishReason.isEmpty
                  ? null
                  : retryFinishReason;
              _appliedTurnTransforms.add('final_answer_concise_retry');
              appLog(
                '[FinalAnswerRecovery] Applied concise final-answer retry; '
                'reason=${recoveryReason.logToken}',
              );
            } else {
              _finalAnswerFinishReasonOverride = firstFinishReason;
            }
          }
          _stripToolArtifactsFromStreamedAnswerSuffix(
            interactionGeneration,
            preAnswerContent: preAnswerContent,
          );
          _appendUnexecutedToolRequestNoticeForContentIfNeeded(
            interactionGeneration: interactionGeneration,
            content: rawStreamedAnswer,
            toolResults: toolResults,
          );
          _replaceTimedOutCommandSuccessClaimIfNeeded(
            toolResults: toolResults,
            interactionGeneration: interactionGeneration,
          );
          _replaceFailedCommandSuccessClaimIfNeeded(
            toolResults: toolResults,
            interactionGeneration: interactionGeneration,
          );
          _appendUnexecutedFileSideEffectNoticeIfNeeded(
            toolResults: toolResults,
            interactionGeneration: interactionGeneration,
          );
          final strippedStreamedAnswer = ContentParser.stripToolArtifacts(
            rawStreamedAnswer,
          ).trim();
          if (strippedStreamedAnswer.isNotEmpty) {
            _lastStreamedToolResultFinalAnswersByGeneration[interactionGeneration] =
                strippedStreamedAnswer;
          } else {
            _lastStreamedToolResultFinalAnswersByGeneration.remove(
              interactionGeneration,
            );
          }
          return strippedStreamedAnswer;
        },
      );
    }

    try {
      return await streamAnswer(
        forceCompaction: false,
        budgetMode: ToolResultPromptBudgetMode.normal,
      );
    } catch (error) {
      final hasCompactableHistory = _hasCompactablePromptHistory();
      final hasToolResultBudget = _hasAdditionalCompactToolResultBudget(
        toolResults,
      );
      if (!ConversationCompactionService.isContextLengthError(
            error.toString(),
          ) ||
          (!hasCompactableHistory && !hasToolResultBudget)) {
        rethrow;
      }
      appLog(
        '[Compaction] Retrying final tool-result answer after context-length '
        'error with ${hasCompactableHistory ? 'forced prompt compaction' : 'unchanged prompt history'} '
        'and compact tool results',
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return '';
      _removeTrailingThinkTagForGeneration(interactionGeneration);
      return streamAnswer(
        forceCompaction: hasCompactableHistory,
        budgetMode: ToolResultPromptBudgetMode.compact,
      );
    }
  }
}
