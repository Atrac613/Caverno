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
    _turnStream.cancelAll();
    if (cancelledOwner != null) {
      _dismissPendingAskUserQuestionForConversation(
        cancelledOwner.conversationId,
      );
    }
    _goalContinuationLifecycle.clear();
    // Stop has to stop the thread, not only the turn: a queued message's turn
    // holds its thread's drain until it returns, so one waiting on a tool the
    // user just cancelled leaves the next message invisible in the queue.
    // Ordering is not what keeps a cancelled turn from landing; the owner is.
    final cancelledThread = cancelledOwner?.conversationId ?? conversationId;
    if (cancelledThread != null) _queuedChatMessages.endDrain(cancelledThread);

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
      message.modelContent == null &&
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
    // A turn that is streaming has no further request planned, so waiting for
    // one means waiting forever. Measured: users interrupt while reading the
    // answer, which is after every between-request window has closed.
    //
    // It has to be *this* turn's stream: a turn running a tool still has a
    // request coming, and another thread's stream is not this turn's to end.
    if (_turnStream.isStreaming(owner)) {
      unawaited(_restartTurnForSteering(owner));
    }
    return owner;
  }

  /// Abandons the stream this turn is consuming so it can take the
  /// interruption, without ending the turn.
  ///
  /// The generation still does not advance. What changes is that the turn stops
  /// waiting for a request boundary that is not coming and makes one, keeping
  /// its owner, tool results and everything already streamed.
  ///
  /// Cancelling the subscription means `onDone` never fires, so the
  /// finalization it would have triggered has to move here with it -- the
  /// re-issued stream below owns it instead. Dropping that is how a thread ends
  /// up stranded under a spinner.
  Future<void> _restartTurnForSteering(ChatTurnOwner owner) async {
    final subscription = _turnStream.subscriptionFor(owner);
    if (subscription == null) return;
    if (!_claimSteeringRestart(owner)) return;

    // Not awaited: cancellation stops delivery to this listener immediately,
    // while the future it returns settles with the upstream teardown and can
    // outlive the request. Awaiting it strands the restart behind the very
    // stream it is abandoning.
    _turnStream.release(owner);
    unawaited(subscription.cancel());
    await _reissueTurnForSteering(owner);
  }

  /// Whether the tool-aware loop should leave the stream it is reading.
  ///
  /// That loop consumes its stream with `await for` and holds no subscription,
  /// so it cannot be interrupted from outside: it has to check and break. This
  /// is the path a turn takes when the model answers without calling a tool,
  /// which is the ordinary chat reply and therefore the one users interrupt.
  bool _steeringRestartWanted(ChatTurnOwner owner) =>
      _turnSteering.pendingCount(owner) > 0 &&
      _turnSteering.restartCount(owner) <
          TurnSteeringPolicy.restartBudgetPerTurn &&
      _activeResponseRegistry.containsOwner(owner) &&
      _isCurrentInteractionGeneration(owner.interactionGeneration);

  /// The tool-aware loop's entry point, called after it has already broken out
  /// of its `await for` -- which cancels the underlying stream on its own.
  Future<void> _restartTurnForSteeringFromToolLoop(ChatTurnOwner owner) async {
    if (!_claimSteeringRestart(owner)) return;
    await _reissueTurnForSteering(owner);
  }

  bool _claimSteeringRestart(ChatTurnOwner owner) {
    if (!_activeResponseRegistry.containsOwner(owner)) return false;
    if (!_isCurrentInteractionGeneration(owner.interactionGeneration)) {
      return false;
    }
    if (_turnSteering.tryClaimRestart(
      owner,
      budget: TurnSteeringPolicy.restartBudgetPerTurn,
    )) {
      return true;
    }
    appLog(
      '[Steering] Restart budget spent for generation '
      '${owner.interactionGeneration}; the interruption waits for the queue',
    );
    return false;
  }

  Future<void> _reissueTurnForSteering(ChatTurnOwner owner) async {
    final ownerMessages = _activeResponseRegistry.messagesForOwner(owner);
    if (ownerMessages == null || ownerMessages.isEmpty) return;

    // Keep what was streamed and stop it streaming, so the transcript shows how
    // far the reply got before the user cut in. An empty placeholder is dropped
    // instead, exactly as cancellation treats one.
    final finalizedMessages = [...ownerMessages];
    final lastIndex = finalizedMessages.length - 1;
    final lastMessage = finalizedMessages[lastIndex];
    if (lastMessage.role == MessageRole.assistant &&
        !TurnFinalMessage.hasVisibleContent(lastMessage.content)) {
      finalizedMessages.removeAt(lastIndex);
    } else if (lastMessage.isStreaming) {
      finalizedMessages[lastIndex] = lastMessage.copyWith(isStreaming: false);
    }

    final restartedMessage = Message(
      id: _uuid.v4(),
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isStreaming: true,
    );
    final restartedMessages = [...finalizedMessages, restartedMessage];
    _activeResponseRegistry.cacheMessagesForOwner(owner, restartedMessages);
    if (_isCancellationMounted && conversationId == owner.conversationId) {
      _setCancellationState(
        _cancellationState.copyWith(
          messages: restartedMessages,
          isLoading: true,
          error: null,
        ),
      );
    }

    appLog(
      '[Steering] Restarted generation ${owner.interactionGeneration} '
      'mid-stream to take the interruption '
      '(restart ${_turnSteering.restartCount(owner)} of '
      '${TurnSteeringPolicy.restartBudgetPerTurn})',
    );

    // Re-enter the turn's own path rather than issuing a bare stream, so the
    // restarted request keeps the tools the turn had. Issuing it directly cost
    // a measured turn its LAN scan: the interruption arrived tool-aware and
    // came back tool-free, and the model wrote a script about scanning instead
    // of scanning.
    //
    // The tool-free path has to be entered deliberately to keep that argument
    // symmetric: `_sendWithTools` reads the catalog the service holds, which is
    // populated whether or not tools are switched on, so a turn the user ran
    // with tools off would come back with the whole catalog attached. An
    // interruption is not consent to a setting they turned off.
    //
    // Safe to re-enter on the same generation. The file-turn checkpoint is
    // keyed by generation, so beginning it again returns without touching the
    // open one. `_prepareMessagesForLLM` commits the pending steer on the way
    // through, and the partial answer above is already finalized, so the
    // interruption lands after it.
    if (_turnDeniedTools(owner)) {
      await _sendWithoutTools(
        interactionGeneration: owner.interactionGeneration,
      );
      return;
    }
    await _sendWithTools(interactionGeneration: owner.interactionGeneration);
  }

  /// Whether this turn went out with no tools at all.
  ///
  /// An empty allowed set is what the tool-free send path records; null means
  /// the full catalog, which is the tool-aware turn.
  bool _turnDeniedTools(ChatTurnOwner owner) {
    final allowed = _activeResponseRegistry
        .snapshotForOwner(owner)
        ?.allowedToolNames;
    return allowed != null && allowed.isEmpty;
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
