import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/services/tool_execution_scheduler.dart';
import 'package:caverno/features/chat/presentation/providers/runtime_turn_event_publisher.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('publishes non-terminal events to the exact runtime handle', () async {
    final ports = _RuntimePorts();
    final runtime = CavernoExecutionRuntime(
      composition: CavernoRuntimeComposition(
        surface: CavernoRuntimeSurface.headless,
        settings: ports,
        repository: ports,
        ownership: ports,
        llm: ports,
        tools: ports,
        approvals: ports,
        logs: ports,
        lifecycle: ports,
      ),
    );
    final handle = await runtime.startTurn(
      const CavernoRuntimeTurnRequest(
        turnId: 'gen-1',
        conversationId: 'conversation-a',
      ),
    );
    final otherHandle = await runtime.startTurn(
      const CavernoRuntimeTurnRequest(
        turnId: 'gen-2',
        conversationId: 'conversation-b',
      ),
    );
    addTearDown(() async {
      if (!handle.isTerminal) {
        handle.fail(
          code: 'test_cleanup',
          message: 'Test cleanup.',
          exitCode: 1,
        );
      }
      if (!otherHandle.isTerminal) {
        otherHandle.fail(
          code: 'test_cleanup',
          message: 'Test cleanup.',
          exitCode: 1,
        );
      }
      await runtime.close();
    });
    final handles = <int, CavernoRuntimeTurnHandle>{1: handle, 2: otherHandle};
    final publisher = RuntimeTurnEventPublisher(handles);
    ports.events.clear();

    publisher.emitRuntimeAssistantContent(1, 'Hello');
    publisher.emitRuntimeAssistantContent(1, 'Hello world');
    publisher.emitRuntimeAssistantContent(1, 'Hello world');
    publisher.emitRuntimeAssistantContent(1, 'Replacement');
    publisher.emitRuntimeToolLifecycle(
      generation: 1,
      toolCallId: 'tool-1',
      toolName: 'read_file',
      state: CavernoRuntimeToolLifecycleState.completed,
      loopIndex: 2,
      schedulerClass: 'serial',
      resultStatus: 'success',
      skipReason: 'none',
      durationMs: 12,
    );
    publisher.emitRuntimeApprovalRequired(
      generation: 1,
      id: 'approval-1',
      capability: 'file_mutation',
      summary: 'Write a file.',
      target: '/workspace/file.txt',
      rememberAllowed: true,
    );
    publisher.emitRuntimeQuestionRequired(
      1,
      const CavernoRuntimeQuestionRequest(
        id: 'question-1',
        prompt: 'Continue?',
        options: ['Yes', 'No'],
      ),
    );
    publisher.emitRuntimeWorkflowTransition(
      generation: 1,
      stage: 'implement',
      taskId: 'task-1',
      taskStatus: 'running',
    );
    publisher.emitRuntimeUsage(
      1,
      const TokenUsage(promptTokens: 10, completionTokens: 5, totalTokens: 15),
    );

    expect(
      ports.events.whereType<CavernoRuntimeAssistantDelta>().map(
        (event) => event.delta,
      ),
      ['Hello', ' world'],
    );
    final toolEvent =
        ports.events.singleWhere(
              (event) => event is CavernoRuntimeToolLifecycle,
            )
            as CavernoRuntimeToolLifecycle;
    expect(toolEvent.toolCallId, 'tool-1');
    expect(toolEvent.skipReason, 'none');
    expect(toolEvent.durationMs, 12);
    expect(ports.approvals.single.id, 'approval-1');
    expect(
      ports.events
          .whereType<CavernoRuntimeQuestionRequired>()
          .single
          .request
          .id,
      'question-1',
    );
    expect(
      ports.events.whereType<CavernoRuntimeWorkflowTransition>().single.stage,
      'implement',
    );
    final usage = ports.events.whereType<CavernoRuntimeUsage>().single;
    expect(usage.totalTokens, 15);

    publisher.emitRuntimeAssistantContent(2, 'Other owner');
    final otherDelta = ports.events
        .whereType<CavernoRuntimeAssistantDelta>()
        .last;
    expect(otherDelta.conversationId, 'conversation-b');
    expect(otherDelta.delta, 'Other owner');

    final eventCount = ports.events.length;
    publisher.emitRuntimeAssistantContent(3, 'Missing owner');
    publisher.emitRuntimeApprovalRequired(
      generation: 3,
      id: 'missing',
      capability: 'none',
      summary: 'Ignored.',
    );
    expect(ports.events, hasLength(eventCount));
    expect(ports.approvals, hasLength(1));

    publisher.clearAssistantContent(1);
    publisher.emitRuntimeAssistantContent(1, 'Reset');
    expect(
      ports.events.whereType<CavernoRuntimeAssistantDelta>().last.delta,
      'Reset',
    );
    expect(
      publisher.runtimeToolLifecycleState(ToolExecutionLifecycleState.queued),
      CavernoRuntimeToolLifecycleState.queued,
    );
    expect(
      publisher.runtimeToolLifecycleState(ToolExecutionLifecycleState.started),
      CavernoRuntimeToolLifecycleState.started,
    );
    expect(
      publisher.runtimeToolLifecycleState(
        ToolExecutionLifecycleState.completed,
      ),
      CavernoRuntimeToolLifecycleState.completed,
    );
  });
}

final class _RuntimePorts
    implements
        CavernoRuntimeSettingsPort,
        CavernoRuntimeRepositoryPort,
        CavernoRuntimeOwnershipPort,
        CavernoRuntimeLlmPort,
        CavernoRuntimeToolPort,
        CavernoRuntimeApprovalPort,
        CavernoRuntimeLogPort,
        CavernoRuntimeLifecyclePort {
  final List<CavernoRuntimeEvent> events = [];
  final List<CavernoRuntimeApprovalRequest> approvals = [];

  @override
  CavernoRuntimeSettingsSnapshot get current =>
      const CavernoRuntimeSettingsSnapshot(
        mode: 'coding',
        model: 'test-model',
        baseUrl: 'http://localhost:1234/v1',
      );

  @override
  String? get currentConversationId => 'conversation-a';

  @override
  String get providerName => 'test';

  @override
  List<String> get availableToolNames => const ['read_file'];

  @override
  Future<bool> refreshConversation(String conversationId) async => true;

  @override
  Future<void> flushPendingPersistence() async {}

  @override
  Future<CavernoRuntimeOwnershipHandle> acquire(
    CavernoRuntimeOwnershipRequest request,
  ) async => const _OwnershipHandle();

  @override
  void onApprovalRequired(CavernoRuntimeApprovalRequest request) {
    approvals.add(request);
  }

  @override
  void onEvent(CavernoRuntimeEvent event) {
    events.add(event);
  }

  @override
  void onTurnStarted(CavernoRuntimeRunStarted event) {}

  @override
  void onTurnTerminal(CavernoRuntimeTerminalEvent event) {}
}

final class _OwnershipHandle implements CavernoRuntimeOwnershipHandle {
  const _OwnershipHandle();

  @override
  void release() {}
}
