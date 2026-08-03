part of 'chat_notifier.dart';

extension ChatNotifierCancellation on ChatNotifier {
  void _cancelStreaming() {
    final cancelledGeneration =
        _activeResponseGenerationForConversation(conversationId) ??
        _interactionGeneration;
    final cancelledOwner = _turnOwnerForGeneration(cancelledGeneration);
    _streamSubscription?.cancel();
    _streamSubscription = null;
    if (cancelledOwner != null) {
      _dismissPendingAskUserQuestionForConversation(
        cancelledOwner.conversationId,
      );
    }
    _turnRuntimeComposition.clearGoalContinuationScheduling();

    // Advance the global generation so recursive loops stop. The visible owner
    // is captured above because a restored participant turn can be older than
    // the latest completed generation.
    _beginInteractionGeneration();

    // The generation has advanced, so _finishStreaming would early-return on its
    // own guard. Finalize the partial assistant bubble inline instead: keep
    // whatever was streamed, drop an empty placeholder, clear the loading
    // state, and persist what remains.
    if (_isCancellationMounted && _cancellationState.messages.isNotEmpty) {
      final updatedMessages = [..._cancellationState.messages];
      final lastIndex = updatedMessages.length - 1;
      final lastMessage = updatedMessages[lastIndex];
      var changedMessages = false;
      if (lastMessage.role == MessageRole.assistant &&
          !TurnFinalMessage.hasVisibleContent(lastMessage.content)) {
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
        final targetConversationId =
            cancelledOwner?.conversationId ?? conversationId;
        if (targetConversationId != null) {
          unawaited(
            _messagePersistence.enqueueCancelledTurn(
              conversationId: targetConversationId,
              messages: updatedMessages,
            ),
          );
        }
      } else if (_cancellationState.isLoading) {
        _setCancellationState(
          _cancellationState.copyWith(
            isLoading: false,
            participantTurnRuntime: null,
          ),
        );
      }
    }
    _failRuntimeTurn(
      cancelledGeneration,
      code: 'cancelled',
      message: 'Execution was cancelled by the user.',
      exitCode: 130,
    );
    if (_isCancellationMounted) _clearGoalAutoContinueIndicator();
  }
}
