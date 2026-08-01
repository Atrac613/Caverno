import 'dart:async';

import 'package:caverno/features/chat/data/datasources/subagent_catalog_child_tool_execution_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/chat_tool_handler_catalog.dart';
import 'package:caverno/features/chat/domain/services/subagent_tool_contract.dart';
import 'package:test/test.dart';

void main() {
  group('SubagentCatalogChildToolExecutionAdapter', () {
    test(
      'dispatches with the task owner after visible owner changes',
      () async {
        ChatTurnOwner? dispatchedOwner;
        ToolCallInfo? dispatchedCall;
        var visibleOwner = _ownerA;
        final adapter = _adapter(
          isOwnerCurrent: (_) => true,
          execute: (owner, call) async {
            dispatchedOwner = owner;
            dispatchedCall = call;
            return _success(call.name);
          },
        );
        final request = _request(owner: visibleOwner);
        visibleOwner = _ownerB;

        final completion = await adapter.execute(request);

        expect(completion.request, same(request));
        expect(completion.result.isSuccess, isTrue);
        expect(dispatchedOwner, _ownerA);
        expect(dispatchedOwner, isNot(visibleOwner));
        expect(dispatchedCall?.id, 'child-call');
        expect(dispatchedCall?.name, 'read_file');
        expect(dispatchedCall?.arguments, {'path': 'README.md'});
      },
    );

    test('rejects a tool omitted from the child allowlist', () async {
      var dispatchCount = 0;
      final adapter = _adapter(
        isOwnerCurrent: (_) => true,
        execute: (_, call) async {
          dispatchCount += 1;
          return _success(call.name);
        },
      );

      final completion = await adapter.execute(
        _request(name: 'write_file', allowedToolNames: {'read_file'}),
      );

      expect(dispatchCount, 0);
      expect(completion.result.isSuccess, isFalse);
      expect(
        completion.result.errorMessage,
        'Tool write_file is not available to this subagent.',
      );
    });

    test('rejects nested subagent tools even if allowlisted', () async {
      var dispatchCount = 0;
      final adapter = _adapter(
        isOwnerCurrent: (_) => true,
        execute: (_, call) async {
          dispatchCount += 1;
          return _success(call.name);
        },
      );

      final completion = await adapter.execute(
        _request(
          name: spawnSubagentToolName,
          allowedToolNames: {spawnSubagentToolName},
        ),
      );

      expect(dispatchCount, 0);
      expect(completion.result.isSuccess, isFalse);
      expect(
        completion.result.errorMessage,
        'Nested subagents are not allowed.',
      );
    });

    test('does not dispatch after the exact owner expires', () async {
      var dispatchCount = 0;
      final adapter = _adapter(
        isOwnerCurrent: (_) => false,
        execute: (_, call) async {
          dispatchCount += 1;
          return _success(call.name);
        },
      );

      final completion = await adapter.execute(_request());

      expect(dispatchCount, 0);
      expect(completion.result.isSuccess, isFalse);
      expect(completion.result.errorMessage, contains('exact owner expired'));
    });

    test('reports uncertainty when owner expires during dispatch', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var current = true;
      final adapter = _adapter(
        isOwnerCurrent: (_) => current,
        execute: (_, call) async {
          started.complete();
          await release.future;
          return _success(call.name);
        },
      );
      final request = _request();

      final pending = adapter.execute(request);
      await started.future;
      current = false;
      release.complete();
      final completion = await pending;

      expect(completion.request, same(request));
      expect(completion.result.isSuccess, isFalse);
      expect(completion.result.errorMessage, contains('outcome is uncertain'));
    });

    test('receives recursively immutable request arguments', () async {
      Map<String, dynamic>? receivedArguments;
      final nested = <Object?>['README.md'];
      final adapter = _adapter(
        isOwnerCurrent: (_) => true,
        execute: (_, call) async {
          receivedArguments = call.arguments;
          return _success(call.name);
        },
      );
      final request = _request(arguments: {'paths': nested});

      await adapter.execute(request);
      nested.add('changed');

      expect(receivedArguments?['paths'], ['README.md']);
      expect(
        () => (receivedArguments?['paths'] as List<Object?>).add('other'),
        throwsUnsupportedError,
      );
    });
  });
}

SubagentCatalogChildToolExecutionAdapter _adapter({
  required bool Function(SubagentTaskIdentity identity) isOwnerCurrent,
  required Future<McpToolResult> Function(
    ChatTurnOwner owner,
    ToolCallInfo call,
  )
  execute,
}) {
  final catalog = ChatToolHandlerCatalog.fromModules(
    const [],
    fallback: CallbackChatMcpToolExecutionPort(execute),
  );
  return SubagentCatalogChildToolExecutionAdapter(
    catalog: catalog,
    isOwnerCurrent: isOwnerCurrent,
  );
}

ChildToolExecutionRequest _request({
  ChatTurnOwner? owner,
  String name = 'read_file',
  Map<String, dynamic> arguments = const {'path': 'README.md'},
  Set<String> allowedToolNames = const {'read_file'},
}) {
  return ChildToolExecutionRequest(
    taskIdentity: SubagentTaskIdentity(
      owner: owner ?? _ownerA,
      parentToolCallId: 'parent-call',
      taskId: 'task-1',
    ),
    id: 'child-call',
    name: name,
    arguments: arguments,
    allowedToolNames: allowedToolNames,
  );
}

McpToolResult _success(String toolName) =>
    McpToolResult(toolName: toolName, result: '{"ok":true}', isSuccess: true);

final _ownerA = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 4,
);
final _ownerB = ChatTurnOwner(
  conversationId: 'conversation-b',
  interactionGeneration: 7,
);
