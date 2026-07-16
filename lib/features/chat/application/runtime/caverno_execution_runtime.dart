import 'dart:async';

import 'caverno_runtime_event.dart';
import 'caverno_runtime_ports.dart';

final class CavernoRuntimeTurnRequest {
  const CavernoRuntimeTurnRequest({
    required this.turnId,
    this.conversationId,
    this.hidden = false,
  });

  final String turnId;
  final String? conversationId;
  final bool hidden;
}

final class CavernoRuntimeTurnStartException implements Exception {
  const CavernoRuntimeTurnStartException(this.terminal);

  final CavernoRuntimeRunFailed terminal;

  @override
  String toString() => terminal.message;
}

final class CavernoExecutionRuntime {
  CavernoExecutionRuntime({required this.composition, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final CavernoRuntimeComposition composition;
  final DateTime Function() _now;
  final StreamController<CavernoRuntimeEvent> _events =
      StreamController<CavernoRuntimeEvent>.broadcast(sync: true);
  final Map<String, CavernoRuntimeTurnHandle> _activeTurns =
      <String, CavernoRuntimeTurnHandle>{};
  final Map<String, Completer<void>> _preparingTurns =
      <String, Completer<void>>{};
  final Set<Future<void>> _pendingOwnershipReleases = <Future<void>>{};
  int _sequence = 0;
  bool _closed = false;
  Future<void>? _closeFuture;

  Stream<CavernoRuntimeEvent> get events => _events.stream;

  bool get isClosed => _closed;

  bool get hasActiveTurns => _activeTurns.isNotEmpty;

  Future<CavernoRuntimeTurnHandle> startTurn(
    CavernoRuntimeTurnRequest request,
  ) async {
    if (_closed) {
      throw StateError('The execution runtime is closed.');
    }
    if (_activeTurns.containsKey(request.turnId) ||
        _preparingTurns.containsKey(request.turnId)) {
      throw StateError('Turn ${request.turnId} is already active.');
    }

    final preparation = Completer<void>();
    _preparingTurns[request.turnId] = preparation;
    final settings = composition.settings.current;
    final explicitConversationId = request.conversationId?.trim();
    final repositoryConversationId = composition
        .repository
        .currentConversationId
        ?.trim();
    final conversationId = explicitConversationId?.isNotEmpty == true
        ? explicitConversationId
        : repositoryConversationId?.isNotEmpty == true
        ? repositoryConversationId
        : null;
    CavernoRuntimeOwnershipHandle? ownership;
    var ownershipTransferred = false;
    try {
      ownership = await composition.ownership.acquire(
        CavernoRuntimeOwnershipRequest(
          surface: composition.surface,
          mode: settings.mode,
          conversationId: conversationId,
          workspace: settings.workspace,
        ),
      );
      if (conversationId != null &&
          !await composition.repository.refreshConversation(conversationId)) {
        throw _startFailure(
          request: request,
          conversationId: conversationId,
          code: 'conversation_unavailable',
          message: 'The selected conversation is no longer available.',
          exitCode: 65,
        );
      }
      if (_closed) {
        throw _startFailure(
          request: request,
          conversationId: conversationId,
          code: 'runtime_closed',
          message: 'The execution runtime closed before the turn started.',
          exitCode: 130,
        );
      }

      final handle = CavernoRuntimeTurnHandle._(
        runtime: this,
        turnId: request.turnId,
        conversationId: conversationId,
        hidden: request.hidden,
        ownership: ownership,
      );
      ownershipTransferred = true;
      _activeTurns[request.turnId] = handle;
      final started =
          _publish(
                (sequence, timestamp) => CavernoRuntimeRunStarted(
                  sequence: sequence,
                  timestamp: timestamp,
                  turnId: request.turnId,
                  conversationId: conversationId,
                  surface: composition.surface,
                  mode: settings.mode,
                  model: settings.model,
                  baseUrl: settings.baseUrl,
                  workspace: settings.workspace,
                  toolNames: List<String>.unmodifiable(
                    composition.tools.availableToolNames,
                  ),
                  hidden: request.hidden,
                  frontendDiagnostics: Map<String, String>.unmodifiable(
                    settings.frontendDiagnostics,
                  ),
                ),
              )
              as CavernoRuntimeRunStarted;
      composition.lifecycle.onTurnStarted(started);
      return handle;
    } on CavernoRuntimeTurnStartException {
      rethrow;
    } on CavernoRuntimeOwnershipConflict catch (conflict) {
      throw _startFailure(
        request: request,
        conversationId: conversationId,
        code: 'execution_lease_conflict',
        message: conflict.message,
        exitCode: 75,
      );
    } on Object {
      throw _startFailure(
        request: request,
        conversationId: conversationId,
        code: 'turn_preparation_failed',
        message: 'The execution runtime could not prepare the turn.',
        exitCode: 74,
      );
    } finally {
      if (!ownershipTransferred) {
        ownership?.release();
      }
      _preparingTurns.remove(request.turnId);
      if (!preparation.isCompleted) {
        preparation.complete();
      }
    }
  }

  CavernoRuntimeTurnStartException _startFailure({
    required CavernoRuntimeTurnRequest request,
    required String? conversationId,
    required String code,
    required String message,
    required int exitCode,
  }) {
    final terminal =
        _publish(
              (sequence, timestamp) => CavernoRuntimeRunFailed(
                sequence: sequence,
                timestamp: timestamp,
                turnId: request.turnId,
                conversationId: conversationId,
                code: code,
                message: message,
                exitCode: exitCode,
              ),
            )
            as CavernoRuntimeRunFailed;
    composition.repository.onTurnTerminal(terminal);
    composition.lifecycle.onTurnTerminal(terminal);
    return CavernoRuntimeTurnStartException(terminal);
  }

  CavernoRuntimeEvent _publish(
    CavernoRuntimeEvent Function(int sequence, DateTime timestamp) create,
  ) {
    final event = create(++_sequence, _now().toUtc());
    composition.logs.onEvent(event);
    if (!_events.isClosed) {
      _events.add(event);
    }
    return event;
  }

  CavernoRuntimeEvent _publishForTurn(
    CavernoRuntimeTurnHandle handle,
    CavernoRuntimeEvent Function(
      int sequence,
      DateTime timestamp,
      String turnId,
      String? conversationId,
    )
    create,
  ) {
    if (handle._terminal != null) {
      throw StateError('Turn ${handle.turnId} is already terminal.');
    }
    return _publish(
      (sequence, timestamp) =>
          create(sequence, timestamp, handle.turnId, handle.conversationId),
    );
  }

  CavernoRuntimeTerminalEvent _terminal(
    CavernoRuntimeTurnHandle handle,
    CavernoRuntimeTerminalEvent Function(
      int sequence,
      DateTime timestamp,
      String turnId,
      String? conversationId,
    )
    create,
  ) {
    final existing = handle._terminal;
    if (existing != null) {
      return existing;
    }
    final terminal =
        _publish(
              (sequence, timestamp) => create(
                sequence,
                timestamp,
                handle.turnId,
                handle.conversationId,
              ),
            )
            as CavernoRuntimeTerminalEvent;
    handle._terminal = terminal;
    _activeTurns.remove(handle.turnId);
    composition.repository.onTurnTerminal(terminal);
    composition.lifecycle.onTurnTerminal(terminal);
    if (!handle._done.isCompleted) {
      handle._done.complete(terminal);
    }
    _scheduleOwnershipRelease(handle);
    return terminal;
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    await Future.wait(
      _preparingTurns.values.map((preparation) => preparation.future),
    );
    terminateActiveTurns(
      code: 'runtime_closed',
      message: 'The execution runtime closed before the turn completed.',
      exitCode: 130,
    );
    await Future.wait(_pendingOwnershipReleases.toList(growable: false));
    await _events.close();
  }

  void _scheduleOwnershipRelease(CavernoRuntimeTurnHandle handle) {
    final pending = _drainPersistenceAndRelease(handle);
    _pendingOwnershipReleases.add(pending);
    unawaited(
      pending.whenComplete(() {
        _pendingOwnershipReleases.remove(pending);
      }),
    );
  }

  Future<void> _drainPersistenceAndRelease(
    CavernoRuntimeTurnHandle handle,
  ) async {
    try {
      await composition.repository.flushPendingPersistence();
    } on Object {
      // The turn is already terminal. Ownership must still be released so a
      // failed persistence drain cannot permanently block future execution.
    } finally {
      try {
        handle._ownership.release();
      } on Object {
        // OS locks are process-owned and will be released at process exit.
      }
    }
  }

  List<CavernoRuntimeTerminalEvent> terminateActiveTurns({
    required String code,
    required String message,
    required int exitCode,
  }) {
    return _activeTurns.values
        .toList(growable: false)
        .map(
          (handle) =>
              handle.fail(code: code, message: message, exitCode: exitCode),
        )
        .toList(growable: false);
  }
}

final class CavernoRuntimeTurnHandle {
  CavernoRuntimeTurnHandle._({
    required CavernoExecutionRuntime runtime,
    required this.turnId,
    required this.conversationId,
    required this.hidden,
    required CavernoRuntimeOwnershipHandle ownership,
  }) : _runtime = runtime,
       _ownership = ownership;

  final CavernoExecutionRuntime _runtime;
  final String turnId;
  final String? conversationId;
  final bool hidden;
  final CavernoRuntimeOwnershipHandle _ownership;
  final Completer<CavernoRuntimeTerminalEvent> _done =
      Completer<CavernoRuntimeTerminalEvent>();
  CavernoRuntimeTerminalEvent? _terminal;
  (int, int, int)? _lastUsage;

  Future<CavernoRuntimeTerminalEvent> get done => _done.future;

  bool get isTerminal => _terminal != null;

  void emitAssistantDelta(String delta) {
    if (hidden || delta.isEmpty || isTerminal) {
      return;
    }
    _runtime._publishForTurn(
      this,
      (sequence, timestamp, turnId, conversationId) =>
          CavernoRuntimeAssistantDelta(
            sequence: sequence,
            timestamp: timestamp,
            turnId: turnId,
            conversationId: conversationId,
            delta: delta,
          ),
    );
  }

  void emitToolLifecycle({
    required String toolCallId,
    required String toolName,
    required CavernoRuntimeToolLifecycleState state,
    required int loopIndex,
    String? schedulerClass,
    String? resultStatus,
    String? skipReason,
    int? durationMs,
  }) {
    if (isTerminal) {
      return;
    }
    _runtime._publishForTurn(
      this,
      (sequence, timestamp, turnId, conversationId) =>
          CavernoRuntimeToolLifecycle(
            sequence: sequence,
            timestamp: timestamp,
            turnId: turnId,
            conversationId: conversationId,
            toolCallId: toolCallId,
            toolName: toolName,
            state: state,
            loopIndex: loopIndex,
            schedulerClass: schedulerClass,
            resultStatus: resultStatus,
            skipReason: skipReason,
            durationMs: durationMs,
          ),
    );
  }

  void emitApprovalRequired(CavernoRuntimeApprovalRequest request) {
    if (isTerminal) {
      return;
    }
    _runtime.composition.approvals.onApprovalRequired(request);
    _runtime._publishForTurn(
      this,
      (sequence, timestamp, turnId, conversationId) =>
          CavernoRuntimeApprovalRequired(
            sequence: sequence,
            timestamp: timestamp,
            turnId: turnId,
            conversationId: conversationId,
            request: request,
          ),
    );
  }

  void emitQuestionRequired(CavernoRuntimeQuestionRequest request) {
    if (isTerminal) {
      return;
    }
    _runtime._publishForTurn(
      this,
      (sequence, timestamp, turnId, conversationId) =>
          CavernoRuntimeQuestionRequired(
            sequence: sequence,
            timestamp: timestamp,
            turnId: turnId,
            conversationId: conversationId,
            request: request,
          ),
    );
  }

  void emitWorkflowTransition({
    required String stage,
    String? taskId,
    String? taskStatus,
  }) {
    if (isTerminal) {
      return;
    }
    _runtime._publishForTurn(
      this,
      (sequence, timestamp, turnId, conversationId) =>
          CavernoRuntimeWorkflowTransition(
            sequence: sequence,
            timestamp: timestamp,
            turnId: turnId,
            conversationId: conversationId,
            stage: stage,
            taskId: taskId,
            taskStatus: taskStatus,
          ),
    );
  }

  void emitUsage({
    required int promptTokens,
    required int completionTokens,
    required int totalTokens,
  }) {
    if (isTerminal) {
      return;
    }
    final usage = (promptTokens, completionTokens, totalTokens);
    if (_lastUsage == usage) {
      return;
    }
    _lastUsage = usage;
    _runtime._publishForTurn(
      this,
      (sequence, timestamp, turnId, conversationId) => CavernoRuntimeUsage(
        sequence: sequence,
        timestamp: timestamp,
        turnId: turnId,
        conversationId: conversationId,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: totalTokens,
      ),
    );
  }

  CavernoRuntimeTerminalEvent complete({required String content}) {
    return _runtime._terminal(
      this,
      (sequence, timestamp, turnId, conversationId) =>
          CavernoRuntimeRunCompleted(
            sequence: sequence,
            timestamp: timestamp,
            turnId: turnId,
            conversationId: conversationId,
            content: hidden ? '' : content,
          ),
    );
  }

  CavernoRuntimeTerminalEvent fail({
    required String code,
    required String message,
    required int exitCode,
  }) {
    return _runtime._terminal(
      this,
      (sequence, timestamp, turnId, conversationId) => CavernoRuntimeRunFailed(
        sequence: sequence,
        timestamp: timestamp,
        turnId: turnId,
        conversationId: conversationId,
        code: code,
        message: message,
        exitCode: exitCode,
      ),
    );
  }
}
