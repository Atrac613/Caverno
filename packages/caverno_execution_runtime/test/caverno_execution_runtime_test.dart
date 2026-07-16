import 'dart:async';

import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import 'package:test/test.dart';

void main() {
  group('CavernoExecutionRuntime', () {
    test(
      'terminates every active turn with a caller-selected exit code',
      () async {
        final fixture = _RuntimeFixture();
        final runtime = fixture.runtime;
        final first = await runtime.startTurn(
          const CavernoRuntimeTurnRequest(turnId: 'turn-1'),
        );
        final second = await runtime.startTurn(
          const CavernoRuntimeTurnRequest(turnId: 'turn-2'),
        );

        final terminal = runtime.terminateActiveTurns(
          code: 'approval_unavailable',
          message: 'A terminal approval is unavailable.',
          exitCode: 77,
        );

        expect(runtime.hasActiveTurns, isFalse);
        expect(terminal, hasLength(2));
        expect(await first.done, isA<CavernoRuntimeRunFailed>());
        expect((await second.done as CavernoRuntimeRunFailed).exitCode, 77);
        await runtime.close();
      },
    );

    test('emits every typed event in strict sequence order', () async {
      final fixture = _RuntimeFixture();
      final events = <CavernoRuntimeEvent>[];
      final subscription = fixture.runtime.events.listen(events.add);

      final handle = await fixture.runtime.startTurn(
        const CavernoRuntimeTurnRequest(
          turnId: 'turn-1',
          conversationId: 'conversation-1',
        ),
      );
      handle.emitAssistantDelta('Hello');
      handle.emitToolLifecycle(
        toolCallId: 'tool-1',
        toolName: 'read_file',
        state: CavernoRuntimeToolLifecycleState.started,
        loopIndex: 1,
        schedulerClass: 'parallelFileRead',
      );
      handle.emitApprovalRequired(
        const CavernoRuntimeApprovalRequest(
          id: 'approval-1',
          capability: 'command_execution',
          risk: CavernoRuntimeApprovalRisk.high,
          summary: 'Run dart test',
          target: '/workspace',
          rememberAllowed: true,
        ),
      );
      handle.emitQuestionRequired(
        const CavernoRuntimeQuestionRequest(
          id: 'question-1',
          prompt: 'Choose a format',
          options: <String>['json', 'text'],
        ),
      );
      handle.emitWorkflowTransition(
        stage: 'implement',
        taskId: 'task-1',
        taskStatus: 'in_progress',
      );
      handle.emitUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15);
      handle.emitUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15);
      final completed = handle.complete(content: 'Hello');
      final duplicateCompletion = handle.complete(content: 'Ignored');

      expect(duplicateCompletion, same(completed));
      await expectLater(handle.done, completion(same(completed)));
      expect(events.map((event) => event.type), <String>[
        'run_started',
        'assistant_delta',
        'tool_lifecycle',
        'approval_required',
        'question_required',
        'workflow_transition',
        'usage',
        'run_completed',
      ]);
      expect(
        events.map((event) => event.sequence),
        orderedEquals(List<int>.generate(events.length, (index) => index + 1)),
      );
      expect(events.first, isA<CavernoRuntimeRunStarted>());
      expect(
        (events.first as CavernoRuntimeRunStarted).frontendDiagnostics,
        containsPair('approvalMode', 'manual'),
      );
      expect(events.last, isA<CavernoRuntimeRunCompleted>());
      expect(
        events.first.toJson(),
        containsPair('schema', CavernoRuntimeEvent.schema),
      );
      expect(
        events.first.toJson(),
        containsPair('schemaVersion', CavernoRuntimeEvent.schemaVersion),
      );
      expect(
        events.first.toJson(),
        containsPair('conversationId', 'conversation-1'),
      );
      expect(fixture.approvals.requests, hasLength(1));
      expect(fixture.repository.terminals, <CavernoRuntimeTerminalEvent>[
        completed,
      ]);
      expect(fixture.lifecycle.started, hasLength(1));
      expect(fixture.lifecycle.terminals, <CavernoRuntimeTerminalEvent>[
        completed,
      ]);
      expect(fixture.logs.events, orderedEquals(events));

      await subscription.cancel();
      await fixture.runtime.close();
    });

    test('keeps hidden assistant content out of runtime output', () async {
      final fixture = _RuntimeFixture();
      final events = <CavernoRuntimeEvent>[];
      final subscription = fixture.runtime.events.listen(events.add);

      final handle = await fixture.runtime.startTurn(
        const CavernoRuntimeTurnRequest(turnId: 'hidden-1', hidden: true),
      );
      handle.emitAssistantDelta('secret continuation');
      final completed = handle.complete(content: 'secret continuation');

      expect(events.whereType<CavernoRuntimeAssistantDelta>(), isEmpty);
      expect((completed as CavernoRuntimeRunCompleted).content, isEmpty);
      expect(completed.conversationId, 'repository-conversation');

      await subscription.cancel();
      await fixture.runtime.close();
    });

    test('fails active turns when the runtime closes', () async {
      final fixture = _RuntimeFixture();
      final events = <CavernoRuntimeEvent>[];
      final subscription = fixture.runtime.events.listen(events.add);
      final handle = await fixture.runtime.startTurn(
        const CavernoRuntimeTurnRequest(turnId: 'turn-close'),
      );

      await fixture.runtime.close();

      final terminal = await handle.done;
      expect(terminal, isA<CavernoRuntimeRunFailed>());
      expect((terminal as CavernoRuntimeRunFailed).code, 'runtime_closed');
      expect(terminal.exitCode, 130);
      expect(fixture.runtime.isClosed, isTrue);
      await expectLater(
        fixture.runtime.startTurn(
          const CavernoRuntimeTurnRequest(turnId: 'turn-after-close'),
        ),
        throwsStateError,
      );
      await subscription.cancel();
    });

    test('rejects duplicate active turn IDs', () async {
      final fixture = _RuntimeFixture();
      final handle = await fixture.runtime.startTurn(
        const CavernoRuntimeTurnRequest(turnId: 'turn-duplicate'),
      );

      await expectLater(
        fixture.runtime.startTurn(
          const CavernoRuntimeTurnRequest(turnId: 'turn-duplicate'),
        ),
        throwsStateError,
      );

      handle.fail(code: 'test_failure', message: 'failed', exitCode: 2);
      await fixture.runtime.close();
    });

    test('publishes run_started only after conversation refresh', () async {
      final fixture = _RuntimeFixture();
      final refreshGate = Completer<bool>();
      fixture.repository.refreshGate = refreshGate;
      final events = <CavernoRuntimeEvent>[];
      final subscription = fixture.runtime.events.listen(events.add);

      final start = fixture.runtime.startTurn(
        const CavernoRuntimeTurnRequest(turnId: 'turn-refresh'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fixture.ownership.requests, hasLength(1));
      expect(fixture.repository.refreshes, ['repository-conversation']);
      expect(events, isEmpty);

      refreshGate.complete(true);
      final handle = await start;

      expect(events.single, isA<CavernoRuntimeRunStarted>());
      handle.complete(content: 'done');
      await fixture.runtime.close();
      await subscription.cancel();
    });

    test('emits a retryable failure when ownership conflicts', () async {
      final fixture = _RuntimeFixture();
      fixture.ownership.conflictMessage =
          'conversation:conflict is already owned by terminal process 42.';
      final events = <CavernoRuntimeEvent>[];
      final subscription = fixture.runtime.events.listen(events.add);

      await expectLater(
        fixture.runtime.startTurn(
          const CavernoRuntimeTurnRequest(turnId: 'turn-conflict'),
        ),
        throwsA(isA<CavernoRuntimeTurnStartException>()),
      );

      expect(events, hasLength(1));
      final failure = events.single as CavernoRuntimeRunFailed;
      expect(failure.code, 'execution_lease_conflict');
      expect(failure.exitCode, 75);
      expect(fixture.repository.refreshes, isEmpty);
      expect(fixture.lifecycle.started, isEmpty);
      await fixture.runtime.close();
      await subscription.cancel();
    });

    test(
      'fails before run_started when the conversation disappeared',
      () async {
        final fixture = _RuntimeFixture();
        fixture.repository.refreshResult = false;
        final events = <CavernoRuntimeEvent>[];
        final subscription = fixture.runtime.events.listen(events.add);

        await expectLater(
          fixture.runtime.startTurn(
            const CavernoRuntimeTurnRequest(turnId: 'turn-missing'),
          ),
          throwsA(isA<CavernoRuntimeTurnStartException>()),
        );

        final failure = events.single as CavernoRuntimeRunFailed;
        expect(failure.code, 'conversation_unavailable');
        expect(failure.exitCode, 65);
        expect(fixture.lifecycle.started, isEmpty);
        expect(fixture.ownership.handles.single.released, isTrue);
        await fixture.runtime.close();
        await subscription.cancel();
      },
    );

    test('retains ownership until terminal persistence drains', () async {
      final fixture = _RuntimeFixture();
      final flushGate = Completer<void>();
      fixture.repository.flushGate = flushGate;
      final handle = await fixture.runtime.startTurn(
        const CavernoRuntimeTurnRequest(turnId: 'turn-flush'),
      );

      handle.complete(content: 'done');
      await Future<void>.delayed(Duration.zero);

      final ownership = fixture.ownership.handles.single;
      expect(ownership.released, isFalse);

      flushGate.complete();
      await fixture.runtime.close();

      expect(ownership.released, isTrue);
    });

    test('rejects a duplicate turn ID while preparation is pending', () async {
      final fixture = _RuntimeFixture();
      final refreshGate = Completer<bool>();
      fixture.repository.refreshGate = refreshGate;
      final first = fixture.runtime.startTurn(
        const CavernoRuntimeTurnRequest(turnId: 'turn-preparing'),
      );
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        fixture.runtime.startTurn(
          const CavernoRuntimeTurnRequest(turnId: 'turn-preparing'),
        ),
        throwsStateError,
      );

      refreshGate.complete(true);
      final handle = await first;
      handle.complete(content: 'done');
      await fixture.runtime.close();
    });
  });
}

final class _RuntimeFixture {
  _RuntimeFixture() {
    runtime = CavernoExecutionRuntime(
      composition: CavernoRuntimeComposition(
        surface: CavernoRuntimeSurface.headless,
        settings: const _SettingsPort(),
        repository: repository,
        ownership: ownership,
        llm: const _LlmPort(),
        tools: const _ToolPort(),
        approvals: approvals,
        logs: logs,
        lifecycle: lifecycle,
      ),
      now: () => DateTime.utc(2026, 7, 16, 1, 2, 3),
    );
  }

  final _RepositoryPort repository = _RepositoryPort();
  final _OwnershipPort ownership = _OwnershipPort();
  final _ApprovalPort approvals = _ApprovalPort();
  final _LogPort logs = _LogPort();
  final _LifecyclePort lifecycle = _LifecyclePort();
  late final CavernoExecutionRuntime runtime;
}

final class _SettingsPort implements CavernoRuntimeSettingsPort {
  const _SettingsPort();

  @override
  CavernoRuntimeSettingsSnapshot get current =>
      const CavernoRuntimeSettingsSnapshot(
        mode: 'coding',
        model: 'test-model',
        baseUrl: 'http://localhost:1234/v1',
        workspace: '/workspace',
        frontendDiagnostics: <String, String>{'approvalMode': 'manual'},
      );
}

final class _RepositoryPort implements CavernoRuntimeRepositoryPort {
  final List<CavernoRuntimeTerminalEvent> terminals =
      <CavernoRuntimeTerminalEvent>[];
  final List<String> refreshes = <String>[];
  Completer<bool>? refreshGate;
  Completer<void>? flushGate;
  bool refreshResult = true;

  @override
  String? get currentConversationId => 'repository-conversation';

  @override
  Future<bool> refreshConversation(String conversationId) {
    refreshes.add(conversationId);
    return refreshGate?.future ?? Future<bool>.value(refreshResult);
  }

  @override
  Future<void> flushPendingPersistence() =>
      flushGate?.future ?? Future<void>.value();

  @override
  void onTurnTerminal(CavernoRuntimeTerminalEvent event) {
    terminals.add(event);
  }
}

final class _OwnershipPort implements CavernoRuntimeOwnershipPort {
  final List<_OwnershipHandle> handles = <_OwnershipHandle>[];
  final List<CavernoRuntimeOwnershipRequest> requests =
      <CavernoRuntimeOwnershipRequest>[];
  String? conflictMessage;

  @override
  Future<CavernoRuntimeOwnershipHandle> acquire(
    CavernoRuntimeOwnershipRequest request,
  ) async {
    requests.add(request);
    final message = conflictMessage;
    if (message != null) {
      throw CavernoRuntimeOwnershipConflict(message);
    }
    final handle = _OwnershipHandle();
    handles.add(handle);
    return handle;
  }
}

final class _OwnershipHandle implements CavernoRuntimeOwnershipHandle {
  bool released = false;

  @override
  void release() {
    released = true;
  }
}

final class _LlmPort implements CavernoRuntimeLlmPort {
  const _LlmPort();

  @override
  String get providerName => 'test';
}

final class _ToolPort implements CavernoRuntimeToolPort {
  const _ToolPort();

  @override
  List<String> get availableToolNames => const <String>['read_file'];
}

final class _ApprovalPort implements CavernoRuntimeApprovalPort {
  final List<CavernoRuntimeApprovalRequest> requests =
      <CavernoRuntimeApprovalRequest>[];

  @override
  void onApprovalRequired(CavernoRuntimeApprovalRequest request) {
    requests.add(request);
  }
}

final class _LogPort implements CavernoRuntimeLogPort {
  final List<CavernoRuntimeEvent> events = <CavernoRuntimeEvent>[];

  @override
  void onEvent(CavernoRuntimeEvent event) {
    events.add(event);
  }
}

final class _LifecyclePort implements CavernoRuntimeLifecyclePort {
  final List<CavernoRuntimeRunStarted> started = <CavernoRuntimeRunStarted>[];
  final List<CavernoRuntimeTerminalEvent> terminals =
      <CavernoRuntimeTerminalEvent>[];

  @override
  void onTurnStarted(CavernoRuntimeRunStarted event) {
    started.add(event);
  }

  @override
  void onTurnTerminal(CavernoRuntimeTerminalEvent event) {
    terminals.add(event);
  }
}
