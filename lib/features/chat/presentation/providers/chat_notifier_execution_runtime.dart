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
      if (!_contentToolTurns.begin(owner) ||
          !_hiddenAssistantEvidence.begin(owner) ||
          !_turnEnd.begin(owner) ||
          !_goalCompletionEvidence.begin(
            owner,
            initialEvidence: initialGoalCompletionEvidence,
          )) {
        _contentToolTurns.dispose(owner);
        _hiddenAssistantEvidence.dispose(owner);
        _turnEnd.dispose(owner);
        _goalCompletionEvidence.dispose(owner);
        handle.fail(
          code: 'content_tool_state_unavailable',
          message: 'Turn-owned execution state could not be initialized.',
          exitCode: 70,
        );
        return null;
      }
      _runtimeTurns[generation] = handle;
      _registerTurnReleases(owner);
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
  };

  @visibleForTesting
  bool turnStateIsClearedForTest() =>
      _activeResponseRegistry.openRegistrationCount == 0 &&
      _contentToolTurns.isEmpty &&
      _goalCompletionEvidence.isEmpty &&
      _responseMetadata.isEmpty &&
      _toolApprovalCache.isEmpty &&
      _runtimeTurns.isEmpty &&
      _turnEnd.isEmpty;

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
