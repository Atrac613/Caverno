import 'package:caverno/features/chat/application/runtime/caverno_execution_runtime.dart';
import 'package:caverno/features/chat/application/runtime/caverno_runtime_event.dart';
import 'package:caverno/features/chat/application/runtime/caverno_runtime_ports.dart';
import 'package:test/test.dart';

void main() {
  group('CavernoExecutionRuntime', () {
    test('emits every typed event in strict sequence order', () async {
      final fixture = _RuntimeFixture();
      final events = <CavernoRuntimeEvent>[];
      final subscription = fixture.runtime.events.listen(events.add);

      final handle = fixture.runtime.startTurn(
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

      final handle = fixture.runtime.startTurn(
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
      final handle = fixture.runtime.startTurn(
        const CavernoRuntimeTurnRequest(turnId: 'turn-close'),
      );

      await fixture.runtime.close();

      final terminal = await handle.done;
      expect(terminal, isA<CavernoRuntimeRunFailed>());
      expect((terminal as CavernoRuntimeRunFailed).code, 'runtime_closed');
      expect(terminal.exitCode, 130);
      expect(fixture.runtime.isClosed, isTrue);
      expect(
        () => fixture.runtime.startTurn(
          const CavernoRuntimeTurnRequest(turnId: 'turn-after-close'),
        ),
        throwsStateError,
      );
      await subscription.cancel();
    });

    test('rejects duplicate active turn IDs', () async {
      final fixture = _RuntimeFixture();
      final handle = fixture.runtime.startTurn(
        const CavernoRuntimeTurnRequest(turnId: 'turn-duplicate'),
      );

      expect(
        () => fixture.runtime.startTurn(
          const CavernoRuntimeTurnRequest(turnId: 'turn-duplicate'),
        ),
        throwsStateError,
      );

      handle.fail(code: 'test_failure', message: 'failed', exitCode: 2);
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
      );
}

final class _RepositoryPort implements CavernoRuntimeRepositoryPort {
  final List<CavernoRuntimeTerminalEvent> terminals =
      <CavernoRuntimeTerminalEvent>[];

  @override
  String? get currentConversationId => 'repository-conversation';

  @override
  void onTurnTerminal(CavernoRuntimeTerminalEvent event) {
    terminals.add(event);
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
