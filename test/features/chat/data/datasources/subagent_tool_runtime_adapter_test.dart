import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/subagent_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/subagent_tool_contract.dart';
import 'package:test/test.dart';

final _owner = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 7,
);
final _fixedTime = DateTime.utc(2026, 7, 31, 12);

Map<String, dynamic> _tool(String name) => {
  'type': 'function',
  'function': <String, dynamic>{
    'name': name,
    'parameters': <String, dynamic>{'type': 'object'},
  },
};

void main() {
  test('forwards a foreground run through exact callback identities', () async {
    final store = _RuntimeStore();
    final seenChildren = <ChildToolExecutionRequest>[];
    final adapter = _adapter(
      store: store,
      execute: (request, {required dispatchToolCall}) async {
        expect(request.identity.owner, _owner);
        expect(request.identity.parentToolCallId, 'spawn-call');
        expect(request.identity.taskId, 'task-1');
        expect(request.tools, [_tool('read_file')]);
        expect(request.allowedToolNames, {'read_file'});

        final childResult = await dispatchToolCall(
          ToolCallInfo(
            id: 'child-call',
            name: 'read_file',
            arguments: const {'path': 'README.md'},
          ),
        );
        expect(childResult.result, 'contents');
        return _completedTask(request);
      },
      executeChild: (request) async {
        seenChildren.add(request);
        return const McpToolResult(
          toolName: 'read_file',
          result: 'contents',
          isSuccess: true,
        );
      },
    );

    final result = await adapter.handle(
      owner: _owner,
      toolCall: ToolCallInfo(
        id: 'spawn-call',
        name: spawnSubagentToolName,
        arguments: const {'description': 'Inspect', 'prompt': 'Read the file.'},
      ),
      parentToolDefinitions: [_tool(spawnSubagentToolName), _tool('read_file')],
    );

    expect(jsonDecode(result.result), {
      'status': 'completed',
      'task_id': 'task-1',
      'description': 'Inspect',
      'summary': 'done',
    });
    expect(result.isSuccess, isTrue);
    expect(seenChildren, hasLength(1));
    expect(seenChildren.single.taskIdentity.owner, _owner);
    expect(seenChildren.single.taskIdentity.parentToolCallId, 'spawn-call');
    expect(seenChildren.single.id, 'child-call');
    expect(seenChildren.single.arguments, {'path': 'README.md'});
  });

  test(
    'persists and notifies a background run under its exact owner',
    () async {
      final store = _RuntimeStore();
      final releaseExecution = Completer<void>();
      final notified = Completer<SubagentTaskIdentity>();
      final adapter = _adapter(
        store: store,
        execute: (request, {required dispatchToolCall}) async {
          await releaseExecution.future;
          return _completedTask(request);
        },
        notify: (identity, notification) async {
          expect(notification.taskId, 'task-1');
          expect(notification.description, 'Inspect');
          expect(notification.isSuccessful, isTrue);
          expect(notification.body, 'done');
          notified.complete(identity);
        },
      );

      final result = await adapter.handle(
        owner: _owner,
        toolCall: ToolCallInfo(
          id: 'spawn-call',
          name: spawnSubagentToolName,
          arguments: const {
            'description': 'Inspect',
            'prompt': 'Read the file.',
            'background': true,
          },
        ),
        parentToolDefinitions: [_tool('read_file')],
      );

      expect(jsonDecode(result.result)['status'], 'started');
      final running = store.lookup(_owner, 'task-1');
      expect(running?.status, SubagentTaskStatus.running);
      expect(running?.parentToolUseId, 'spawn-call');

      releaseExecution.complete();
      final identity = await notified.future.timeout(
        const Duration(seconds: 2),
      );
      await Future<void>.delayed(Duration.zero);

      expect(identity.owner, _owner);
      expect(identity.parentToolCallId, 'spawn-call');
      expect(identity.taskId, 'task-1');
      final completed = store.lookup(_owner, 'task-1');
      expect(completed?.status, SubagentTaskStatus.completed);
      expect(completed?.resultSummary, 'done');
      expect(completed?.notified, isTrue);
    },
  );

  test('lookup cannot read another owner and respects retirement', () async {
    final store = _RuntimeStore();
    final identity = SubagentTaskIdentity(
      owner: _owner,
      parentToolCallId: 'spawn-call',
      taskId: 'task-1',
    );
    store.tasks[_RuntimeStore.key(_owner, 'task-1')] = SubagentTask(
      id: 'task-1',
      conversationId: _owner.conversationId,
      interactionGeneration: _owner.interactionGeneration,
      status: SubagentTaskStatus.completed,
      description: 'Inspect',
      parentToolUseId: 'spawn-call',
      resultSummary: 'done',
    );
    final retiredCalls = <String>{};
    final adapter = _adapter(
      store: store,
      isLookupCurrent: (lookup) =>
          !retiredCalls.contains(lookup.invocation.toolCallId),
    );

    final otherOwnerResult = await adapter.handle(
      owner: ChatTurnOwner(
        conversationId: 'conversation-b',
        interactionGeneration: 7,
      ),
      toolCall: ToolCallInfo(
        id: 'other-result-call',
        name: getSubagentResultToolName,
        arguments: const {'task_id': 'task-1'},
      ),
      parentToolDefinitions: const [],
    );
    expect(otherOwnerResult.isSuccess, isFalse);
    expect(jsonDecode(otherOwnerResult.result)['status'], 'not_found');

    final currentResult = await adapter.handle(
      owner: _owner,
      toolCall: ToolCallInfo(
        id: 'result-call',
        name: getSubagentResultToolName,
        arguments: const {'task_id': 'task-1'},
      ),
      parentToolDefinitions: const [],
    );
    expect(currentResult.isSuccess, isTrue);
    expect(jsonDecode(currentResult.result)['summary'], 'done');

    retiredCalls.add('retired-result-call');
    final retiredResult = await adapter.handle(
      owner: _owner,
      toolCall: ToolCallInfo(
        id: 'retired-result-call',
        name: getSubagentResultToolName,
        arguments: const {'task_id': 'task-1'},
      ),
      parentToolDefinitions: const [],
    );
    expect(retiredResult.isSuccess, isFalse);
    expect(
      retiredResult.errorMessage,
      'Subagent execution was cancelled because its exact owner expired',
    );
    expect(identity.owner, _owner);
  });

  group('SubagentTaskStoreAdapter receipts', () {
    test('accepts exact registration and rejects duplicate or mismatch', () {
      final store = _RuntimeStore();
      final adapter = store.adapter;
      final identity = _identity();
      final task = _runningTask(identity);

      expect(
        adapter.register(identity, task).disposition,
        SubagentTransitionDisposition.accepted,
      );
      expect(
        adapter.register(identity, task).disposition,
        SubagentTransitionDisposition.rejected,
      );

      final mismatched = task.copyWith(parentToolUseId: 'other-call');
      expect(
        adapter
            .register(
              SubagentTaskIdentity(
                owner: _owner,
                parentToolCallId: 'second-call',
                taskId: 'task-2',
              ),
              mismatched.copyWith(id: 'task-2'),
            )
            .disposition,
        SubagentTransitionDisposition.rejected,
      );
    });

    test('verifies completion, failure, and notification postconditions', () {
      final store = _RuntimeStore();
      final adapter = store.adapter;
      final completeIdentity = _identity();
      adapter.register(completeIdentity, _runningTask(completeIdentity));

      expect(
        adapter
            .complete(completeIdentity, output: 'output', summary: 'summary')
            .disposition,
        SubagentTransitionDisposition.accepted,
      );
      expect(
        adapter.markNotified(completeIdentity).disposition,
        SubagentTransitionDisposition.accepted,
      );
      expect(adapter.lookupExact(completeIdentity)?.task.notified, isTrue);

      final failureIdentity = _identity(
        taskId: 'task-2',
        parentToolCallId: 'spawn-call-2',
      );
      adapter.register(failureIdentity, _runningTask(failureIdentity));
      expect(
        adapter.fail(failureIdentity, 'boom').disposition,
        SubagentTransitionDisposition.accepted,
      );
      expect(adapter.lookupExact(failureIdentity)?.task.error, 'boom');
    });

    test('reports uncertain when a callback claims an unapplied effect', () {
      final store = _RuntimeStore();
      final identity = _identity();
      store.tasks[_RuntimeStore.key(_owner, identity.taskId)] = _runningTask(
        identity,
      );
      final adapter = SubagentTaskStoreAdapter(
        lookupTask: store.lookup,
        registerTask: store.register,
        completeTask: (owner, taskId, {required output, required summary}) =>
            true,
        failTask: store.fail,
        markTaskNotified: store.markNotified,
      );

      expect(
        adapter
            .complete(identity, output: 'missing', summary: 'missing')
            .disposition,
        SubagentTransitionDisposition.effectUncertain,
      );
      expect(
        adapter.lookupExact(identity)?.task.status,
        SubagentTaskStatus.running,
      );
    });
  });
}

SubagentToolRuntimeAdapter _adapter({
  required _RuntimeStore store,
  SubagentExecutionCallback? execute,
  SubagentChildExecutionCallback? executeChild,
  SubagentNotificationCallback? notify,
  SubagentTaskCurrentCallback? isTaskCurrent,
  SubagentLookupCurrentCallback? isLookupCurrent,
}) {
  return SubagentToolRuntimeAdapter(
    lookupTask: store.lookup,
    registerTask: store.register,
    completeTask: store.complete,
    failTask: store.fail,
    markTaskNotified: store.markNotified,
    isTaskCurrent: isTaskCurrent ?? (_) => true,
    isLookupCurrent: isLookupCurrent ?? (_) => true,
    execute:
        execute ??
        (request, {required dispatchToolCall}) async => _completedTask(request),
    executeChild:
        executeChild ??
        (request) async =>
            McpToolResult(toolName: request.name, result: '', isSuccess: true),
    notify: notify ?? (identity, notification) async {},
    filterTools: (definitions) => definitions
        .where(
          (definition) =>
              _toolName(definition) != spawnSubagentToolName &&
              _toolName(definition) != getSubagentResultToolName,
        )
        .toList(growable: false),
    toolName: _toolName,
    taskIdFactory: () => 'task-1',
    clock: () => _fixedTime,
  );
}

String _toolName(Map<String, dynamic> tool) {
  return ((tool['function'] as Map?)?['name'] as String?) ?? '';
}

SubagentTaskIdentity _identity({
  String taskId = 'task-1',
  String parentToolCallId = 'spawn-call',
}) {
  return SubagentTaskIdentity(
    owner: _owner,
    parentToolCallId: parentToolCallId,
    taskId: taskId,
  );
}

SubagentTask _runningTask(SubagentTaskIdentity identity) {
  return SubagentTask(
    id: identity.taskId,
    conversationId: identity.owner.conversationId,
    interactionGeneration: identity.owner.interactionGeneration,
    status: SubagentTaskStatus.running,
    description: 'Inspect',
    parentToolUseId: identity.parentToolCallId,
    prompt: 'Read the file.',
    isBackground: true,
    startedAt: _fixedTime,
  );
}

SubagentTask _completedTask(SubagentExecutionRequest request) {
  return SubagentTask(
    id: request.identity.taskId,
    conversationId: request.identity.owner.conversationId,
    interactionGeneration: request.identity.owner.interactionGeneration,
    status: SubagentTaskStatus.completed,
    description: request.description,
    parentToolUseId: request.identity.parentToolCallId,
    prompt: request.prompt,
    output: 'full output',
    resultSummary: 'done',
    isBackground: request.isBackground,
    startedAt: _fixedTime,
    finishedAt: _fixedTime.add(const Duration(seconds: 1)),
  );
}

final class _RuntimeStore {
  final Map<String, SubagentTask> tasks = {};

  SubagentTaskStoreAdapter get adapter => SubagentTaskStoreAdapter(
    lookupTask: lookup,
    registerTask: register,
    completeTask: complete,
    failTask: fail,
    markTaskNotified: markNotified,
  );

  static String key(ChatTurnOwner owner, String taskId) {
    return '${owner.conversationId}:${owner.interactionGeneration}:$taskId';
  }

  SubagentTask? lookup(ChatTurnOwner owner, String taskId) {
    return tasks[key(owner, taskId)];
  }

  bool register(ChatTurnOwner owner, SubagentTask task) {
    final taskKey = key(owner, task.id);
    if (tasks.containsKey(taskKey) || !task.isOwnedBy(owner)) return false;
    tasks[taskKey] = task;
    return true;
  }

  bool complete(
    ChatTurnOwner owner,
    String taskId, {
    required String output,
    required String summary,
  }) {
    final taskKey = key(owner, taskId);
    final task = tasks[taskKey];
    if (task == null || !task.isActive) return false;
    tasks[taskKey] = task.copyWith(
      status: SubagentTaskStatus.completed,
      output: output,
      resultSummary: summary,
      finishedAt: _fixedTime,
    );
    return true;
  }

  bool fail(ChatTurnOwner owner, String taskId, String error) {
    final taskKey = key(owner, taskId);
    final task = tasks[taskKey];
    if (task == null || !task.isActive) return false;
    tasks[taskKey] = task.copyWith(
      status: SubagentTaskStatus.failed,
      error: error,
      finishedAt: _fixedTime,
    );
    return true;
  }

  bool markNotified(ChatTurnOwner owner, String taskId) {
    final taskKey = key(owner, taskId);
    final task = tasks[taskKey];
    if (task == null || task.notified) return false;
    tasks[taskKey] = task.copyWith(notified: true);
    return true;
  }
}
