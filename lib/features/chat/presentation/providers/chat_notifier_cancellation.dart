part of 'chat_notifier.dart';

/// The two ways the user acts on a turn that is already running: end it, or
/// join it.
///
/// They live together because they are the same decision seen from opposite
/// sides, and the one line that separates them is easy to lose if they drift
/// apart: cancellation advances the interaction generation, steering must not.

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
    _goalContinuationLifecycle.clear();

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

/// Mid-turn interruption: a message typed while a turn is running joins that
/// turn instead of waiting behind it.
///
/// The difference from [_cancelStreaming] is one line that is not here: the
/// interaction generation never advances. The turn keeps its owner, its tool
/// results and its partial output, and the interrupting message is picked up
/// by the next request the turn builds. Nothing has to cut a stream mid-token,
/// so none of the partial-response recovery paths fire.
///
/// A turn that never builds another request cannot carry the message, so a
/// steer is only ever *claimed* when a request commits it. Whatever is left
/// unclaimed when the turn ends goes back to [ThreadScopedMessageQueue], which
/// is where a message typed against a busy thread went before steering
/// existed. That fallback is what makes it safe to try steering first.
///
/// The rules live in [TurnSteeringPolicy]; what remains here is the plumbing
/// that applies them to the turn's registries and state.
extension ChatNotifierSteering on ChatNotifier {
  /// The turn a message typed in [targetConversationId] would join, if any.
  ChatTurnOwner? _steerableTurnOwner(String? targetConversationId) {
    if (targetConversationId == null || targetConversationId.isEmpty) {
      return null;
    }
    final generation = _activeResponseGenerationForConversation(
      targetConversationId,
    );
    if (generation == null) return null;
    final owner = _turnOwnerForGeneration(generation);
    if (owner == null || owner.conversationId != targetConversationId) {
      return null;
    }
    if (!_activeResponseRegistry.containsOwner(owner)) return null;
    // A participant turn passes the floor between personas on a schedule of
    // its own, and a paused one is waiting for the user to resume it. Steering
    // either races that handover, so those keep queueing.
    if (_participantTurnControls.contains(owner)) return null;
    return owner;
  }

  bool _isSteerableMessage(QueuedChatMessage message) =>
      TurnSteeringPolicy.canSteer(
        content: message.content,
        hasImage: message.hasImage,
        isVoiceMode: message.isVoiceMode,
      );

  /// Files [message] against the running [owner] and reports the turn it
  /// joined.
  ChatTurnOwner _registerTurnSteering(
    ChatTurnOwner owner,
    QueuedChatMessage message,
  ) {
    _turnSteering.add(
      owner,
      TurnSteeringEntry(message: message, receivedAt: DateTime.now()),
    );
    _syncTurnSteeringState();
    appLog(
      '[Steering] Interruption filed against generation '
      '${owner.interactionGeneration} '
      '(${_turnSteering.pendingCount(owner)} waiting for the next request)',
    );
    return owner;
  }

  /// Moves interruptions that arrived since the last request into the turn's
  /// history, so the request now being built carries them as ordinary user
  /// turns.
  ///
  /// Called at the top of [_prepareMessagesForLLM], before the owner snapshot
  /// is read, because committing is what puts the message where that read will
  /// find it. Retries rebuild from a history that already contains the
  /// message, so they carry it without claiming anything twice.
  void _commitPendingTurnSteering(int interactionGeneration) {
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null || _turnSteering.pendingCount(owner) == 0) return;
    final ownerMessages = _activeResponseRegistry.messagesForOwner(owner);
    if (ownerMessages == null) return;
    final claimed = _turnSteering.claimPending(owner);
    if (claimed.isEmpty) return;

    final updatedMessages = [...ownerMessages];
    updatedMessages.insertAll(TurnSteeringPolicy.insertIndex(updatedMessages), [
      for (final entry in claimed)
        TurnSteeringPolicy.steeringMessage(
          id: entry.id,
          content: entry.content,
          receivedAt: entry.receivedAt,
        ),
    ]);

    _activeResponseRegistry.cacheMessagesForOwner(owner, updatedMessages);
    if (_isCancellationMounted && conversationId == owner.conversationId) {
      _setCancellationState(
        _cancellationState.copyWith(messages: updatedMessages),
      );
    }
    _syncTurnSteeringState();
    appLog(
      '[Steering] Committed ${claimed.length} interruption(s) into generation '
      '${owner.interactionGeneration}',
    );
  }

  /// The directive that tells the model those user turns are an interruption.
  ///
  /// Derived from the carried count rather than consumed, so it stays in place
  /// for the rest of the turn instead of only for the request that first
  /// carried the message.
  Message? _turnSteeringDirectiveMessage(ChatTurnOwner owner) {
    final carried = _turnSteering.carriedCount(owner);
    if (carried == 0) return null;
    return Message(
      id: 'system_turn_steering_${owner.interactionGeneration}',
      content: TurnSteeringPromptBuilder.directive(steerCount: carried),
      role: MessageRole.system,
      timestamp: DateTime.now(),
    );
  }

  /// Retires [owner] and hands back whatever never reached the model.
  ///
  /// Registered as a turn release, so it runs on every way out of a turn --
  /// completion, failure and cancellation alike -- ahead of the queue drain
  /// that follows finalization.
  void _returnUncarriedTurnSteering(ChatTurnOwner owner) {
    final uncarried = _turnSteering.dispose(owner);
    if (uncarried.isEmpty) {
      _syncTurnSteeringState();
      return;
    }
    // Reversed because each restore goes to the head of the thread's queue;
    // walking backwards leaves them in the order they were typed.
    for (final entry in uncarried.reversed) {
      unawaited(
        _queuedChatMessages.restoreFirstForThread(
          entry.message,
          owner.conversationId,
        ),
      );
    }
    _syncQueuedChatMessagesState();
    _syncTurnSteeringState();
    appLog(
      '[Steering] Turn ${owner.interactionGeneration} ended before carrying '
      '${uncarried.length} interruption(s); returned them to the queue',
    );
  }

  /// Withdraws a pending interruption the user removed from the strip.
  ///
  /// Only pending ones: once a request carried it, it is a user turn in the
  /// transcript and the model has seen it, so there is nothing to take back.
  bool _removePendingTurnSteering(String id) {
    if (_turnSteering.removePendingAnywhere(id) == null) return false;
    _syncTurnSteeringState();
    appLog('[Steering] Withdrew an interruption before any request carried it');
    return true;
  }

  void _syncTurnSteeringState() {
    if (!_isCancellationMounted) return;
    final visibleThread = conversationId;
    final pending = visibleThread == null
        ? const <TurnSteeringEntry>[]
        : _turnSteering.pendingForConversation(visibleThread);
    final messages = [for (final entry in pending) entry.message];
    if (listEquals(_cancellationState.steeringMessages, messages)) return;
    _setCancellationState(
      _cancellationState.copyWith(steeringMessages: messages),
    );
  }
}
