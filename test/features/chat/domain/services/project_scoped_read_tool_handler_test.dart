import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/project_scoped_read_tool_handler.dart';
import 'package:test/test.dart';

const _tools = {
  'list_directory',
  'read_file',
  'inspect_file',
  'find_files',
  'search_files',
  'process_status',
  'process_tail',
  'process_wait',
  'process_list',
};

typedef _Call = ({
  ProjectScopedReadOperationIdentity identity,
  Map<String, dynamic> arguments,
});
typedef _Behavior =
    Future<ProjectScopedReadCompletion> Function(
      ProjectScopedReadOperationIdentity,
      Map<String, dynamic>,
    );

final class _Lifecycle implements ProjectScopedReadLifecyclePort {
  final expired = <ProjectScopedReadOperationIdentity>{};
  final checks = <ProjectScopedReadOperationIdentity>[];

  @override
  bool isCurrent(ProjectScopedReadOperationIdentity identity) {
    checks.add(identity);
    return !expired.contains(identity);
  }
}

final class _Execution implements McpToolExecutionPort {
  _Behavior? behavior;
  final calls = <_Call>[];

  @override
  Future<ProjectScopedReadCompletion> execute(
    ProjectScopedReadOperationIdentity identity,
    Map<String, dynamic> arguments,
  ) async {
    calls.add((identity: identity, arguments: arguments));
    final custom = behavior;
    if (custom != null) return custom(identity, arguments);
    return _completion(identity);
  }
}

ChatTurnOwner _owner([int generation = 7]) => ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: generation,
);

ProjectScopedReadToolRequest _request({
  String id = 'call-1',
  String name = 'read_file',
  String? root = '/workspace/owner',
  Map<String, dynamic> arguments = const {'path': 'lib/main.dart'},
}) => ProjectScopedReadToolRequest(
  owner: _owner(),
  toolCallId: id,
  toolName: name,
  ownerProjectRoot: root,
  arguments: arguments,
);

ProjectScopedReadToolHandler _handler(
  _Execution execution,
  _Lifecycle lifecycle,
) => ProjectScopedReadToolHandler(
  executionPort: execution,
  lifecyclePort: lifecycle,
  supportedToolNames: _tools,
);

Map<String, dynamic> _payload(McpToolResult result) =>
    jsonDecode(result.result) as Map<String, dynamic>;
String? _code(McpToolResult result) => _payload(result)['code'] as String?;

ProjectScopedReadCompletion _completion(
  ProjectScopedReadOperationIdentity identity, [
  String result = 'completed',
]) => ProjectScopedReadCompletion(
  identity: identity,
  result: McpToolResult(
    toolName: identity.toolName,
    result: result,
    isSuccess: true,
  ),
);

void main() {
  test('requires non-empty call IDs and canonical tool names', () {
    expect(
      () => _request(id: ' '),
      throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'toolCallId')),
    );
    for (final name in [' Read_File', 'read-file', 'READ_FILE', '']) {
      expect(() => _request(name: name), throwsArgumentError);
    }
  });

  test('freezes JSON arguments and rejects non-JSON graphs', () {
    final nested = <String, dynamic>{
      'paths': <Object?>['lib/main.dart'],
    };
    final source = <String, dynamic>{'path': 'lib/main.dart', 'nested': nested};
    final request = _request(arguments: source);
    source['path'] = 'poison.dart';
    (nested['paths']! as List).add('poison.dart');

    expect(request.arguments['path'], 'lib/main.dart');
    expect((request.arguments['nested'] as Map)['paths'], ['lib/main.dart']);
    expect(
      () => (request.arguments['nested'] as Map)['late'] = true,
      throwsUnsupportedError,
    );
    for (final value in [
      <Object?, Object?>{7: 'bad-key'},
      <String>{'bad'},
    ]) {
      expect(() => _request(arguments: {'nested': value}), throwsArgumentError);
    }
  });

  test(
    'binds explicit roots, resolution, and execution to the exact call',
    () async {
      final execution = _Execution();
      final lifecycle = _Lifecycle();
      final request = _request(
        id: 'file-call',
        arguments: const {'path': 'lib/main.dart', 'limit': 12},
      );
      final result = await _handler(execution, lifecycle).handle(request);

      expect(result.result, 'completed');
      expect(execution.calls.single.identity, same(request.identity));
      expect(execution.calls.single.arguments, {
        'path': '/workspace/owner/lib/main.dart',
        'limit': 12,
      });
      expect(
        () => execution.calls.single.arguments['path'] = 'poison.dart',
        throwsUnsupportedError,
      );
      expect(lifecycle.checks, everyElement(same(request.identity)));
    },
  );

  test('preserves absent-root and process argument behavior', () async {
    final execution = _Execution();
    final lifecycle = _Lifecycle();
    final handler = _handler(execution, lifecycle);
    await handler.handle(
      _request(name: 'list_directory', root: null, arguments: const {}),
    );
    await handler.handle(
      _request(
        id: 'process-call',
        name: 'process_tail',
        arguments: const {'job_id': 'job-7', 'lines': 12},
      ),
    );

    expect(execution.calls[0].arguments, {'path': '.'});
    expect(execution.calls[1].arguments, {'job_id': 'job-7', 'lines': 12});
  });

  test(
    'rejects unsupported tools and resolver failures before execution',
    () async {
      final execution = _Execution();
      final lifecycle = _Lifecycle();
      final handler = _handler(execution, lifecycle);
      await expectLater(
        handler.handle(_request(name: 'resolve_installed_dependency')),
        throwsArgumentError,
      );
      await expectLater(
        handler.handle(_request(arguments: const {'path': 7})),
        throwsA(isA<TypeError>()),
      );
      expect(execution.calls, isEmpty);
      final error = StateError('transport failed');
      execution.behavior = (_, _) =>
          Future<ProjectScopedReadCompletion>.error(error);
      await expectLater(handler.handle(_request()), throwsA(same(error)));
    },
  );

  test('rejects stale lifecycle and wrong-call read completions', () async {
    final lifecycle = _Lifecycle();
    final execution = _Execution();
    final request = _request();
    lifecycle.expired.add(request.identity);
    var result = await _handler(execution, lifecycle).handle(request);
    expect(_code(result), 'turn_owner_expired');
    expect(execution.calls, isEmpty);

    lifecycle.expired.clear();
    final other = _request(id: 'call-2');
    execution.behavior = (_, _) async => ProjectScopedReadCompletion(
      identity: other.identity,
      result: _completion(other.identity, 'poison').result,
    );
    result = await _handler(execution, lifecycle).handle(request);
    expect(_code(result), 'turn_owner_expired');
  });

  test(
    'same-owner concurrent completions cannot cross roots or arguments',
    () async {
      final lifecycle = _Lifecycle();
      final execution = _Execution();
      final firstDone = Completer<ProjectScopedReadCompletion>();
      final secondDone = Completer<ProjectScopedReadCompletion>();
      final first = _request(id: 'shared', root: '/workspace/a');
      final second = _request(
        id: 'shared',
        root: '/workspace/b',
        arguments: const {'path': 'lib/other.dart'},
      );
      expect(first.identity, isNot(second.identity));
      execution.behavior = (_, arguments) =>
          arguments['path'] == '/workspace/a/lib/main.dart'
          ? firstDone.future
          : secondDone.future;
      final handler = _handler(execution, lifecycle);
      final firstResult = handler.handle(first);
      final secondResult = handler.handle(second);
      firstDone.complete(_completion(second.identity, 'second'));
      secondDone.complete(_completion(first.identity, 'first'));

      expect(_code(await firstResult), 'turn_owner_expired');
      expect(_code(await secondResult), 'turn_owner_expired');
    },
  );

  test('returns safe guidance for ambiguous process observations', () async {
    final execution = _Execution();
    final request = _request(name: 'process_status');
    final other = _request(id: 'other', name: 'process_status');
    execution.behavior = (_, _) async =>
        _completion(other.identity, '{"status":"exited"}');

    final result = await _handler(execution, _Lifecycle()).handle(request);
    expect(result.isSuccess, isFalse);
    expect(
      _payload(result),
      containsPair('code', 'background_process_observation_uncertain'),
    );
    expect(_payload(result)['next_action'], contains('exact job_id'));
  });
}
