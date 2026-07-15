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

final class CavernoExecutionRuntime {
  CavernoExecutionRuntime({required this.composition, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final CavernoRuntimeComposition composition;
  final DateTime Function() _now;
  final StreamController<CavernoRuntimeEvent> _events =
      StreamController<CavernoRuntimeEvent>.broadcast(sync: true);
  final Map<String, CavernoRuntimeTurnHandle> _activeTurns =
      <String, CavernoRuntimeTurnHandle>{};
  int _sequence = 0;
  bool _closed = false;

  Stream<CavernoRuntimeEvent> get events => _events.stream;

  bool get isClosed => _closed;

  CavernoRuntimeTurnHandle startTurn(CavernoRuntimeTurnRequest request) {
    if (_closed) {
      throw StateError('The execution runtime is closed.');
    }
    if (_activeTurns.containsKey(request.turnId)) {
      throw StateError('Turn ${request.turnId} is already active.');
    }

    final settings = composition.settings.current;
    final conversationId = request.conversationId?.trim().isNotEmpty == true
        ? request.conversationId
        : composition.repository.currentConversationId;
    final handle = CavernoRuntimeTurnHandle._(
      runtime: this,
      turnId: request.turnId,
      conversationId: conversationId,
      hidden: request.hidden,
    );
    _activeTurns[request.turnId] = handle;
    final started = _publish(
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
      ),
    ) as CavernoRuntimeRunStarted;
    composition.lifecycle.onTurnStarted(started);
    return handle;
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
    return terminal;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final handle in _activeTurns.values.toList(growable: false)) {
      handle.fail(
        code: 'runtime_closed',
        message: 'The execution runtime closed before the turn completed.',
        exitCode: 130,
      );
    }
    await _events.close();
  }
}

final class CavernoRuntimeTurnHandle {
  CavernoRuntimeTurnHandle._({
    required CavernoExecutionRuntime runtime,
    required this.turnId,
    required this.conversationId,
    required this.hidden,
  }) : _runtime = runtime;

  final CavernoExecutionRuntime _runtime;
  final String turnId;
  final String? conversationId;
  final bool hidden;
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
