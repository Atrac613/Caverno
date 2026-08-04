// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierExecutionRuntime on ChatNotifier {
  int get _runtimeEventGeneration => TurnGeneration.current ?? 0;

  void _finishStreamedCompletionInBackground(
    ChatTurnOwner owner,
    Future<ChatCompletionTerminalMetadata> terminal,
  ) => unawaited(() async {
    try {
      final metadata = await terminal;
      if (!_activeResponseRegistry.containsOwner(owner)) return;
      if (!_responseMetadata.capture(owner, metadata)) return;
      await _finishStreaming(
        interactionGeneration: owner.interactionGeneration,
      );
    } catch (error, stackTrace) {
      if (!_activeResponseRegistry.containsOwner(owner)) return;
      appLog(
        '[ChatNotifier] Turn finalization failed for '
        '${owner.conversationId}/gen-${owner.interactionGeneration}: '
        '${error.runtimeType}: $error',
      );
      appLog('[ChatNotifier] stackTrace: $stackTrace');
      await _handleError(error, owner: owner);
    }
  }());

  Future<ChatTurnOwner?> _startRuntimeTurn({
    required int generation,
    required String ownerConversationId,
    required bool hidden,
    ToolResultCompletionEvidence initialGoalCompletionEvidence =
        const ToolResultCompletionEvidence(),
  }) async {
    _runtimeEvents.clearAssistantContent(generation);
    final previous = _runtimeTurns[generation];
    if (previous != null && !previous.isTerminal) {
      _failRuntimeTurn(
        generation,
        code: 'turn_replaced',
        message: 'The active turn was replaced by a new interaction.',
        exitCode: 130,
      );
    }
    // Held outside the try so a throw between registration and return still
    // discharges the scope. A registered scope that nothing drops is the
    // stranded-registration defect this boundary exists to prevent.
    ChatTurnOwner? registeredOwner;
    try {
      final handle = await _executionRuntime.startTurn(
        CavernoRuntimeTurnRequest(
          turnId: 'gen-$generation',
          conversationId: ownerConversationId,
          hidden: hidden,
        ),
      );
      if (!_isCurrentInteractionGeneration(generation)) {
        handle.fail(
          code: 'turn_cancelled_before_start',
          message: 'Cancelled before start.',
          exitCode: 130,
        );
        return null;
      }
      final owner = ChatTurnOwner(
        conversationId: ownerConversationId,
        interactionGeneration: generation,
      );
      registeredOwner = owner;
      // Registered before the acquisition guards, not after them, so the
      // failure below discharges the same obligations a live turn does. It
      // previously undid four of the eleven by hand, which is a third
      // destructor that had to be kept in step with the other two.
      _registerTurnReleases(owner);
      if (!_contentToolTurns.begin(owner) ||
          !_hiddenAssistantEvidence.begin(owner) ||
          !_turnEnd.begin(owner) ||
          !_goalCompletionEvidence.begin(
            owner,
            initialEvidence: initialGoalCompletionEvidence,
          )) {
        // Released before the handle fails, matching the order
        // `_terminalizeRuntimeTurn` uses for a live turn.
        _releaseTurnScope(owner);
        registeredOwner = null;
        handle.fail(
          code: 'content_tool_state_unavailable',
          message: 'Turn-owned execution state could not be initialized.',
          exitCode: 70,
        );
        return null;
      }
      _runtimeTurns[generation] = handle;
      registeredOwner = null;
      return owner;
    } on CavernoRuntimeTurnStartException catch (error) {
      _routeRuntimeStartFailure(ownerConversationId, error.terminal.message);
      return null;
    } on Object {
      _routeRuntimeStartFailure(
        ownerConversationId,
        'The execution runtime could not start the turn.',
      );
      return null;
    } finally {
      // Non-null only when the turn registered a scope and did not go on to
      // own it: the guard failure above already released, so this catches a
      // throw out of registration or acquisition.
      //
      // Untested, and deliberately kept: no test reaches it, because every
      // call between registration and return is a map operation that does not
      // throw in practice. Deleting it costs nothing today and reintroduces
      // the stranded-registration class the moment one of them grows a
      // failure mode. Mutating it away leaves the suite green -- do not read
      // that as coverage.
      final stranded = registeredOwner;
      if (stranded != null) _releaseTurnScope(stranded);
    }
  }

  /// What this turn owes, declared once where the turn begins.
  ///
  /// Every release is a no-op when the resource was never acquired, so
  /// registering the full set at start is safe and keeps the list in one place
  /// that is adjacent to acquisition rather than distant from it.
  void _registerTurnReleases(ChatTurnOwner owner) {
    final scope = TurnReleaseScope(owner: owner);
    _turnReleases[owner] = scope;
    scope
      ..register(
        'pythonScriptRuntime',
        () => unawaited(_pythonScriptRuntime.retireOwner(owner)),
      )
      ..register(
        'fileMutationRuntime',
        () => _fileMutationRuntime.retireOwner(owner),
      )
      ..register(
        'backgroundProcesses',
        () => unawaited(
          _mcpToolService?.clearBackgroundProcessOwner(owner) ??
              Future<void>.sync(
                () => _backgroundProcessMonitorService.clearOwner(owner),
              ),
        ),
      )
      // Through the runtime, not the service: it also retires the owner's
      // connection record and settles any outstanding disconnect receipts,
      // which clearing the service alone leaves behind.
      ..register('sshOwner', () => unawaited(_clearSshOwner(owner)))
      ..register(
        'conversationTaintState',
        () => _conversationTaintState.clearOwner(owner: owner),
      )
      ..register(
        'pendingToolApprovals',
        () => _cancelPendingToolApprovalsForOwner(owner),
      )
      ..register('toolApprovalCache', () => _toolApprovalCache.clear(owner))
      // Published, not disposed: this closes writes and opens a retention
      // window, because the evidence is read after the turn ends.
      ..register(
        'hiddenAssistantEvidence',
        () => _hiddenAssistantEvidence.publish(owner),
      )
      ..register('contentToolTurns', () => _contentToolTurns.dispose(owner))
      ..register('turnEnd', () => _turnEnd.dispose(owner))
      ..register(
        'goalCompletionEvidence',
        () => _goalCompletionEvidence.dispose(owner),
      )
      // Below: owner-scoped releases that used to sit in the generation-keyed
      // `_clearActiveResponseForGeneration`, which had to look the owner back
      // up to run them. All six are acquired only after the turn starts, so
      // they are empty on the paths that never reach a scope.
      //
      // A paused participant turn is not over: disposing its controls here
      // would end the turn the user paused, so the pause is checked first.
      ..register('participantTurnControls', () {
        if (!_participantTurnControls.contains(owner)) return;
        if (_participantTurnControls.isPaused(owner)) return;
        _participantTurnControls.dispose(owner);
      })
      ..register(
        'askUserQuestionRuntime',
        () => _askUserQuestionRuntime.retireOwner(owner),
      )
      ..register('responseMetadata', () => _responseMetadata.dispose(owner))
      ..register(
        'contextSurgeryObservations',
        () => _contextSurgeryObservations.removeOwner(owner),
      )
      ..register(
        'modelEditTelemetry',
        () => _modelEditTelemetry?.retireOwner(owner),
      )
      ..register(
        'modelSwitchCompaction',
        () => _modelSwitchHandoffs.discardPromptCompaction(owner),
      );
  }

  void _routeRuntimeStartFailure(String ownerConversationId, String message) {
    if (!ref.mounted) return;
    _routeThreadState(
      ownerConversationId,
      (s) => s.copyWith(isLoading: false, error: message),
    );
  }

  void _completeRuntimeTurn(
    int generation, {
    required String content,
    String? exitReason,
  }) {
    _recordTurnExitIfUnclassified(
      generation,
      outcome: 'completed',
      reason: exitReason,
    );
    _terminalizeRuntimeTurn(
      generation,
      (handle) => handle.complete(content: ContentParser.parse(content).text),
    );
  }

  void _failRuntimeTurn(
    int generation, {
    required String code,
    required String message,
    int exitCode = 2,
    bool recordExit = true,
  }) {
    if (recordExit) {
      _recordTurnExitIfUnclassified(generation, outcome: 'failed:$code');
    }
    _terminalizeRuntimeTurn(
      generation,
      (handle) => handle.fail(code: code, message: message, exitCode: exitCode),
    );
  }

  /// Every turn-local store this part's teardown is responsible for emptying.
  ///
  /// The destructor runs 21 manual steps across `_terminalizeRuntimeTurn` and
  /// `_clearActiveResponseForGeneration`, and until now nothing asserted that
  /// any of them happened.
  ///
  /// Two stores are deliberately excluded because they outlive the turn by
  /// design, and both share the owner-keyed shape of the ones that do not:
  /// `_turnToolResults` retains for ten minutes and no destructor touches it,
  /// and `_hiddenAssistantEvidence` is `publish`ed rather than disposed, which
  /// stops writes and starts a retention window instead of removing the entry.
  @visibleForTesting
  Map<String, bool> turnStateReportForTest() => {
    'activeResponseRegistry':
        _activeResponseRegistry.openRegistrationCount == 0,
    'contentToolTurns': _contentToolTurns.isEmpty,
    'goalCompletionEvidence': _goalCompletionEvidence.isEmpty,
    'responseMetadata': _responseMetadata.isEmpty,
    'toolApprovalCache': _toolApprovalCache.isEmpty,
    'runtimeTurns': _runtimeTurns.isEmpty,
    'turnEnd': _turnEnd.isEmpty,
    // A scope nobody dropped is the stranded registration this boundary
    // exists to prevent, and it was the one thing here nothing observed.
    'turnReleases': _turnReleases.isEmpty,
  };

  @visibleForTesting
  bool turnStateIsClearedForTest() =>
      _activeResponseRegistry.openRegistrationCount == 0 &&
      _contentToolTurns.isEmpty &&
      _goalCompletionEvidence.isEmpty &&
      _responseMetadata.isEmpty &&
      _toolApprovalCache.isEmpty &&
      _runtimeTurns.isEmpty &&
      _turnEnd.isEmpty &&
      _turnReleases.isEmpty;

  void _terminalizeRuntimeTurn(
    int generation,
    void Function(CavernoRuntimeTurnHandle handle) terminalize,
  ) {
    final handle = _runtimeTurns.remove(generation);
    final conversationId = handle?.conversationId;
    final owner = conversationId == null
        ? _turnOwnerForGeneration(generation)
        : ChatTurnOwner(
            conversationId: conversationId,
            interactionGeneration: generation,
          );
    _runtimeEvents.clearAssistantContent(generation);
    if (handle != null) {
      publishTurnEvidence(_turnToolResults, generation, handle.conversationId);
    }
    if (owner != null) {
      _releaseTurnScope(owner);
    }
    if (handle != null) terminalize(handle);
    _clearActiveResponseForGeneration(generation);
  }

  /// Registered and discharged names from the most recent turn teardown.
  ///
  /// The store report says released state ended up empty; this says the scope
  /// was actually asked for every release and ran every one. A release dropped
  /// from the registration list would pass the first check and fail this one.
  @visibleForTesting
  (List<String>, List<String>)? lastTurnReleaseReportForTest() =>
      _lastTurnRelease;

  /// Drops the turn's scope, discharging everything it registered.
  ///
  /// A turn with no scope was never started through `_startRuntimeTurn`, which
  /// happens on the start-failure paths; there is nothing owed.
  void _releaseTurnScope(ChatTurnOwner owner) {
    final scope = _turnReleases.remove(owner);
    if (scope == null) return;
    try {
      scope.dispose();
      _lastTurnRelease = (scope.registeredNames, scope.dischargedNames);
    } on TurnReleaseFailure catch (failure) {
      appLog('[ChatNotifier] Turn teardown reported failures: $failure');
    }
  }

  void _failAllRuntimeTurns({
    required String code,
    required String message,
    required int exitCode,
    bool recordExit = true,
  }) {
    for (final generation in _runtimeTurns.keys.toList(growable: false)) {
      _failRuntimeTurn(
        generation,
        code: code,
        message: message,
        exitCode: exitCode,
        recordExit: recordExit,
      );
    }
  }
}
