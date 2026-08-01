import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/subagent_tool_contract.dart';
import 'package:caverno/features/chat/domain/services/subagent_tool_handler.dart';
import 'package:test/test.dart';

final _fixedTime = DateTime.utc(2026, 7, 31, 9, 30);

ChatTurnOwner _owner(String conversationId, {int generation = 1}) =>
    ChatTurnOwner(
      conversationId: conversationId,
      interactionGeneration: generation,
    );

SubagentTaskIdentity _taskIdentity(
  ChatTurnOwner owner,
  String taskId, {
  String parentToolCallId = 'parent-call',
}) => SubagentTaskIdentity(
  owner: owner,
  parentToolCallId: parentToolCallId,
  taskId: taskId,
);

Map<String, dynamic> _tool(String name) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': '$name description',
    'parameters': <String, dynamic>{'type': 'object'},
  },
};

SubagentToolRequest _spawnRequest({
  ChatTurnOwner? owner,
  String id = 'parent-call',
  Map<String, dynamic> arguments = const {
    'description': 'Inspect the project',
    'prompt': 'Read the relevant files.',
  },
  List<Map<String, dynamic>> tools = const [],
}) => SubagentToolRequest(
  owner: owner ?? _owner('conversation-default'),
  toolCallId: id,
  toolName: 'spawn_subagent',
  arguments: arguments,
  parentToolDefinitions: tools,
);

SubagentToolRequest _resultRequest({
  ChatTurnOwner? owner,
  Object? taskId = 'task-1',
}) => SubagentToolRequest(
  owner: owner ?? _owner('conversation-default'),
  toolCallId: 'result-call',
  toolName: 'get_subagent_result',
  arguments: {'task_id': taskId},
);

SubagentTask _settledTask(
  SubagentExecutionRequest request, {
  SubagentTaskStatus status = SubagentTaskStatus.completed,
  ChatTurnOwner? owner,
  String? id,
  String? description,
  String output = 'full output',
  String summary = 'concise summary',
  String? error,
}) {
  final actualOwner = owner ?? request.key.owner;
  return SubagentTask(
    id: id ?? request.key.taskId,
    conversationId: actualOwner.conversationId,
    interactionGeneration: actualOwner.interactionGeneration,
    status: status,
    description: description ?? request.description,
    prompt: request.prompt,
    parentToolUseId: request.parentToolUseId,
    output: output,
    resultSummary: summary,
    isBackground: request.isBackground,
    startedAt: _fixedTime,
    finishedAt: _fixedTime.add(const Duration(seconds: 1)),
    error: error,
  );
}

void main() {
  group('Subagent request values', () {
    test('keys compare by exact owner and task identity', () {
      final ownerA = _owner('conversation-a', generation: 3);
      final same = SubagentTaskIdentity(
        owner: ownerA,
        parentToolCallId: 'parent-call',
        taskId: 'task-1',
      );
      final equal = SubagentTaskIdentity(
        owner: _owner('conversation-a', generation: 3),
        parentToolCallId: 'parent-call',
        taskId: 'task-1',
      );

      expect(same, equal);
      expect(same.hashCode, equal.hashCode);
      expect(
        same,
        isNot(
          SubagentTaskIdentity(
            owner: _owner('conversation-a', generation: 4),
            parentToolCallId: 'parent-call',
            taskId: 'task-1',
          ),
        ),
      );
      expect(
        same,
        isNot(
          SubagentTaskIdentity(
            owner: ownerA,
            parentToolCallId: 'parent-call',
            taskId: 'task-2',
          ),
        ),
      );
      expect(same, isNot('task-1'));
    });

    test('recursively freezes arguments and parent tool definitions', () {
      final labels = <Object?>['safe'];
      final flags = <Object?>['read'];
      final metadata = <String, Object?>{'labels': labels, 'flags': flags};
      final arguments = <String, dynamic>{
        'prompt': 'Original prompt',
        'metadata': metadata,
      };
      final parameters = <String, dynamic>{
        'required': <Object?>['path'],
      };
      final tools = <Map<String, dynamic>>[
        {
          'type': 'function',
          'function': <String, dynamic>{
            'name': 'read_file',
            'parameters': parameters,
          },
        },
      ];

      final request = _spawnRequest(
        owner: _owner('conversation-a'),
        arguments: arguments,
        tools: tools,
      );

      labels.add('poisoned');
      flags.add('write');
      metadata['labels'] = <Object?>['replaced'];
      arguments['prompt'] = 'Poisoned prompt';
      (parameters['required'] as List<Object?>).add('workspace');
      tools.add(_tool('run_command'));

      expect(request.arguments['prompt'], 'Original prompt');
      expect(request.arguments['metadata'], {
        'labels': ['safe'],
        'flags': {'read'},
      });
      expect(request.parentToolDefinitions, hasLength(1));
      expect(
        ((request.parentToolDefinitions.single['function']
                as Map<String, dynamic>)['parameters']
            as Map<String, dynamic>)['required'],
        ['path'],
      );
      expect(
        () => request.arguments['prompt'] = 'late',
        throwsUnsupportedError,
      );
      expect(
        () => (request.arguments['metadata'] as Map)['late'] = true,
        throwsUnsupportedError,
      );
      expect(
        () => ((request.arguments['metadata'] as Map)['labels'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => ((request.arguments['metadata'] as Map)['flags'] as List).add(
          'late',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => request.parentToolDefinitions.add(_tool('late')),
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((request.parentToolDefinitions.single['function']
                        as Map<String, dynamic>)['parameters']
                    as Map<String, dynamic>)['late'] =
                true,
        throwsUnsupportedError,
      );
      expect(
        () => _spawnRequest(
          owner: _owner('conversation-a'),
          arguments: {
            'prompt': 'work',
            'metadata': <Object?, Object?>{7: 'poison'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _spawnRequest(
          owner: _owner('conversation-a'),
          arguments: {'prompt': 'work', 'metadata': StringBuffer('mutable')},
        ),
        throwsArgumentError,
      );
      expect(
        () => _spawnRequest(
          owner: _owner('conversation-a'),
          arguments: {
            'prompt': 'work',
            'metadata': <Object?>{'not-json'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _spawnRequest(
          owner: _owner('conversation-a'),
          arguments: {'prompt': 'work', 'metadata': double.nan},
        ),
        throwsArgumentError,
      );
    });
  });

  group('SubagentToolHandler validation', () {
    test('requires exact invocation identity before handler execution', () {
      expect(
        () => _spawnRequest(owner: _owner('conversation-a'), id: ' '),
        throwsArgumentError,
      );
    });

    test('preserves prompt validation and side-effect ordering', () async {
      final fixture = _Fixture();

      for (final arguments in <Map<String, dynamic>>[
        const {},
        const {'prompt': null},
        const {'prompt': '   '},
      ]) {
        final result = await fixture.handler.handle(
          _spawnRequest(
            owner: _owner('conversation-a'),
            arguments: arguments,
            tools: [_tool('read_file')],
          ),
        );

        expect(result.toolName, 'spawn_subagent');
        expect(result.result, isEmpty);
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, 'prompt is required');
      }

      expect(fixture.taskIdCalls, 0);
      expect(fixture.execution.calls, isEmpty);
      expect(fixture.store.registerCalls, isEmpty);
      expect(fixture.child.calls, isEmpty);
      expect(fixture.notifications.calls, isEmpty);
    });

    test('preserves invalid string argument cast failures', () async {
      final fixture = _Fixture();
      final owner = _owner('conversation-a');

      await expectLater(
        fixture.handler.handle(
          _spawnRequest(
            owner: owner,
            arguments: const {'description': 7, 'prompt': 'work'},
          ),
        ),
        throwsA(isA<TypeError>()),
      );
      await expectLater(
        fixture.handler.handle(
          _spawnRequest(
            owner: owner,
            arguments: const {'description': 'work', 'prompt': 7},
          ),
        ),
        throwsA(isA<TypeError>()),
      );
      await expectLater(
        fixture.handler.handle(_resultRequest(owner: owner, taskId: 7)),
        throwsA(isA<TypeError>()),
      );

      expect(fixture.taskIdCalls, 0);
      expect(fixture.execution.calls, isEmpty);
    });

    test('returns exact missing task id failure', () async {
      final owner = _owner('conversation-a');
      final fixture = _Fixture();

      final missingId = await fixture.handler.handle(
        _resultRequest(owner: owner, taskId: '  '),
      );
      expect(missingId.toolName, 'get_subagent_result');
      expect(missingId.result, isEmpty);
      expect(missingId.isSuccess, isFalse);
      expect(missingId.errorMessage, 'task_id is required');
      expect(fixture.store.lookupCalls, isEmpty);
    });

    test('rejects unsupported handler bindings', () async {
      final fixture = _Fixture();
      expect(
        () => SubagentToolRequest(
          owner: _owner('conversation-a'),
          toolCallId: 'unknown-call',
          toolName: 'unknown_subagent_tool',
          arguments: const {},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.invalidValue,
            'invalidValue',
            'unknown_subagent_tool',
          ),
        ),
      );
      expect(fixture.execution.calls, isEmpty);
    });
  });

  group('SubagentToolHandler foreground execution', () {
    test('filters tools and returns the exact completed payload', () async {
      final owner = _owner('conversation-a', generation: 8);
      final fixture = _Fixture(ids: ['task-success']);
      fixture.child.result = const McpToolResult(
        toolName: 'read_file',
        result: 'file contents',
        isSuccess: true,
      );
      fixture.execution.onRun = (request, dispatch) async {
        expect(request.key.owner, owner);
        expect(request.key.taskId, 'task-success');
        expect(request.description, 'Inspect the project');
        expect(request.prompt, 'Read the relevant files.');
        expect(request.parentToolUseId, 'parent-call');
        expect(request.isBackground, isFalse);
        expect(
          request.tools.map(
            (tool) => (tool['function'] as Map<String, dynamic>)['name'],
          ),
          ['read_file', 'get_subagent_result'],
        );
        expect(request.allowedToolNames, {'read_file', 'get_subagent_result'});
        expect(
          () => request.allowedToolNames.add('late'),
          throwsUnsupportedError,
        );
        expect(() => request.tools.add(_tool('late')), throwsUnsupportedError);

        final childResult = await dispatch(
          ToolCallInfo(
            id: 'child-call',
            name: 'read_file',
            arguments: {
              'path': 'README.md',
              'nested': <String, dynamic>{
                'lines': <Object?>[1, 2],
              },
            },
          ),
        );
        expect(childResult.result, 'file contents');
        return _settledTask(request);
      };

      final result = await fixture.handler.handle(
        _spawnRequest(
          owner: owner,
          tools: [
            _tool('spawn_subagent'),
            _tool('read_file'),
            _tool('read_file'),
            _tool('get_subagent_result'),
          ],
        ),
      );

      expect(result.toolName, 'spawn_subagent');
      expect(
        result.result,
        '{"status":"completed","task_id":"task-success",'
        '"description":"Inspect the project","summary":"concise summary"}',
      );
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      expect(fixture.taskIdCalls, 1);
      expect(fixture.store.registerCalls, isEmpty);
      expect(fixture.child.calls, hasLength(1));
      expect(fixture.child.calls.single.owner, owner);
      expect(fixture.child.calls.single.request.id, 'child-call');
      expect(fixture.child.calls.single.request.name, 'read_file');
      expect(fixture.child.calls.single.request.arguments, {
        'path': 'README.md',
        'nested': {
          'lines': [1, 2],
        },
      });
      expect(fixture.child.calls.single.request.allowedToolNames, {
        'read_file',
        'get_subagent_result',
      });
      expect(
        () => fixture.child.calls.single.request.arguments['late'] = true,
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((fixture.child.calls.single.request.arguments['nested']
                        as Map<String, dynamic>)['lines']
                    as List<Object?>)
                .add(3),
        throwsUnsupportedError,
      );
    });

    test(
      'uses the legacy description default and strict background flag',
      () async {
        final fixture = _Fixture(ids: ['task-default', 'task-not-boolean']);

        final defaultResult = await fixture.handler.handle(
          _spawnRequest(
            owner: _owner('conversation-a'),
            arguments: const {'description': '  ', 'prompt': '  Work now.  '},
          ),
        );
        final nonBooleanResult = await fixture.handler.handle(
          _spawnRequest(
            owner: _owner('conversation-a'),
            arguments: const {
              'description': 'Named',
              'prompt': 'Work',
              'background': 1,
            },
          ),
        );

        expect(jsonDecode(defaultResult.result), {
          'status': 'completed',
          'task_id': 'task-default',
          'description': 'Subagent task',
          'summary': 'concise summary',
        });
        expect(
          fixture.execution.calls.first.request.description,
          'Subagent task',
        );
        expect(fixture.execution.calls.first.request.prompt, 'Work now.');
        expect(fixture.execution.calls.first.request.isBackground, isFalse);
        expect(
          jsonDecode(nonBooleanResult.result)['task_id'],
          'task-not-boolean',
        );
        expect(fixture.execution.calls.last.request.isBackground, isFalse);
        expect(fixture.store.registerCalls, isEmpty);
      },
    );

    test('returns exact explicit and fallback execution failures', () async {
      final fixture = _Fixture(ids: ['task-explicit', 'task-fallback']);
      var call = 0;
      fixture.execution.onRun = (request, dispatch) async {
        call += 1;
        return _settledTask(
          request,
          status: SubagentTaskStatus.failed,
          description: call == 1 ? 'Returned description' : request.description,
          error: call == 1 ? 'execution failed' : null,
        );
      };

      final explicit = await fixture.handler.handle(
        _spawnRequest(owner: _owner('conversation-a')),
      );
      final fallback = await fixture.handler.handle(
        _spawnRequest(owner: _owner('conversation-a')),
      );

      expect(
        explicit.result,
        '{"status":"failed","task_id":"task-explicit",'
        '"description":"Returned description","error":"execution failed"}',
      );
      expect(explicit.isSuccess, isFalse);
      expect(explicit.errorMessage, 'execution failed');
      expect(
        fallback.result,
        '{"status":"failed","task_id":"task-fallback",'
        '"description":"Inspect the project","error":"Subagent failed"}',
      );
      expect(fallback.isSuccess, isFalse);
      expect(fallback.errorMessage, 'Subagent failed');
    });

    test('rejects mismatched result task and owner identities', () async {
      final ownerA = _owner('conversation-a', generation: 2);
      final ownerB = _owner('conversation-b', generation: 2);
      final fixture = _Fixture(ids: ['expected-id', 'expected-owner']);
      var call = 0;
      fixture.execution.onRun = (request, dispatch) async {
        call += 1;
        return _settledTask(
          request,
          id: call == 1 ? 'wrong-id' : null,
          owner: call == 1 ? ownerA : ownerB,
        );
      };

      final wrongId = await fixture.handler.handle(
        _spawnRequest(owner: ownerA),
      );
      final wrongOwner = await fixture.handler.handle(
        _spawnRequest(owner: ownerA),
      );

      for (final result in [wrongId, wrongOwner]) {
        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'Subagent execution returned a mismatched task identity',
        );
      }
      expect(jsonDecode(wrongId.result), {
        'status': 'failed',
        'task_id': 'expected-id',
        'description': 'Inspect the project',
        'error': 'Subagent execution returned a mismatched task identity',
      });
      expect(jsonDecode(wrongOwner.result)['task_id'], 'expected-owner');
    });

    test('denies nested and unavailable child tools without dispatch', () async {
      final fixture = _Fixture();
      fixture.execution.onRun = (request, dispatch) async {
        final nestedSpawn = await dispatch(
          ToolCallInfo(
            id: 'nested-spawn',
            name: 'spawn_subagent',
            arguments: const {'prompt': 'fan out'},
          ),
        );
        final nestedResult = await dispatch(
          ToolCallInfo(
            id: 'nested-result',
            name: 'get_subagent_result',
            arguments: const {'task_id': 'other'},
          ),
        );
        final unavailable = await dispatch(
          ToolCallInfo(
            id: 'unavailable',
            name: 'write_file',
            arguments: const {'path': 'out.txt'},
          ),
        );

        for (final denial in [nestedSpawn, nestedResult]) {
          expect(denial.result, isEmpty);
          expect(denial.isSuccess, isFalse);
          expect(
            denial.errorMessage,
            'Nested subagents are not allowed. Finish this sub-task directly.',
          );
        }
        expect(unavailable.toolName, 'write_file');
        expect(unavailable.result, isEmpty);
        expect(unavailable.isSuccess, isFalse);
        expect(
          unavailable.errorMessage,
          'Tool write_file is not available to this subagent.',
        );
        return _settledTask(request);
      };

      final result = await fixture.handler.handle(
        _spawnRequest(
          owner: _owner('conversation-a'),
          tools: [_tool('read_file'), _tool('get_subagent_result')],
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(fixture.child.calls, isEmpty);
    });

    test(
      'surfaces an allowed child execution error to the execution port',
      () async {
        final fixture = _Fixture();
        fixture.child.error = StateError('child boom');
        fixture.execution.onRun = (request, dispatch) async {
          String? childError;
          try {
            await dispatch(
              ToolCallInfo(
                id: 'child-error',
                name: 'read_file',
                arguments: const {'path': 'README.md'},
              ),
            );
          } catch (error) {
            childError = error.toString();
          }
          return _settledTask(
            request,
            status: SubagentTaskStatus.failed,
            error: childError,
          );
        };

        final result = await fixture.handler.handle(
          _spawnRequest(
            owner: _owner('conversation-a'),
            tools: [_tool('read_file')],
          ),
        );

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, 'Bad state: child boom');
        expect(fixture.child.calls, hasLength(1));
      },
    );

    test(
      'warns when a child completion belongs to another parent call',
      () async {
        final owner = _owner('conversation-a');
        final fixture = _Fixture();
        fixture.execution.onRun = (request, dispatch) async {
          fixture.child.completionRequest = ChildToolExecutionRequest(
            taskIdentity: _taskIdentity(
              owner,
              'peer-task',
              parentToolCallId: 'peer-call',
            ),
            id: 'child-call',
            name: 'read_file',
            arguments: const {'path': 'README.md'},
            allowedToolNames: const {'read_file'},
          );
          final child = await dispatch(
            ToolCallInfo(
              id: 'child-call',
              name: 'read_file',
              arguments: const {'path': 'README.md'},
            ),
          );
          return _settledTask(
            request,
            status: SubagentTaskStatus.failed,
            error: child.errorMessage,
          );
        };

        final result = await fixture.handler.handle(
          _spawnRequest(owner: owner, tools: [_tool('read_file')]),
        );

        expect(
          result.errorMessage,
          'Subagent execution outcome is uncertain; inspect possible child-tool '
          'side effects before retrying',
        );
      },
    );

    test('warns when the exact owner retires during foreground work', () async {
      final fixture = _Fixture();
      fixture.execution.onRun = (request, dispatch) async {
        fixture.lifecycle.retiredTasks.add(request.identity);
        return _settledTask(request);
      };

      final result = await fixture.handler.handle(
        _spawnRequest(owner: _owner('conversation-a')),
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'Subagent execution outcome is uncertain; inspect possible child-tool '
        'side effects before retrying',
      );
    });
  });

  group('SubagentToolHandler background execution', () {
    test(
      'registers before execution and returns the exact started payload',
      () async {
        final owner = _owner('conversation-a', generation: 5);
        final execution = Completer<SubagentTask>();
        final fixture = _Fixture(ids: ['background-1']);
        fixture.execution.onRun = (request, dispatch) => execution.future;

        final result = await fixture.handler.handle(
          _spawnRequest(
            owner: owner,
            id: 'parent-background',
            arguments: const {
              'description': '  Background inspection  ',
              'prompt': '  Inspect asynchronously.  ',
              'background': true,
            },
            tools: [_tool('read_file')],
          ),
        );

        expect(
          result.result,
          '{"status":"started","task_id":"background-1",'
          '"description":"Background inspection","note":'
          '"The subagent is running in the background. Call '
          'get_subagent_result with this task_id to retrieve the result '
          'once it finishes."}',
        );
        expect(result.isSuccess, isTrue);
        expect(fixture.store.registerCalls, hasLength(1));
        final registration = fixture.store.registerCalls.single;
        expect(registration.key.owner, owner);
        expect(registration.key.taskId, 'background-1');
        expect(registration.task.id, 'background-1');
        expect(registration.task.conversationId, 'conversation-a');
        expect(registration.task.interactionGeneration, 5);
        expect(registration.task.status, SubagentTaskStatus.running);
        expect(registration.task.description, 'Background inspection');
        expect(registration.task.prompt, 'Inspect asynchronously.');
        expect(registration.task.parentToolUseId, 'parent-background');
        expect(registration.task.isBackground, isTrue);
        expect(registration.task.startedAt, _fixedTime);
        expect(fixture.execution.calls, hasLength(1));
        expect(fixture.execution.calls.single.request.isBackground, isTrue);

        fixture.store.remove(registration.key);
        execution.complete(_settledTask(_registrationToRequest(registration)));
        await _drainAsyncWork();
      },
    );

    test(
      'settles a thrown background execution instead of leaving it running',
      () async {
        final owner = _owner('conversation-a');
        final fixture = _Fixture(ids: ['throwing-task']);
        fixture.execution.onRun = (request, dispatch) async {
          throw StateError('background boom');
        };

        await fixture.handler.handle(
          _spawnRequest(
            owner: owner,
            arguments: const {'prompt': 'Work', 'background': true},
          ),
        );
        await _drainAsyncWork();

        final task = fixture.store.tasks[_taskIdentity(owner, 'throwing-task')];
        expect(task?.status, SubagentTaskStatus.failed);
        expect(task?.error, 'Bad state: background boom');
        expect(task?.notified, isTrue);
      },
    );

    test('rejects a duplicate task id from a concurrent parent call', () async {
      final owner = _owner('conversation-a');
      final firstRun = Completer<SubagentTask>();
      final fixture = _Fixture(ids: ['shared-task', 'shared-task']);
      fixture.execution.onRun = (request, dispatch) => firstRun.future;

      final first = await fixture.handler.handle(
        _spawnRequest(
          owner: owner,
          id: 'parent-a',
          arguments: const {'prompt': 'Work', 'background': true},
        ),
      );
      final second = await fixture.handler.handle(
        _spawnRequest(
          owner: owner,
          id: 'parent-b',
          arguments: const {'prompt': 'Work', 'background': true},
        ),
      );

      expect(first.isSuccess, isTrue);
      expect(second.isSuccess, isFalse);
      expect(second.errorMessage, 'Subagent task registration failed');
      expect(fixture.execution.calls, hasLength(1));
      final request = fixture.execution.calls.single.request;
      firstRun.complete(_settledTask(request));
      await _drainAsyncWork();
    });

    test(
      'completes only the exact owner and truncates success notification',
      () async {
        final ownerA = _owner('conversation-a', generation: 7);
        final ownerB = _owner('conversation-b', generation: 7);
        final longSummary = List.filled(210, 'x').join();
        final execution = Completer<SubagentTask>();
        final fixture = _Fixture(ids: ['shared-task']);
        fixture.execution.onRun = (request, dispatch) => execution.future;
        fixture.store.register(
          _taskIdentity(ownerB, 'shared-task'),
          _storedTask(
            ownerB,
            id: 'shared-task',
            status: SubagentTaskStatus.completed,
            summary: 'owner-b summary',
          ),
        );

        await fixture.handler.handle(
          _spawnRequest(
            owner: ownerA,
            arguments: const {'prompt': 'Work', 'background': true},
          ),
        );
        final request = fixture.execution.calls.single.request;
        execution.complete(
          _settledTask(request, output: 'owner-a output', summary: longSummary),
        );
        await _drainAsyncWork();

        final taskA = fixture.store.tasks[_taskIdentity(ownerA, 'shared-task')];
        final taskB = fixture.store.tasks[_taskIdentity(ownerB, 'shared-task')];
        expect(taskA?.status, SubagentTaskStatus.completed);
        expect(taskA?.output, 'owner-a output');
        expect(taskA?.resultSummary, longSummary);
        expect(taskA?.notified, isTrue);
        expect(taskB?.status, SubagentTaskStatus.completed);
        expect(taskB?.resultSummary, 'owner-b summary');
        expect(taskB?.notified, isFalse);
        expect(fixture.store.completeCalls.single.key.owner, ownerA);
        expect(fixture.notifications.calls, hasLength(1));
        final notification = fixture.notifications.calls.single;
        expect(notification.owner, ownerA);
        expect(notification.notification.taskId, 'shared-task');
        expect(notification.notification.description, 'Subagent task');
        expect(notification.notification.isSuccessful, isTrue);
        expect(
          notification.notification.body,
          '${longSummary.substring(0, 200)}...',
        );
      },
    );

    test('stores failure and emits exact failure notification', () async {
      final owner = _owner('conversation-a');
      final execution = Completer<SubagentTask>();
      final fixture = _Fixture(ids: ['background-failure']);
      fixture.execution.onRun = (request, dispatch) => execution.future;

      await fixture.handler.handle(
        _spawnRequest(
          owner: owner,
          arguments: const {
            'description': 'Failing task',
            'prompt': 'Try work',
            'background': true,
          },
        ),
      );
      execution.complete(
        _settledTask(
          fixture.execution.calls.single.request,
          status: SubagentTaskStatus.failed,
          error: 'remote execution failed',
        ),
      );
      await _drainAsyncWork();

      final task =
          fixture.store.tasks[_taskIdentity(owner, 'background-failure')];
      expect(task?.status, SubagentTaskStatus.failed);
      expect(task?.error, 'remote execution failed');
      expect(task?.notified, isTrue);
      expect(fixture.store.failCalls.single.error, 'remote execution failed');
      final notification = fixture.notifications.calls.single.notification;
      expect(notification.isSuccessful, isFalse);
      expect(notification.body, 'remote execution failed');
    });

    test(
      'uses fallback failure text and swallows notification errors',
      () async {
        final owner = _owner('conversation-a');
        final execution = Completer<SubagentTask>();
        final fixture = _Fixture(ids: ['background-fallback']);
        fixture.execution.onRun = (request, dispatch) => execution.future;
        fixture.notifications.error = StateError('notifications disabled');

        await fixture.handler.handle(
          _spawnRequest(
            owner: owner,
            arguments: const {'prompt': 'Try work', 'background': true},
          ),
        );
        execution.complete(
          _settledTask(
            fixture.execution.calls.single.request,
            status: SubagentTaskStatus.failed,
            error: null,
          ),
        );
        await _drainAsyncWork();

        final key = _taskIdentity(owner, 'background-fallback');
        expect(fixture.store.tasks[key]?.error, 'Subagent failed');
        expect(fixture.store.tasks[key]?.notified, isFalse);
        expect(
          fixture.notifications.calls.single.notification.body,
          'Subagent failed',
        );
        expect(fixture.store.markNotifiedCalls, isEmpty);
      },
    );

    test('uses Completed fallback for an empty successful summary', () async {
      final execution = Completer<SubagentTask>();
      final fixture = _Fixture(ids: ['empty-summary']);
      fixture.execution.onRun = (request, dispatch) => execution.future;

      await fixture.handler.handle(
        _spawnRequest(
          owner: _owner('conversation-a'),
          arguments: const {'prompt': 'Work', 'background': true},
        ),
      );
      execution.complete(
        _settledTask(
          fixture.execution.calls.single.request,
          output: '',
          summary: '',
        ),
      );
      await _drainAsyncWork();

      expect(
        fixture.notifications.calls.single.notification.body,
        'Completed.',
      );
    });

    test('drops late completion after cancellation', () async {
      final owner = _owner('conversation-a');
      final execution = Completer<SubagentTask>();
      final fixture = _Fixture(ids: ['cancelled-task']);
      fixture.execution.onRun = (request, dispatch) => execution.future;

      await fixture.handler.handle(
        _spawnRequest(
          owner: owner,
          arguments: const {'prompt': 'Work', 'background': true},
        ),
      );
      final key = _taskIdentity(owner, 'cancelled-task');
      fixture.store.cancel(key);
      execution.complete(_settledTask(fixture.execution.calls.single.request));
      await _drainAsyncWork();

      expect(fixture.store.tasks[key]?.status, SubagentTaskStatus.cancelled);
      expect(fixture.store.completeCalls, isEmpty);
      expect(fixture.store.failCalls, isEmpty);
      expect(fixture.notifications.calls, isEmpty);
      expect(fixture.store.markNotifiedCalls, isEmpty);
    });

    test(
      'drops removed completion and never runs a rejected registration',
      () async {
        final owner = _owner('conversation-a');
        final removedExecution = Completer<SubagentTask>();
        final removed = _Fixture(ids: ['removed-task']);
        removed.execution.onRun = (request, dispatch) =>
            removedExecution.future;

        await removed.handler.handle(
          _spawnRequest(
            owner: owner,
            arguments: const {'prompt': 'Work', 'background': true},
          ),
        );
        final removedRequest = removed.execution.calls.single.request;
        removed.store.remove(removedRequest.key);
        removedExecution.complete(_settledTask(removedRequest));
        await _drainAsyncWork();

        expect(removed.store.completeCalls, isEmpty);
        expect(removed.notifications.calls, isEmpty);

        final rejected = _Fixture(ids: ['rejected-task']);
        rejected.store.rejectRegistrations = true;

        final result = await rejected.handler.handle(
          _spawnRequest(
            owner: owner,
            arguments: const {'prompt': 'Work', 'background': true},
          ),
        );
        expect(result.isSuccess, isFalse);
        expect(jsonDecode(result.result), {
          'status': 'failed',
          'task_id': 'rejected-task',
          'description': 'Subagent task',
          'error': 'Subagent task registration failed',
        });
        expect(result.errorMessage, 'Subagent task registration failed');
        expect(rejected.store.registerCalls, hasLength(1));
        expect(rejected.execution.calls, isEmpty);
        expect(rejected.store.tasks, isEmpty);
        expect(rejected.store.completeCalls, isEmpty);
        expect(rejected.notifications.calls, isEmpty);
      },
    );

    test('fails and notifies on a mismatched background identity', () async {
      final owner = _owner('conversation-a');
      final execution = Completer<SubagentTask>();
      final fixture = _Fixture(ids: ['expected-task']);
      fixture.execution.onRun = (request, dispatch) => execution.future;

      await fixture.handler.handle(
        _spawnRequest(
          owner: owner,
          arguments: const {'prompt': 'Work', 'background': true},
        ),
      );
      execution.complete(
        _settledTask(
          fixture.execution.calls.single.request,
          owner: _owner('conversation-b'),
        ),
      );
      await _drainAsyncWork();

      final task = fixture.store.tasks[_taskIdentity(owner, 'expected-task')];
      expect(task?.status, SubagentTaskStatus.failed);
      expect(
        task?.error,
        'Subagent execution returned a mismatched task identity',
      );
      expect(fixture.notifications.calls.single.owner, owner);
      expect(
        fixture.notifications.calls.single.notification.body,
        'Subagent execution returned a mismatched task identity',
      );
    });

    test('does not notify a task already marked notified', () async {
      final owner = _owner('conversation-a');
      final execution = Completer<SubagentTask>();
      final fixture = _Fixture(ids: ['pre-notified']);
      fixture.execution.onRun = (request, dispatch) => execution.future;

      await fixture.handler.handle(
        _spawnRequest(
          owner: owner,
          arguments: const {'prompt': 'Work', 'background': true},
        ),
      );
      final key = _taskIdentity(owner, 'pre-notified');
      fixture.store.markNotified(key);
      fixture.store.markNotifiedCalls.clear();
      execution.complete(_settledTask(fixture.execution.calls.single.request));
      await _drainAsyncWork();

      expect(fixture.store.tasks[key]?.status, SubagentTaskStatus.completed);
      expect(fixture.notifications.calls, isEmpty);
      expect(fixture.store.markNotifiedCalls, isEmpty);
    });

    test(
      'does not acknowledge a notification for another exact task',
      () async {
        final owner = _owner('conversation-a');
        final execution = Completer<SubagentTask>();
        final fixture = _Fixture(ids: ['notification-task']);
        fixture.execution.onRun = (request, dispatch) => execution.future;

        await fixture.handler.handle(
          _spawnRequest(
            owner: owner,
            arguments: const {'prompt': 'Work', 'background': true},
          ),
        );
        fixture.notifications.receiptIdentity = _taskIdentity(
          owner,
          'peer-task',
          parentToolCallId: 'peer-call',
        );
        execution.complete(
          _settledTask(fixture.execution.calls.single.request),
        );
        await _drainAsyncWork();

        final task =
            fixture.store.tasks[_taskIdentity(owner, 'notification-task')];
        expect(task?.status, SubagentTaskStatus.completed);
        expect(task?.notified, isFalse);
        expect(fixture.store.markNotifiedCalls, isEmpty);
      },
    );

    test(
      'drops completion and notification after exact task retirement',
      () async {
        final owner = _owner('conversation-a');
        final execution = Completer<SubagentTask>();
        final fixture = _Fixture(ids: ['retired-task']);
        fixture.execution.onRun = (request, dispatch) => execution.future;

        await fixture.handler.handle(
          _spawnRequest(
            owner: owner,
            arguments: const {'prompt': 'Work', 'background': true},
          ),
        );
        final request = fixture.execution.calls.single.request;
        fixture.lifecycle.retiredTasks.add(request.identity);
        execution.complete(_settledTask(request));
        await _drainAsyncWork();

        expect(
          fixture.store.tasks[request.identity]?.status,
          SubagentTaskStatus.running,
        );
        expect(fixture.store.completeCalls, isEmpty);
        expect(fixture.notifications.calls, isEmpty);
      },
    );
  });

  group('SubagentToolHandler result lookup', () {
    test('missing result cannot be satisfied by another owner', () async {
      final ownerA = _owner('conversation-a', generation: 4);
      final ownerB = _owner('conversation-b', generation: 4);
      final ownerANextGeneration = _owner('conversation-a', generation: 5);
      final fixture = _Fixture();
      fixture.store.register(
        _taskIdentity(ownerB, 'shared-task'),
        _storedTask(
          ownerB,
          id: 'shared-task',
          status: SubagentTaskStatus.completed,
          summary: 'owner-b result',
        ),
      );
      fixture.store.register(
        _taskIdentity(ownerANextGeneration, 'shared-task'),
        _storedTask(
          ownerANextGeneration,
          id: 'shared-task',
          status: SubagentTaskStatus.completed,
          summary: 'next-generation result',
        ),
      );

      final result = await fixture.handler.handle(
        _resultRequest(owner: ownerA, taskId: ' shared-task '),
      );

      expect(result.toolName, 'get_subagent_result');
      expect(result.result, '{"status":"not_found","task_id":"shared-task"}');
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'No subagent task with id shared-task');
      expect(fixture.store.lookupCalls.single.taskId, 'shared-task');
    });

    test('returns exact pending, running, and cancelled payloads', () async {
      final owner = _owner('conversation-a');
      final fixture = _Fixture();
      for (final entry in <(String, SubagentTaskStatus)>[
        ('pending-task', SubagentTaskStatus.pending),
        ('running-task', SubagentTaskStatus.running),
        ('cancelled-task', SubagentTaskStatus.cancelled),
      ]) {
        fixture.store.register(
          _taskIdentity(owner, entry.$1),
          _storedTask(owner, id: entry.$1, status: entry.$2),
        );
      }

      final pending = await fixture.handler.handle(
        _resultRequest(owner: owner, taskId: 'pending-task'),
      );
      final running = await fixture.handler.handle(
        _resultRequest(owner: owner, taskId: 'running-task'),
      );
      final cancelled = await fixture.handler.handle(
        _resultRequest(owner: owner, taskId: 'cancelled-task'),
      );

      expect(
        pending.result,
        '{"task_id":"pending-task","description":"Stored task",'
        '"status":"pending","note":"Still running. Check again shortly."}',
      );
      expect(pending.isSuccess, isTrue);
      expect(
        running.result,
        '{"task_id":"running-task","description":"Stored task",'
        '"status":"running","note":"Still running. Check again shortly."}',
      );
      expect(running.isSuccess, isTrue);
      expect(
        cancelled.result,
        '{"task_id":"cancelled-task","description":"Stored task",'
        '"status":"cancelled"}',
      );
      expect(cancelled.isSuccess, isTrue);
    });

    test('returns exact completed and failed payloads', () async {
      final owner = _owner('conversation-a');
      final fixture = _Fixture();
      fixture.store.register(
        _taskIdentity(owner, 'completed-task'),
        _storedTask(
          owner,
          id: 'completed-task',
          status: SubagentTaskStatus.completed,
          summary: 'Finished inspection',
        ),
      );
      fixture.store.register(
        _taskIdentity(owner, 'failed-task'),
        _storedTask(
          owner,
          id: 'failed-task',
          status: SubagentTaskStatus.failed,
          error: 'Network unavailable',
        ),
      );
      fixture.store.register(
        _taskIdentity(owner, 'fallback-failure'),
        _storedTask(
          owner,
          id: 'fallback-failure',
          status: SubagentTaskStatus.failed,
        ),
      );

      final completed = await fixture.handler.handle(
        _resultRequest(owner: owner, taskId: 'completed-task'),
      );
      final failed = await fixture.handler.handle(
        _resultRequest(owner: owner, taskId: 'failed-task'),
      );
      final fallback = await fixture.handler.handle(
        _resultRequest(owner: owner, taskId: 'fallback-failure'),
      );

      expect(
        completed.result,
        '{"task_id":"completed-task","description":"Stored task",'
        '"status":"completed","summary":"Finished inspection"}',
      );
      expect(completed.isSuccess, isTrue);
      expect(
        failed.result,
        '{"task_id":"failed-task","description":"Stored task",'
        '"status":"failed","error":"Network unavailable"}',
      );
      expect(failed.isSuccess, isFalse);
      expect(failed.errorMessage, isNull);
      expect(
        fallback.result,
        '{"task_id":"fallback-failure","description":"Stored task",'
        '"status":"failed","error":"Subagent failed"}',
      );
      expect(fallback.isSuccess, isFalse);
    });
  });
}

SubagentExecutionRequest _registrationToRequest(_Registration registration) {
  return SubagentExecutionRequest(
    identity: registration.key,
    description: registration.task.description,
    prompt: registration.task.prompt,
    tools: const [],
    allowedToolNames: const {},
    isBackground: registration.task.isBackground,
  );
}

SubagentTask _storedTask(
  ChatTurnOwner owner, {
  required String id,
  required SubagentTaskStatus status,
  String summary = '',
  String? error,
}) => SubagentTask(
  id: id,
  conversationId: owner.conversationId,
  interactionGeneration: owner.interactionGeneration,
  status: status,
  description: 'Stored task',
  prompt: 'Stored prompt',
  parentToolUseId: 'parent-call',
  resultSummary: summary,
  error: error,
  isBackground: true,
  startedAt: _fixedTime,
);

Future<void> _drainAsyncWork() async {
  for (var index = 0; index < 4; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

typedef _RunBehavior =
    Future<SubagentTask> Function(
      SubagentExecutionRequest request,
      SubagentChildToolDispatcher dispatch,
    );

final class _Fixture {
  _Fixture({List<String> ids = const ['task-1']})
    : _ids = List<String>.of(ids) {
    handler = SubagentToolHandler(
      taskStore: store,
      executionPort: execution,
      childToolExecutionPort: child,
      notificationPort: notifications,
      ownerLifecyclePort: lifecycle,
      toolCatalogPort: toolCatalog,
      taskIdFactory: () {
        taskIdCalls += 1;
        return _ids.removeAt(0);
      },
      clock: () => _fixedTime,
    );
  }

  final List<String> _ids;
  final _TaskStore store = _TaskStore();
  final _ExecutionPort execution = _ExecutionPort();
  final _ChildExecutionPort child = _ChildExecutionPort();
  final _NotificationPort notifications = _NotificationPort();
  final _OwnerLifecyclePort lifecycle = _OwnerLifecyclePort();
  final _ToolCatalogPort toolCatalog = _ToolCatalogPort();
  late final SubagentToolHandler handler;
  int taskIdCalls = 0;
}

final class _ExecutionCall {
  const _ExecutionCall(this.request, this.dispatch);

  final SubagentExecutionRequest request;
  final SubagentChildToolDispatcher dispatch;
}

final class _ExecutionPort implements SubagentExecutionPort {
  final List<_ExecutionCall> calls = [];
  _RunBehavior? onRun;
  SubagentTaskIdentity? completionIdentity;

  @override
  Future<SubagentExecutionCompletion> run(
    SubagentExecutionRequest request, {
    required SubagentChildToolDispatcher dispatchToolCall,
  }) async {
    calls.add(_ExecutionCall(request, dispatchToolCall));
    final behavior = onRun;
    final task = behavior == null
        ? _settledTask(request)
        : await behavior(request, dispatchToolCall);
    return SubagentExecutionCompletion(
      identity: completionIdentity ?? request.identity,
      task: task,
    );
  }
}

final class _ChildExecutionCall {
  const _ChildExecutionCall(this.owner, this.request);

  final ChatTurnOwner owner;
  final ChildToolExecutionRequest request;
}

final class _ChildExecutionPort implements ChildToolExecutionPort {
  final List<_ChildExecutionCall> calls = [];
  McpToolResult result = const McpToolResult(
    toolName: 'child',
    result: 'child result',
    isSuccess: true,
  );
  Object? error;
  ChildToolExecutionRequest? completionRequest;

  @override
  Future<ChildToolExecutionCompletion> execute(
    ChildToolExecutionRequest request,
  ) {
    calls.add(_ChildExecutionCall(request.taskIdentity.owner, request));
    final failure = error;
    if (failure != null) {
      return Future.error(failure);
    }
    return Future.value(
      ChildToolExecutionCompletion(
        request: completionRequest ?? request,
        result: result,
      ),
    );
  }
}

final class _NotificationCall {
  const _NotificationCall(this.owner, this.notification);

  final ChatTurnOwner owner;
  final SubagentCompletionNotification notification;
}

final class _NotificationPort implements SubagentNotificationPort {
  final List<_NotificationCall> calls = [];
  Object? error;
  SubagentTaskIdentity? receiptIdentity;
  SubagentTransitionDisposition disposition =
      SubagentTransitionDisposition.accepted;

  @override
  Future<SubagentTransitionReceipt> notify(
    SubagentTaskIdentity identity,
    SubagentCompletionNotification notification,
  ) {
    calls.add(_NotificationCall(identity.owner, notification));
    final failure = error;
    if (failure != null) {
      return Future.error(failure);
    }
    return Future.value(
      SubagentTransitionReceipt(
        identity: receiptIdentity ?? identity,
        disposition: disposition,
      ),
    );
  }
}

final class _OwnerLifecyclePort implements SubagentOwnerLifecyclePort {
  final Set<SubagentTaskIdentity> retiredTasks = {};
  final Set<String> retiredLookupCalls = {};

  @override
  bool isCurrent(SubagentTaskIdentity identity) =>
      !retiredTasks.contains(identity);

  @override
  bool isLookupCurrent(SubagentResultLookup lookup) =>
      !retiredLookupCalls.contains(lookup.invocation.toolCallId);
}

final class _ToolCatalogPort implements SubagentToolCatalogPort {
  @override
  List<Map<String, dynamic>> filterInherited(
    List<Map<String, dynamic>> parentDefinitions,
  ) {
    final names = <String>{};
    return [
      for (final tool in parentDefinitions)
        if (toolName(tool) != spawnSubagentToolName &&
            names.add(toolName(tool)))
          tool,
    ];
  }

  @override
  String toolName(Map<String, dynamic> tool) {
    final function = tool['function'];
    if (function is Map<String, dynamic>) {
      return function['name'] as String? ?? '';
    }
    return tool['name'] as String? ?? '';
  }
}

final class _Registration {
  const _Registration(this.key, this.task);

  final SubagentTaskIdentity key;
  final SubagentTask task;
}

final class _Completion {
  const _Completion(this.key, this.output, this.summary);

  final SubagentTaskIdentity key;
  final String output;
  final String summary;
}

final class _Failure {
  const _Failure(this.key, this.error);

  final SubagentTaskIdentity key;
  final String error;
}

final class _TaskStore implements SubagentTaskStorePort {
  final Map<SubagentTaskIdentity, SubagentTask> tasks = {};
  final List<_Registration> registerCalls = [];
  final List<SubagentResultLookup> lookupCalls = [];
  final List<SubagentTaskIdentity> lookupExactCalls = [];
  final List<_Completion> completeCalls = [];
  final List<_Failure> failCalls = [];
  final List<SubagentTaskIdentity> markNotifiedCalls = [];
  bool rejectRegistrations = false;
  SubagentTransitionDisposition transitionDisposition =
      SubagentTransitionDisposition.accepted;
  SubagentTaskIdentity? receiptIdentity;

  @override
  SubagentTransitionReceipt register(
    SubagentTaskIdentity identity,
    SubagentTask task,
  ) {
    registerCalls.add(_Registration(identity, task));
    final duplicate = tasks.keys.any(
      (key) => key.owner == identity.owner && key.taskId == identity.taskId,
    );
    if (!rejectRegistrations && !duplicate) {
      tasks[identity] = task;
    }
    return _receipt(
      identity,
      rejectRegistrations || duplicate
          ? SubagentTransitionDisposition.rejected
          : transitionDisposition,
    );
  }

  @override
  SubagentTaskSnapshot? lookupExact(SubagentTaskIdentity identity) {
    lookupExactCalls.add(identity);
    final task = tasks[identity];
    return task == null
        ? null
        : SubagentTaskSnapshot(identity: identity, task: task);
  }

  @override
  SubagentResultSnapshot? lookupResult(SubagentResultLookup lookup) {
    lookupCalls.add(lookup);
    for (final entry in tasks.entries) {
      if (entry.key.owner == lookup.invocation.owner &&
          entry.key.taskId == lookup.taskId) {
        return SubagentResultSnapshot(
          lookup: lookup,
          taskIdentity: entry.key,
          task: entry.value,
        );
      }
    }
    return null;
  }

  @override
  SubagentTransitionReceipt complete(
    SubagentTaskIdentity key, {
    required String output,
    required String summary,
  }) {
    completeCalls.add(_Completion(key, output, summary));
    final task = tasks[key];
    if (task == null || !task.isActive) {
      return _receipt(key, SubagentTransitionDisposition.rejected);
    }
    tasks[key] = task.copyWith(
      status: SubagentTaskStatus.completed,
      output: output,
      resultSummary: summary,
      finishedAt: _fixedTime.add(const Duration(seconds: 1)),
    );
    return _receipt(key, transitionDisposition);
  }

  @override
  SubagentTransitionReceipt fail(SubagentTaskIdentity key, String error) {
    failCalls.add(_Failure(key, error));
    final task = tasks[key];
    if (task == null || !task.isActive) {
      return _receipt(key, SubagentTransitionDisposition.rejected);
    }
    tasks[key] = task.copyWith(
      status: SubagentTaskStatus.failed,
      error: error,
      finishedAt: _fixedTime.add(const Duration(seconds: 1)),
    );
    return _receipt(key, transitionDisposition);
  }

  @override
  SubagentTransitionReceipt markNotified(SubagentTaskIdentity key) {
    markNotifiedCalls.add(key);
    final task = tasks[key];
    if (task == null || task.notified) {
      return _receipt(key, SubagentTransitionDisposition.rejected);
    }
    tasks[key] = task.copyWith(notified: true);
    return _receipt(key, transitionDisposition);
  }

  void cancel(SubagentTaskIdentity key) {
    final task = tasks[key]!;
    tasks[key] = task.copyWith(
      status: SubagentTaskStatus.cancelled,
      finishedAt: _fixedTime,
    );
  }

  void remove(SubagentTaskIdentity key) {
    tasks.remove(key);
  }

  SubagentTransitionReceipt _receipt(
    SubagentTaskIdentity identity,
    SubagentTransitionDisposition disposition,
  ) => SubagentTransitionReceipt(
    identity: receiptIdentity ?? identity,
    disposition: disposition,
  );
}
