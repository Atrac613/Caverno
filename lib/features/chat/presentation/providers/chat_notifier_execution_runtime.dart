// Same-library extension on [ChatNotifier] that adapts the existing production
// orchestration to the frontend-neutral CLI1 runtime contract.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_notifier.dart';

extension ChatNotifierExecutionRuntime on ChatNotifier {
  Future<bool> _startRuntimeTurn({
    required int generation,
    required bool hidden,
  }) async {
    _runtimeVisibleAssistantContentByGeneration.remove(generation);
    final previous = _runtimeTurnsByGeneration.remove(generation);
    if (previous != null && !previous.isTerminal) {
      previous.fail(
        code: 'turn_replaced',
        message: 'The active turn was replaced by a new interaction.',
        exitCode: 130,
      );
    }
    try {
      _runtimeTurnsByGeneration[generation] = await _executionRuntime.startTurn(
        CavernoRuntimeTurnRequest(
          turnId: 'gen-$generation',
          conversationId: conversationId,
          hidden: hidden,
        ),
      );
      return true;
    } on CavernoRuntimeTurnStartException catch (error) {
      if (ref.mounted) {
        state = state.copyWith(isLoading: false, error: error.terminal.message);
      }
      return false;
    } on Object {
      if (ref.mounted) {
        state = state.copyWith(
          isLoading: false,
          error: 'The execution runtime could not start the turn.',
        );
      }
      return false;
    }
  }

  CavernoRuntimeTurnHandle? _runtimeTurnForGeneration(int generation) {
    return _runtimeTurnsByGeneration[generation];
  }

  void _emitRuntimeAssistantContent(int generation, String content) {
    final visibleContent = ContentParser.parse(content).text;
    final previous =
        _runtimeVisibleAssistantContentByGeneration[generation] ?? '';
    if (visibleContent == previous) {
      return;
    }
    _runtimeVisibleAssistantContentByGeneration[generation] = visibleContent;
    if (!visibleContent.startsWith(previous)) {
      return;
    }
    _runtimeTurnForGeneration(
      generation,
    )?.emitAssistantDelta(visibleContent.substring(previous.length));
  }

  void _emitRuntimeToolLifecycle({
    required int generation,
    required String toolCallId,
    required String toolName,
    required CavernoRuntimeToolLifecycleState state,
    required int loopIndex,
    String? schedulerClass,
    String? resultStatus,
    String? skipReason,
    int? durationMs,
  }) {
    _runtimeTurnForGeneration(generation)?.emitToolLifecycle(
      toolCallId: toolCallId,
      toolName: toolName,
      state: state,
      loopIndex: loopIndex,
      schedulerClass: schedulerClass,
      resultStatus: resultStatus,
      skipReason: skipReason,
      durationMs: durationMs,
    );
  }

  void _emitRuntimeApprovalRequired({
    required String id,
    required String capability,
    required String summary,
    String? target,
    bool rememberAllowed = false,
  }) {
    _runtimeTurnForGeneration(_interactionGeneration)?.emitApprovalRequired(
      CavernoRuntimeApprovalRequest(
        id: id,
        capability: capability,
        risk: CavernoRuntimeApprovalRisk.high,
        summary: summary,
        target: target,
        rememberAllowed: rememberAllowed,
      ),
    );
  }

  void _emitRuntimeQuestionRequired(CavernoRuntimeQuestionRequest request) {
    _runtimeTurnForGeneration(
      _interactionGeneration,
    )?.emitQuestionRequired(request);
  }

  void _emitRuntimeWorkflowTransition({
    required String stage,
    String? taskId,
    String? taskStatus,
  }) {
    _runtimeTurnForGeneration(_interactionGeneration)?.emitWorkflowTransition(
      stage: stage,
      taskId: taskId,
      taskStatus: taskStatus,
    );
  }

  void _emitRuntimeUsage(int generation, TokenUsage usage) {
    _runtimeTurnForGeneration(generation)?.emitUsage(
      promptTokens: usage.promptTokens,
      completionTokens: usage.completionTokens,
      totalTokens: usage.totalTokens,
    );
  }

  /// Ends [generation] for good: the runtime turn and the active-response
  /// registration are released together, because a registration outliving its
  /// turn strands the thread on a stale snapshot under a spinner until the app
  /// restarts. Clearing is idempotent, so earlier releases stay correct.
  /// See docs/multi_thread_architecture_study.md.
  void _completeRuntimeTurn(
    int generation, {
    required String content,
    String? exitReason,
  }) {
    final handle = _runtimeTurnsByGeneration.remove(generation);
    _runtimeVisibleAssistantContentByGeneration.remove(generation);
    _recordTurnExitIfUnclassified(
      generation,
      outcome: 'completed',
      reason: exitReason,
    );
    _clearActiveResponseForGeneration(generation);
    if (handle == null) {
      return;
    }
    handle.complete(content: ContentParser.parse(content).text);
  }

  void _failRuntimeTurn(
    int generation, {
    required String code,
    required String message,
    int exitCode = 2,
  }) {
    final handle = _runtimeTurnsByGeneration.remove(generation);
    _runtimeVisibleAssistantContentByGeneration.remove(generation);
    _recordTurnExitIfUnclassified(generation, outcome: 'failed:$code');
    _clearActiveResponseForGeneration(generation);
    if (handle == null) {
      return;
    }
    handle.fail(code: code, message: message, exitCode: exitCode);
  }

  CavernoRuntimeToolLifecycleState _runtimeToolLifecycleState(
    ToolExecutionLifecycleState state,
  ) {
    return switch (state) {
      ToolExecutionLifecycleState.queued =>
        CavernoRuntimeToolLifecycleState.queued,
      ToolExecutionLifecycleState.started =>
        CavernoRuntimeToolLifecycleState.started,
      ToolExecutionLifecycleState.completed =>
        CavernoRuntimeToolLifecycleState.completed,
    };
  }
}
