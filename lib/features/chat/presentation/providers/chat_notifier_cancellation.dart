part of 'chat_notifier.dart';

extension ChatNotifierCancellation on ChatNotifier {
  void _cancelStreaming() {
    final cancelledGeneration = _interactionGeneration;
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _dismissAllPendingAskUserQuestions();
    _isSchedulingGoalAutoContinue = false;
    _persistHiddenPromptAssistantResponse = false;

    // Advance the interaction generation so the in-flight recursive
    // tool-calling loop's generation guards (_isCurrentInteractionGeneration)
    // start failing and it stops issuing further completions/tool calls.
    // Previously this method left _interactionGeneration untouched, so the
    // loop's captured generation stayed current and the stop was ignored — the
    // loop kept running (and the session log kept growing) in the background
    // even though the streaming output had been detached from the UI.
    _beginInteractionGeneration();

    // Drop any queued loop continuation so nothing re-enters the loop after the
    // generation bump. A new turn resets these as well, but clearing them now
    // prevents an already-scheduled continuation from acting before then.
    _pendingContentToolResults.clear();
    _pendingContentToolContinuationFallback = null;
    _pendingToolExecutions.clear();
    _contentToolContinuationCount = 0;
    _latestGoalAutoContinueEvidence = const ToolResultCompletionEvidence();
    _clearAllActiveResponses();

    // The generation has advanced, so _finishStreaming would early-return on its
    // own guard. Finalize the partial assistant bubble inline instead: keep
    // whatever was streamed, drop an empty placeholder, clear the loading
    // state, and persist what remains.
    if (!_isCancellationMounted) {
      _failRuntimeTurn(
        cancelledGeneration,
        code: 'cancelled',
        message: 'Execution was cancelled by the user.',
        exitCode: 130,
      );
      return;
    }
    if (_cancellationState.messages.isEmpty) {
      _clearGoalAutoContinueIndicator();
      _failRuntimeTurn(
        cancelledGeneration,
        code: 'cancelled',
        message: 'Execution was cancelled by the user.',
        exitCode: 130,
      );
      return;
    }
    final updatedMessages = [..._cancellationState.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    var changedMessages = false;
    if (lastMessage.role == MessageRole.assistant &&
        !_assistantMessageHasVisibleContent(lastMessage.content)) {
      updatedMessages.removeAt(lastIndex);
      changedMessages = true;
    } else if (lastMessage.isStreaming) {
      updatedMessages[lastIndex] = lastMessage.copyWith(isStreaming: false);
      changedMessages = true;
    }
    if (changedMessages) {
      _setCancellationState(
        _cancellationState.copyWith(
          messages: updatedMessages,
          isLoading: false,
          participantTurnRuntime: null,
        ),
      );
      final save = _cancelledMessagePersistenceTail.then(
        (_) => _saveMessages(updateSessionMemory: false),
      );
      _cancelledMessagePersistenceTail = save.catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        appLog(
          '[ChatNotifier] Cancelled message persistence failed: '
          '${error.runtimeType}: $error',
        );
        appLog('[ChatNotifier] stackTrace: $stackTrace');
      });
      unawaited(_cancelledMessagePersistenceTail);
    } else if (_cancellationState.isLoading) {
      _setCancellationState(
        _cancellationState.copyWith(
          isLoading: false,
          participantTurnRuntime: null,
        ),
      );
    }
    _clearGoalAutoContinueIndicator();
    _failRuntimeTurn(
      cancelledGeneration,
      code: 'cancelled',
      message: 'Execution was cancelled by the user.',
      exitCode: 130,
    );
  }
}
