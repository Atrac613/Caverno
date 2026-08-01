import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/project_scoped_read_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:test/test.dart';

ToolCallInfo _toolCall({
  String id = 'read-call',
  String name = 'read_file',
  Map<String, dynamic> arguments = const {'path': 'lib/main.dart'},
}) => ToolCallInfo(id: id, name: name, arguments: arguments);

Map<String, dynamic> _payload(McpToolResult result) =>
    jsonDecode(result.result) as Map<String, dynamic>;

void main() {
  final owner = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 7,
  );

  group('ProjectScopedReadRuntimeInput', () {
    test('freezes strict JSON and computes a canonical argument digest', () {
      final paths = <Object?>['lib/main.dart'];
      final metadata = <String, Object?>{'paths': paths};
      final arguments = <String, dynamic>{
        'path': 'lib/main.dart',
        'metadata': metadata,
      };
      final first = ProjectScopedReadRuntimeInput(
        owner: owner,
        toolCall: _toolCall(arguments: arguments),
      );
      final reordered = ProjectScopedReadRuntimeInput(
        owner: owner,
        toolCall: _toolCall(
          arguments: {
            'metadata': {
              'paths': ['lib/main.dart'],
            },
            'path': 'lib/main.dart',
          },
        ),
      );

      paths.add('poison.dart');
      metadata['paths'] = ['replaced'];
      arguments['path'] = 'poison.dart';

      expect(first.identity, reordered.identity);
      expect(first.arguments['path'], 'lib/main.dart');
      expect(first.arguments['metadata'], {
        'paths': ['lib/main.dart'],
      });
      expect(() => first.arguments['late'] = true, throwsUnsupportedError);
    });

    test('rejects ambiguous identities and non-JSON values', () {
      for (final invalid in <Object?>[
        <String>{'mutable'},
        <Object?, Object?>{7: 'bad-key'},
        double.nan,
        double.infinity,
      ]) {
        expect(
          () => ProjectScopedReadRuntimeInput(
            owner: owner,
            toolCall: _toolCall(arguments: {'path': 'a', 'invalid': invalid}),
          ),
          throwsArgumentError,
        );
      }
      for (final toolCall in [
        _toolCall(id: ' '),
        _toolCall(name: 'read_file '),
        _toolCall(name: 'READ_FILE'),
      ]) {
        expect(
          () => ProjectScopedReadRuntimeInput(owner: owner, toolCall: toolCall),
          throwsArgumentError,
        );
      }
    });

    test('binds normalized root identity separately from arguments', () {
      final a = ProjectScopedReadRootIdentity(' /workspace/a ');
      final same = ProjectScopedReadRootIdentity('/workspace/a');
      final absent = ProjectScopedReadRootIdentity(' ');

      expect(a, same);
      expect(a.digest, same.digest);
      expect(absent.projectRoot, isNull);
      expect(a, isNot(absent));
    });
  });

  group('ProjectScopedReadToolRuntimeAdapter', () {
    late String? projectRoot;
    late ProjectScopedReadRootDisposition rootDisposition;
    late ProjectScopedReadLifecycleDisposition lifecycleDisposition;
    late ProjectScopedReadExecutionDisposition executionDisposition;
    late List<ProjectScopedReadExecutionRequest> executions;
    late ProjectScopedReadExecutionAcknowledgement Function(
      ProjectScopedReadExecutionRequest request,
    )
    buildAcknowledgement;
    late ProjectScopedReadToolRuntimeAdapter adapter;

    setUp(() {
      projectRoot = '/workspace/a';
      rootDisposition = ProjectScopedReadRootDisposition.resolved;
      lifecycleDisposition = ProjectScopedReadLifecycleDisposition.current;
      executionDisposition = ProjectScopedReadExecutionDisposition.completed;
      executions = [];
      buildAcknowledgement = (request) {
        return ProjectScopedReadExecutionAcknowledgement(
          identity: request.identity,
          disposition: executionDisposition,
          result:
              executionDisposition ==
                  ProjectScopedReadExecutionDisposition.completed
              ? McpToolResult(
                  toolName: request.toolName,
                  result: '{"ok":true}',
                  isSuccess: true,
                )
              : null,
        );
      };
      adapter = ProjectScopedReadToolRuntimeAdapter(
        resolveProjectRoot: (identity) {
          return ProjectScopedReadRootAcknowledgement(
            identity: identity,
            projectRoot: projectRoot,
            disposition: rootDisposition,
          );
        },
        acknowledgeLifecycle: (identity) {
          return ProjectScopedReadLifecycleAcknowledgement(
            identity: identity,
            disposition: lifecycleDisposition,
          );
        },
        execute: (request) async {
          executions.add(request);
          return buildAcknowledgement(request);
        },
      );
    });

    test('binds owner, call, tool, arguments, root, and completion', () async {
      final completion = await adapter.handle(
        owner: owner,
        toolCall: _toolCall(
          id: 'exact-call',
          arguments: const {'path': 'lib/main.dart', 'limit': 12},
        ),
      );

      expect(
        completion.disposition,
        ProjectScopedReadRuntimeDisposition.completed,
      );
      expect(completion.result.isSuccess, isTrue);
      expect(completion.identity.owner, owner);
      expect(completion.identity.invocation.toolCallId, 'exact-call');
      expect(completion.identity.root.projectRoot, '/workspace/a');
      expect(executions.single.arguments, {
        'path': '/workspace/a/lib/main.dart',
        'limit': 12,
      });
      expect(
        executions.single.identity.resolvedArgumentDigest,
        projectScopedReadArgumentDigest(executions.single.arguments),
      );
      expect(
        () => executions.single.arguments['path'] = 'poison.dart',
        throwsUnsupportedError,
      );
    });

    test('changes exact identity when arguments or roots change', () async {
      final first = await adapter.handle(owner: owner, toolCall: _toolCall());
      final changedArguments = await adapter.handle(
        owner: owner,
        toolCall: _toolCall(arguments: const {'path': 'lib/other.dart'}),
      );
      projectRoot = '/workspace/b';
      final changedRoot = await adapter.handle(
        owner: owner,
        toolCall: _toolCall(),
      );

      expect(first.identity, isNot(changedArguments.identity));
      expect(first.identity, isNot(changedRoot.identity));
      expect(
        first.identity.invocation.argumentDigest,
        isNot(changedArguments.identity.invocation.argumentDigest),
      );
      expect(first.identity.root, isNot(changedRoot.identity.root));
    });

    test('returns explicit root rejection without dispatch', () async {
      rootDisposition = ProjectScopedReadRootDisposition.rejected;

      final completion = await adapter.handle(
        owner: owner,
        toolCall: _toolCall(),
      );

      expect(
        completion.disposition,
        ProjectScopedReadRuntimeDisposition.rejected,
      );
      expect(
        _payload(completion.result)['code'],
        'project_scoped_read_rejected',
      );
      expect(executions, isEmpty);
    });

    test(
      'never trusts root or lifecycle acknowledgements from peers',
      () async {
        adapter = ProjectScopedReadToolRuntimeAdapter(
          resolveProjectRoot: (identity) {
            return ProjectScopedReadRootAcknowledgement(
              identity: ProjectScopedReadInvocationIdentity(
                owner: identity.owner,
                toolCallId: 'peer-call',
                toolName: identity.toolName,
                argumentDigest: identity.argumentDigest,
              ),
              projectRoot: projectRoot,
              disposition: ProjectScopedReadRootDisposition.resolved,
            );
          },
          acknowledgeLifecycle: (identity) =>
              ProjectScopedReadLifecycleAcknowledgement(
                identity: identity,
                disposition: ProjectScopedReadLifecycleDisposition.current,
              ),
          execute: (request) async {
            executions.add(request);
            return buildAcknowledgement(request);
          },
        );
        var completion = await adapter.handle(
          owner: owner,
          toolCall: _toolCall(),
        );
        expect(
          completion.disposition,
          ProjectScopedReadRuntimeDisposition.boundaryMismatch,
        );
        expect(executions, isEmpty);

        adapter = ProjectScopedReadToolRuntimeAdapter(
          resolveProjectRoot: (identity) =>
              ProjectScopedReadRootAcknowledgement(
                identity: identity,
                projectRoot: projectRoot,
                disposition: ProjectScopedReadRootDisposition.resolved,
              ),
          acknowledgeLifecycle: (identity) {
            return ProjectScopedReadLifecycleAcknowledgement(
              identity: ProjectScopedReadRuntimeIdentity(
                invocation: identity.invocation,
                root: ProjectScopedReadRootIdentity('/workspace/peer'),
                toolRequestIdentity: identity.toolRequestIdentity,
              ),
              disposition: ProjectScopedReadLifecycleDisposition.current,
            );
          },
          execute: (request) async {
            executions.add(request);
            return buildAcknowledgement(request);
          },
        );
        completion = await adapter.handle(owner: owner, toolCall: _toolCall());
        expect(
          completion.disposition,
          ProjectScopedReadRuntimeDisposition.boundaryMismatch,
        );
        expect(executions, isEmpty);
      },
    );

    test('rejects unsupported local tools without dispatch', () async {
      final completion = await adapter.handle(
        owner: owner,
        toolCall: _toolCall(name: 'process_status', arguments: const {}),
      );

      expect(
        completion.disposition,
        ProjectScopedReadRuntimeDisposition.rejected,
      );
      expect(executions, isEmpty);
    });

    test('maps lifecycle expiry before execution', () async {
      lifecycleDisposition = ProjectScopedReadLifecycleDisposition.ownerExpired;

      final completion = await adapter.handle(
        owner: owner,
        toolCall: _toolCall(),
      );

      expect(
        completion.disposition,
        ProjectScopedReadRuntimeDisposition.ownerExpired,
      );
      expect(_payload(completion.result)['code'], 'turn_owner_expired');
      expect(executions, isEmpty);
    });

    test('preserves an exact rejected callback result', () async {
      executionDisposition = ProjectScopedReadExecutionDisposition.rejected;
      buildAcknowledgement = (request) {
        return ProjectScopedReadExecutionAcknowledgement(
          identity: request.identity,
          disposition: executionDisposition,
          result: McpToolResult(
            toolName: request.toolName,
            result: '{"ok":false,"code":"path_rejected"}',
            isSuccess: false,
            errorMessage: 'path rejected',
          ),
        );
      };

      final completion = await adapter.handle(
        owner: owner,
        toolCall: _toolCall(),
      );

      expect(
        completion.disposition,
        ProjectScopedReadRuntimeDisposition.rejected,
      );
      expect(_payload(completion.result)['code'], 'path_rejected');
    });

    test('maps explicit callback uncertainty', () async {
      executionDisposition =
          ProjectScopedReadExecutionDisposition.effectUncertain;

      final completion = await adapter.handle(
        owner: owner,
        toolCall: _toolCall(),
      );

      expect(
        completion.disposition,
        ProjectScopedReadRuntimeDisposition.effectUncertain,
      );
      expect(
        _payload(completion.result)['code'],
        'project_scoped_read_effect_uncertain',
      );
    });

    test(
      'never trusts an acknowledgement for another argument digest',
      () async {
        buildAcknowledgement = (request) {
          return ProjectScopedReadExecutionAcknowledgement(
            identity: ProjectScopedReadExecutionIdentity(
              runtime: request.identity.runtime,
              resolvedArgumentDigest: 'poisoned-digest',
            ),
            disposition: ProjectScopedReadExecutionDisposition.completed,
            result: McpToolResult(
              toolName: request.toolName,
              result: 'poison',
              isSuccess: true,
            ),
          );
        };

        final completion = await adapter.handle(
          owner: owner,
          toolCall: _toolCall(),
        );

        expect(
          completion.disposition,
          ProjectScopedReadRuntimeDisposition.effectUncertain,
        );
        expect(
          _payload(completion.result)['code'],
          'project_scoped_read_effect_uncertain',
        );
      },
    );

    test('never trusts a successful result for another tool', () async {
      buildAcknowledgement = (request) {
        return ProjectScopedReadExecutionAcknowledgement(
          identity: request.identity,
          disposition: ProjectScopedReadExecutionDisposition.completed,
          result: const McpToolResult(
            toolName: 'search_files',
            result: 'poison',
            isSuccess: true,
          ),
        );
      };

      final completion = await adapter.handle(
        owner: owner,
        toolCall: _toolCall(),
      );

      expect(
        completion.disposition,
        ProjectScopedReadRuntimeDisposition.effectUncertain,
      );
      expect(completion.result.isSuccess, isFalse);
    });

    test('root drift during execution is explicitly uncertain', () async {
      buildAcknowledgement = (request) {
        projectRoot = '/workspace/b';
        return ProjectScopedReadExecutionAcknowledgement(
          identity: request.identity,
          disposition: ProjectScopedReadExecutionDisposition.completed,
          result: McpToolResult(
            toolName: request.toolName,
            result: '{"ok":true}',
            isSuccess: true,
          ),
        );
      };

      final completion = await adapter.handle(
        owner: owner,
        toolCall: _toolCall(),
      );

      expect(
        completion.disposition,
        ProjectScopedReadRuntimeDisposition.effectUncertain,
      );
      expect(completion.result.isSuccess, isFalse);
    });

    test('callback exceptions are explicitly uncertain', () async {
      adapter = ProjectScopedReadToolRuntimeAdapter(
        resolveProjectRoot: (identity) => ProjectScopedReadRootAcknowledgement(
          identity: identity,
          projectRoot: projectRoot,
          disposition: ProjectScopedReadRootDisposition.resolved,
        ),
        acknowledgeLifecycle: (identity) =>
            ProjectScopedReadLifecycleAcknowledgement(
              identity: identity,
              disposition: ProjectScopedReadLifecycleDisposition.current,
            ),
        execute: (_) => Future.error(StateError('read transport failed')),
      );

      final completion = await adapter.handle(
        owner: owner,
        toolCall: _toolCall(),
      );

      expect(
        completion.disposition,
        ProjectScopedReadRuntimeDisposition.effectUncertain,
      );
      expect(
        _payload(completion.result)['code'],
        'project_scoped_read_effect_uncertain',
      );
    });
  });
}
