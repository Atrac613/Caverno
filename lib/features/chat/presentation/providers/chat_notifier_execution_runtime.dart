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
      unawaited(_pythonScriptRuntime.retireOwner(owner));
      _fileMutationRuntime.retireOwner(owner);
      unawaited(
        _mcpToolService?.clearBackgroundProcessOwner(owner) ??
            Future<void>.sync(
              () => _backgroundProcessMonitorService.clearOwner(owner),
            ),
      );
      // Through the runtime, not the service: it also retires the owner's
      // connection record and settles any outstanding disconnect receipts,
      // which clearing the service alone leaves behind.
      unawaited(_clearSshOwner(owner));
      _conversationTaintState.clearOwner(owner: owner);
      _cancelPendingToolApprovalsForOwner(owner);
      _toolApprovalCache.clear(owner);
      _hiddenAssistantEvidence.publish(owner);
      _contentToolTurns.dispose(owner);
      _turnEnd.dispose(owner);
      _goalCompletionEvidence.dispose(owner);
    }
    if (handle != null) terminalize(handle);
    _clearActiveResponseForGeneration(generation);
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
