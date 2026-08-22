// Same-library extension for streamed tool-result answers and recovery.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierFinalAnswerRecovery on ChatNotifier {
  Future<String> _streamToolResultAnswerWithContextRetry({
    required List<ToolResultInfo> toolResults,
    required int interactionGeneration,
    ToolResultCompletionEvidence? completionEvidence,
    bool deferIncompleteLengthRecovery = false,
  }) async {
    final turnOwner = _turnOwnerForGeneration(interactionGeneration);
    if (turnOwner == null) return '';
    final protectedPaths = const ContextSurgeryProtectedPathPolicy()
        .protectedPathsFor(_conversationForGeneration(interactionGeneration));
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
          protectedPaths: protectedPaths,
          observationOwner: turnOwner,
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
        return await _primaryDataSourceForGeneration(
          interactionGeneration,
        ).createChatCompletion(
          messages: retryMessages,
          tools: const <Map<String, dynamic>>[],
          model: _primaryModelForGeneration(interactionGeneration),
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
              protectedPaths: protectedPaths,
              observationOwner: turnOwner,
            ),
          );
          final preAnswerContent =
              _lastMessageContentForGeneration(interactionGeneration) ?? '';
          _appendToLastMessageForGeneration(interactionGeneration, '<think>');

          final dataSource = _primaryDataSourceForGeneration(
            interactionGeneration,
          );
          final stream = dataSource is SessionLoggingChatDataSource
              ? dataSource.streamChatCompletionWithStructuredToolResults(
                  messages: messagesForLLM,
                  toolResults: toolResults,
                  model: _primaryModelForGeneration(interactionGeneration),
                  temperature: _primaryAssistantTemperatureForGeneration(
                    interactionGeneration,
                  ),
                  maxTokens: _settings.maxTokens,
                )
              : dataSource.streamChatCompletion(
                  messages: messagesForLLM,
                  model: _primaryModelForGeneration(interactionGeneration),
                  temperature: _primaryAssistantTemperatureForGeneration(
                    interactionGeneration,
                  ),
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
            _responseMetadata.discard(turnOwner);
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
          final firstMetadata = await stream.terminal;
          if (!_activeResponseRegistry.containsOwner(turnOwner) ||
              !_responseMetadata.capture(turnOwner, firstMetadata)) {
            return '';
          }
          var rawStreamedAnswer = streamedAnswer.toString();
          final firstFinishReason = firstMetadata.finishReason;
          final recoveryReason = _finalAnswerRecoveryPolicy.recoveryReason(
            content: ContentParser.stripToolArtifacts(rawStreamedAnswer),
            finishReason: firstFinishReason,
          );
          final deferToPendingActionRecovery =
              deferIncompleteLengthRecovery &&
              recoveryReason == FinalAnswerRecoveryReason.lengthTruncated;
          if (deferToPendingActionRecovery) {
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
            final visibleRetryContent =
                ContentParser.stripToolArtifactsPreservingThinking(
                  rawRetryContent,
                ).trim();
            // A retry earns the replacement only by answering. Emptiness was
            // measured with thinking included, so a reply that was nothing but
            // an unterminated <think> block counted as content and replaced the
            // answer with no prose at all; and the retry's own finish reason
            // went unread, so one truncated at the retry budget was applied as
            // the fix for truncation. Session a0ca65b7 gen-14 hit both at once
            // and ended with no visible answer after twelve minutes.
            final retryAnswerText = ContentParser.stripModelHistoryArtifacts(
              rawRetryContent,
            ).trim();
            final retryRecoveryReason = retryResult == null
                ? null
                : _finalAnswerRecoveryPolicy.recoveryReason(
                    content: ContentParser.stripToolArtifacts(rawRetryContent),
                    finishReason: retryResult.finishReason,
                  );
            final retryIsUsable =
                retryResult != null &&
                visibleRetryContent.isNotEmpty &&
                retryAnswerText.isNotEmpty &&
                retryRecoveryReason == null;
            if (retryResult != null && !retryIsUsable) {
              appLog(
                '[FinalAnswerRecovery] Discarded concise final-answer retry; '
                'reason=${recoveryReason.logToken}, '
                'retryFailure=${retryRecoveryReason?.logToken ?? (retryAnswerText.isEmpty ? 'no_answer_text' : 'empty')}',
              );
              _turnEnd.addTransform(
                turnOwner,
                'final_answer_concise_retry_discarded',
              );
            }
            if (retryIsUsable) {
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
              _responseMetadata.captureResult(turnOwner, retryResult);
              _turnEnd.addTransform(turnOwner, 'final_answer_concise_retry');
              appLog(
                '[FinalAnswerRecovery] Applied concise final-answer retry; '
                'reason=${recoveryReason.logToken}',
              );
            }
          }
          _stripToolArtifactsFromStreamedAnswerSuffix(
            interactionGeneration,
            preAnswerContent: preAnswerContent,
          );
          _appendUnexecutedToolRequestNoticeForContentIfNeeded(
            owner: turnOwner,
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
          // Text only. stripToolArtifacts keeps thinking segments and drops
          // just tool tags, leaving reasoning with nothing to mark it: session
          // e40965bc handed that to the unexecuted-command guard, which read a
          // product release out of the model's deliberation as a command run.
          // Every consumer here asks what the assistant asserted.
          final strippedStreamedAnswer =
              ContentParser.stripModelHistoryArtifacts(
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
      final retryOwner = _turnOwnerForGeneration(interactionGeneration);
      final hasCompactableHistory =
          retryOwner != null && _hasCompactablePromptHistory(retryOwner);
      final hasToolResultBudget = _hasAdditionalCompactToolResultBudget(
        toolResults,
        protectedPaths: protectedPaths,
        interactionGeneration: interactionGeneration,
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
