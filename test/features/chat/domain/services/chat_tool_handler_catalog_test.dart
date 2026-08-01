import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/chat_tool_handler_catalog.dart';
import 'package:test/test.dart';

void main() {
  group('ChatToolHandlerCatalog', () {
    test(
      'golden standard catalog preserves every specialized binding',
      () async {
        final calls = <_RecordedCall>[];
        final catalog = _standardCatalog(calls);
        final expectedRoutes = _expectedRoutes;

        expect(catalog.toolNames, ChatToolHandlerCatalog.standardToolNames);
        expect(catalog.toolNames, expectedRoutes.keys.toSet());
        for (final entry in expectedRoutes.entries) {
          final result = await catalog.dispatch(_ownerA, _call(entry.key));
          expect(result.toolName, entry.value, reason: entry.key);
        }

        expect(calls, hasLength(expectedRoutes.length));
        for (final call in calls) {
          expect(call.owner, _ownerA, reason: call.toolName);
          expect(call.route, expectedRoutes[call.toolName]);
        }
      },
    );

    test(
      'registry binds the captured owner when the visible owner changes',
      () async {
        final calls = <_RecordedCall>[];
        var visibleOwner = _ownerA;
        final catalog = _standardCatalog(calls);
        final registry = catalog.registryFor(visibleOwner);
        visibleOwner = _ownerB;

        for (final name in ChatToolHandlerCatalog.standardToolNames) {
          final result = await registry.dispatch(_call(name));
          expect(result, isNotNull, reason: name);
        }

        expect(
          calls,
          hasLength(ChatToolHandlerCatalog.standardToolNames.length),
        );
        expect(calls.every((call) => call.owner == _ownerA), isTrue);
        expect(calls.every((call) => call.owner != visibleOwner), isTrue);
      },
    );

    test('later modules win duplicate-name precedence', () async {
      final catalog = ChatToolHandlerCatalog.fromModules([
        MapChatToolHandlerCatalogModule({
          'read_file': _resultHandler('first'),
          'write_file': _resultHandler('write'),
        }),
        MapChatToolHandlerCatalogModule({
          'read_file': _resultHandler('second'),
        }),
      ], fallback: _fallback());

      expect(
        (await catalog.dispatch(_ownerA, _call('read_file'))).toolName,
        'second',
      );
      expect(
        (await catalog.dispatch(_ownerA, _call('write_file'))).toolName,
        'write',
      );
    });

    test('module and catalog maps are detached from mutable inputs', () async {
      final handlers = <String, OwnerChatToolHandler>{
        'read_file': _resultHandler('original'),
      };
      final module = MapChatToolHandlerCatalogModule(handlers);
      final catalog = ChatToolHandlerCatalog.fromModules([
        module,
      ], fallback: _fallback());
      handlers['read_file'] = _resultHandler('mutated');
      handlers['write_file'] = _resultHandler('added');

      expect(
        (await catalog.dispatch(_ownerA, _call('read_file'))).toolName,
        'original',
      );
      expect(catalog.toolNames, {'read_file'});
      expect(() => module.handlers.clear(), throwsUnsupportedError);
      expect(() => catalog.toolNames.add('write_file'), throwsUnsupportedError);
    });

    test(
      'returns handler success and error results without fallback',
      () async {
        var fallbackCalls = 0;
        final catalog = ChatToolHandlerCatalog.fromModules(
          [
            MapChatToolHandlerCatalogModule({
              'success': _resultHandler('success'),
              'failure': (_, toolCall) async => McpToolResult(
                toolName: toolCall.name,
                result: '',
                isSuccess: false,
                errorMessage: 'handler failure',
              ),
            }),
          ],
          fallback: CallbackChatMcpToolExecutionPort((_, toolCall) async {
            fallbackCalls += 1;
            return _result('fallback', result: toolCall.name);
          }),
        );

        expect(
          (await catalog.dispatch(_ownerA, _call('success'))).isSuccess,
          isTrue,
        );
        final failure = await catalog.dispatch(_ownerA, _call('failure'));
        expect(failure.isSuccess, isFalse);
        expect(failure.errorMessage, 'handler failure');
        expect(fallbackCalls, 0);
      },
    );

    test('propagates handler exceptions without invoking fallback', () async {
      var fallbackCalls = 0;
      final catalog = ChatToolHandlerCatalog.fromModules(
        [
          MapChatToolHandlerCatalogModule({
            'explode': (_, _) async => throw StateError('handler exploded'),
          }),
        ],
        fallback: CallbackChatMcpToolExecutionPort((_, _) async {
          fallbackCalls += 1;
          return _result('fallback');
        }),
      );

      await expectLater(
        catalog.dispatch(_ownerA, _call('explode')),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'handler exploded',
          ),
        ),
      );
      expect(fallbackCalls, 0);
    });

    test(
      'unsupported names use the generic MCP port with exact owner',
      () async {
        ChatTurnOwner? receivedOwner;
        ToolCallInfo? receivedCall;
        final catalog = ChatToolHandlerCatalog.fromModules(
          const [],
          fallback: CallbackChatMcpToolExecutionPort((owner, toolCall) async {
            receivedOwner = owner;
            receivedCall = toolCall;
            return _result('fallback', result: toolCall.name);
          }),
        );

        final result = await catalog.dispatch(_ownerA, _call('external_tool'));

        expect(result.toolName, 'fallback');
        expect(result.result, 'external_tool');
        expect(receivedOwner, _ownerA);
        expect(receivedCall?.name, 'external_tool');
      },
    );

    test(
      'registry and fallback handlers remain explicit and separate',
      () async {
        final catalog = ChatToolHandlerCatalog.fromModules(
          [
            MapChatToolHandlerCatalogModule({
              'read_file': _resultHandler('registered'),
            }),
          ],
          fallback: CallbackChatMcpToolExecutionPort((owner, toolCall) async {
            expect(owner, _ownerA);
            return _result('fallback', result: toolCall.name);
          }),
        );
        final registry = catalog.registryFor(_ownerA);

        expect(
          (await registry.dispatch(_call('read_file')))?.toolName,
          'registered',
        );
        expect(await registry.dispatch(_call('external_tool')), isNull);
        expect(
          (await catalog.fallbackHandlerFor(_ownerA)(
            _call('external_tool'),
          )).toolName,
          'fallback',
        );
      },
    );

    test('allowlist filtering preserves order and duplicate definitions', () {
      final catalog = _standardCatalog([]);
      final definitions = [
        _definition('read_file'),
        _definition('write_file'),
        _definition('read_file'),
      ];

      final filtered = catalog.definitionsAllowedBy(definitions, {'read_file'});

      expect(filtered.map(_definitionName), ['read_file', 'read_file']);
      expect(() => filtered.add(_definition('other')), throwsUnsupportedError);
    });

    test('null allowlist returns all immutable definition snapshots', () {
      final catalog = _standardCatalog([]);
      final nested = <String, dynamic>{
        'name': 'read_file',
        'schema': <String, dynamic>{
          'required': <Object?>['path'],
        },
      };
      final definition = <String, dynamic>{'function': nested};

      final filtered = catalog.definitionsAllowedBy([definition], null);
      nested['name'] = 'changed';
      (nested['schema'] as Map<String, dynamic>)['required'] = <Object?>[];

      expect(_definitionName(filtered.single), 'read_file');
      final function = filtered.single['function'] as Map<String, dynamic>;
      final schema = function['schema'] as Map<String, dynamic>;
      expect(schema['required'], ['path']);
      expect(() => function['name'] = 'mutated', throwsUnsupportedError);
      expect(
        () => (schema['required'] as List<Object?>).add('other'),
        throwsUnsupportedError,
      );
    });

    test('empty allowlist and empty definitions return an empty list', () {
      final catalog = _standardCatalog([]);

      expect(catalog.definitionsAllowedBy(const [], null), isEmpty);
      expect(
        catalog.definitionsAllowedBy([_definition('read_file')], const {}),
        isEmpty,
      );
    });

    test('definition logging receives immutable names and no-match set', () {
      final log = _DefinitionLog();
      final catalog = _standardCatalog([], definitionLog: log);

      catalog.definitionsAllowedBy(
        [_definition('read_file'), _definition('write_file')],
        {'missing'},
      );

      expect(log.filteredNames, isEmpty);
      expect(log.noMatchAllowlist, {'missing'});
      expect(() => log.filteredNames.add('other'), throwsUnsupportedError);
      expect(() => log.noMatchAllowlist.add('other'), throwsUnsupportedError);
    });

    test('rejects non-JSON definitions and tool arguments', () async {
      final catalog = _standardCatalog([]);

      expect(
        () => catalog.definitionsAllowedBy([
          {
            'function': {
              'name': 'read_file',
              'invalid': DateTime.utc(2026, 7, 31),
            },
          },
        ], null),
        throwsArgumentError,
      );
      expect(
        () => catalog.dispatch(
          _ownerA,
          ToolCallInfo(
            id: 'bad-call',
            name: 'read_file',
            arguments: {
              'invalid': <String>{'set'},
            },
          ),
        ),
        throwsArgumentError,
      );
    });

    test(
      'freezes arguments before registered and fallback execution',
      () async {
        final seenArguments = <Map<String, dynamic>>[];
        final catalog = ChatToolHandlerCatalog.fromModules(
          [
            MapChatToolHandlerCatalogModule({
              'read_file': (_, toolCall) async {
                seenArguments.add(toolCall.arguments);
                return _result('registered');
              },
            }),
          ],
          fallback: CallbackChatMcpToolExecutionPort((_, toolCall) async {
            seenArguments.add(toolCall.arguments);
            return _result('fallback');
          }),
        );
        final registeredList = <Object?>['a'];
        final fallbackList = <Object?>['b'];

        await catalog.dispatch(
          _ownerA,
          _call('read_file', arguments: {'paths': registeredList}),
        );
        await catalog.dispatch(
          _ownerA,
          _call('external', arguments: {'paths': fallbackList}),
        );
        registeredList.add('changed');
        fallbackList.add('changed');

        expect(seenArguments[0]['paths'], ['a']);
        expect(seenArguments[1]['paths'], ['b']);
        expect(() => seenArguments[0]['other'] = true, throwsUnsupportedError);
      },
    );
  });
}

final _ownerA = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 4,
);
final _ownerB = ChatTurnOwner(
  conversationId: 'conversation-b',
  interactionGeneration: 5,
);

final Map<String, String> _expectedRoutes = {
  for (final name in const [
    'list_directory',
    'read_file',
    'inspect_file',
    'find_files',
    'search_files',
  ])
    name: 'project',
  'lsp_go_to_definition': 'lsp',
  for (final name in const ['write_file', 'edit_file', 'delete_file'])
    name: 'file_mutation',
  'rollback_last_file_change': 'file_rollback',
  'local_execute_command': 'local_command',
  for (final name in const ['process_start', 'process_cancel'])
    name: 'process_mutation',
  for (final name in const [
    'process_status',
    'process_tail',
    'process_wait',
    'process_list',
  ])
    name: 'project_process',
  'run_tests': 'run_tests',
  'run_python_script': 'python',
  for (final name in const [
    'ssh_connect',
    'ssh_execute_command',
    'ssh_disconnect',
  ])
    name: 'ssh',
  for (final name in const [
    'git_execute_command',
    'git_finish_worktree_session',
  ])
    name: 'git',
  'ble_connect': 'ble',
  'serial_open': 'serial',
  'save_skill': 'save_skill',
  'create_routine': 'create_routine',
  'ask_user_question': 'ask_user',
  for (final name in const ['spawn_subagent', 'get_subagent_result'])
    name: 'subagent',
  'update_goal': 'goal',
};

ChatToolHandlerCatalog _standardCatalog(
  List<_RecordedCall> calls, {
  ToolDefinitionLogPort? definitionLog,
}) {
  OwnerChatToolHandler handler(String route) {
    return (owner, toolCall) async {
      calls.add(_RecordedCall(owner, toolCall.name, route));
      return _result(route, result: toolCall.name);
    };
  }

  return ChatToolHandlerCatalog.standard(
    projectScoped: ProjectScopedChatToolHandlers(
      projectScoped: handler('project'),
      lspGoToDefinition: handler('lsp'),
    ),
    ownerScoped: OwnerScopedChatToolHandlers(
      fileMutation: handler('file_mutation'),
      fileRollback: handler('file_rollback'),
      localCommand: handler('local_command'),
      backgroundProcessMutation: handler('process_mutation'),
      projectScopedProcess: handler('project_process'),
      runTests: handler('run_tests'),
      pythonScript: handler('python'),
      ssh: handler('ssh'),
      git: handler('git'),
      ble: handler('ble'),
      serial: handler('serial'),
      saveSkill: handler('save_skill'),
      createRoutine: handler('create_routine'),
    ),
    conversation: ConversationChatToolHandlers(
      askUserQuestion: handler('ask_user'),
      subagent: handler('subagent'),
      updateGoal: handler('goal'),
    ),
    fallback: _fallback(),
    definitionLog: definitionLog,
  );
}

OwnerChatToolHandler _resultHandler(String name) =>
    (_, _) async => _result(name);

ChatMcpToolExecutionPort _fallback() => CallbackChatMcpToolExecutionPort(
  (_, toolCall) async => _result('fallback', result: toolCall.name),
);

ToolCallInfo _call(String name, {Map<String, dynamic> arguments = const {}}) =>
    ToolCallInfo(id: 'call-$name', name: name, arguments: arguments);

Map<String, dynamic> _definition(String name) => {
  'type': 'function',
  'function': {
    'name': name,
    'parameters': <String, dynamic>{'type': 'object'},
  },
};

String _definitionName(Map<String, dynamic> definition) =>
    (definition['function'] as Map<String, dynamic>)['name'] as String;

McpToolResult _result(String name, {String? result}) =>
    McpToolResult(toolName: name, result: result ?? name, isSuccess: true);

final class _RecordedCall {
  const _RecordedCall(this.owner, this.toolName, this.route);

  final ChatTurnOwner owner;
  final String toolName;
  final String route;
}

final class _DefinitionLog implements ToolDefinitionLogPort {
  List<String> filteredNames = const [];
  Set<String> noMatchAllowlist = const {};

  @override
  void recordFilteredToolNames(List<String> names) {
    filteredNames = names;
  }

  @override
  void recordNoAllowlistMatches(Set<String> allowedToolNames) {
    noMatchAllowlist = allowedToolNames;
  }
}
