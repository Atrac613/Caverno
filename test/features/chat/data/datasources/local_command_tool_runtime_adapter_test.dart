import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/local_command_tool_runtime_adapter.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:test/test.dart';

const _toolName = 'local_execute_command';

void main() {
  group('local command execution identity', () {
    test('uses canonical strict JSON arguments for the digest', () {
      final first = _request(
        arguments: {
          'command': 'touch output.txt',
          'working_directory': '/workspace',
          'metadata': {
            'z': true,
            'a': [
              1,
              {'two': 2},
            ],
          },
        },
      );
      final second = _request(
        arguments: {
          'metadata': {
            'a': [
              1,
              {'two': 2},
            ],
            'z': true,
          },
          'working_directory': '/workspace',
          'command': 'touch output.txt',
        },
      );

      expect(first.argumentDigest, second.argumentDigest);
      expect(first.identityFor(_owner()), second.identityFor(_owner()));
      expect(
        _request(
          arguments: const {
            'command': 'touch output.txt',
            'working_directory': '/workspace',
            'metadata': {'a': 2},
          },
        ).argumentDigest,
        isNot(first.argumentDigest),
      );
      final executionBaseline = _request();
      expect(
        _request(command: 'touch other.txt').argumentDigest,
        isNot(executionBaseline.argumentDigest),
      );
      expect(
        _request(timeout: const Duration(seconds: 16)).argumentDigest,
        isNot(executionBaseline.argumentDigest),
      );
    });

    test('rejects non-JSON values and invalid execution fields', () {
      expect(
        () => _request(
          arguments: {
            'command': 'touch output.txt',
            'working_directory': '/workspace',
            'nested': <Object?, Object?>{7: 'invalid'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          arguments: const {
            'command': 'touch output.txt',
            'working_directory': '/workspace',
            'number': double.infinity,
          },
        ),
        throwsArgumentError,
      );
      expect(() => _request(toolCallId: ' '), throwsArgumentError);
      expect(() => _request(timeout: Duration.zero), throwsArgumentError);
    });
  });

  group('LocalCommandPermissionRuleRuntimeAdapter', () {
    test('evaluates only the exact owner against its frozen rules', () {
      var current = true;
      final rules = <LocalCommandPermissionRule>[
        LocalCommandPermissionRule(
          id: 'allow-1',
          action: LocalCommandPermissionAction.allow,
          pattern: 'dart analyze',
          workingDirectory: '/workspace',
        ),
      ];
      final owner = _owner();
      final adapter = LocalCommandPermissionRuleRuntimeAdapter(
        owner: owner,
        rules: rules,
        ownerIsCurrent: (_) => current,
        upsert: (_) async {},
        remove: (_) async {},
      );
      rules
        ..clear()
        ..add(
          LocalCommandPermissionRule(
            id: 'poison',
            action: LocalCommandPermissionAction.deny,
            pattern: 'dart analyze',
            workingDirectory: '/workspace',
          ),
        );
      const request = CommandPermissionRuleRequest(
        command: 'dart analyze',
        workingDirectory: '/workspace',
      );

      expect(
        adapter.evaluate(owner, request),
        CommandPermissionRuleDecision.allow,
      );
      expect(
        adapter.evaluate(
          ChatTurnOwner(
            conversationId: 'visible-poison',
            interactionGeneration: 9,
          ),
          request,
        ),
        CommandPermissionRuleDecision.deny,
      );
      current = false;
      expect(
        adapter.evaluate(owner, request),
        CommandPermissionRuleDecision.deny,
      );
    });

    test('persists an exact mapped rule for the current owner', () async {
      LocalCommandPermissionRule? persisted;
      final owner = _owner();
      final adapter = LocalCommandPermissionRuleRuntimeAdapter(
        owner: owner,
        rules: const [],
        ownerIsCurrent: (_) => true,
        upsert: (rule) async => persisted = rule,
        remove: (_) async => fail('Current rule must not be removed.'),
      );

      final completion = await adapter.remember(
        owner,
        'call-1',
        const RememberedCommandPermissionRule(
          action: RememberedCommandPermissionAction.deny,
          match: RememberedCommandPermissionMatch.prefix,
          command: 'dart test',
          workingDirectory: '/workspace',
        ),
      );

      expect(
        completion.disposition,
        LocalCommandCompletionDisposition.completed,
      );
      expect(persisted?.action, LocalCommandPermissionAction.deny);
      expect(persisted?.match, LocalCommandPermissionMatch.prefix);
      expect(persisted?.pattern, 'dart test');
      expect(persisted?.workingDirectory, '/workspace');
    });

    test(
      'compensates a rule when the owner expires during persistence',
      () async {
        var current = true;
        String? persistedId;
        String? removedId;
        final owner = _owner();
        final adapter = LocalCommandPermissionRuleRuntimeAdapter(
          owner: owner,
          rules: const [],
          ownerIsCurrent: (_) => current,
          upsert: (rule) async {
            persistedId = rule.id;
            current = false;
          },
          remove: (ruleId) async => removedId = ruleId,
        );

        final completion = await adapter.remember(
          owner,
          'call-1',
          const RememberedCommandPermissionRule(
            action: RememberedCommandPermissionAction.allow,
            match: RememberedCommandPermissionMatch.exact,
            command: 'dart test',
            workingDirectory: '/workspace',
          ),
        );

        expect(
          completion.disposition,
          LocalCommandCompletionDisposition.ownerExpired,
        );
        expect(removedId, persistedId);
      },
    );
  });

  group('LocalCommandToolRuntimeAdapter', () {
    test(
      'executes with exact owner call tool digest and immutable input',
      () async {
        final runtime = _FakeRuntimePort();
        final adapter = _adapter(runtime);
        final owner = _owner();
        final request = _request();

        final completion = await adapter.execute(owner, request);

        expect(
          completion.disposition,
          LocalCommandCompletionDisposition.completed,
        );
        expect(completion.owner, owner);
        expect(completion.toolCallId, request.toolCallId);
        expect(completion.value!.result, 'completed');
        expect(
          completion.effectDisposition,
          LocalCommandEffectDisposition.settlementRequired,
        );
        expect(completion.effectSettlement!.settle(), isTrue);
        expect(runtime.operations, hasLength(1));
        final operation = runtime.operations.single;
        expect(operation.identity.owner, owner);
        expect(operation.identity.toolCallId, request.toolCallId);
        expect(operation.identity.toolName, request.toolName);
        expect(operation.identity.argumentDigest, request.argumentDigest);
        expect(operation.command, request.command);
        expect(operation.workingDirectory, request.workingDirectory);
        expect(operation.timeout, request.timeout);
        expect(
          () => operation.arguments['late'] = true,
          throwsUnsupportedError,
        );
        expect(runtime.ownerAcknowledgements, hasLength(4));
      },
    );

    test('does not dispatch after owner retirement', () async {
      final runtime = _FakeRuntimePort()
        ..ownerDispositions.add(
          LocalCommandRuntimeOwnerDisposition.ownerExpired,
        );
      final completion = await _adapter(runtime).execute(_owner(), _request());

      expect(
        completion.disposition,
        LocalCommandCompletionDisposition.ownerExpired,
      );
      expect(completion.value, isNull);
      expect(runtime.operations, isEmpty);
    });

    test('rejects a poisoned pre-dispatch owner acknowledgement', () async {
      final runtime = _FakeRuntimePort()
        ..ownerIdentityTransform = (identity) => _poisonIdentity(
          identity,
          owner: ChatTurnOwner(
            conversationId: 'other',
            interactionGeneration: 1,
          ),
        );
      final completion = await _adapter(runtime).execute(_owner(), _request());

      _expectFailure(completion, 'local_command_boundary_mismatch');
      expect(runtime.operations, isEmpty);
    });

    test('rejects an unavailable owner state without dispatch', () async {
      final runtime = _FakeRuntimePort()..ownerError = StateError('offline');
      final completion = await _adapter(runtime).execute(_owner(), _request());

      _expectFailure(completion, 'local_command_owner_state_unavailable');
      expect(runtime.operations, isEmpty);
    });

    test('marks a thrown post-dispatch runtime as effect uncertain', () async {
      final runtime = _FakeRuntimePort()..executionError = StateError('lost');
      final completion = await _adapter(runtime).execute(_owner(), _request());

      _expectFailure(completion, 'local_command_effect_uncertain');
      expect(completion.value!.errorMessage, contains('after dispatch'));
      expect(runtime.operations, hasLength(1));
    });

    test('rejects every poisoned execution receipt identity', () async {
      final owner = _owner();
      final request = _request();
      final expected = request.identityFor(owner);
      final poisoned = <LocalCommandOperationIdentity>[
        _poisonIdentity(
          expected,
          owner: ChatTurnOwner(
            conversationId: 'other',
            interactionGeneration: 1,
          ),
        ),
        _poisonIdentity(expected, toolCallId: 'other-call'),
        _poisonIdentity(expected, toolName: 'other-tool'),
        _poisonIdentity(expected, argumentDigest: 'other-digest'),
      ];

      for (final identity in poisoned) {
        final runtime = _FakeRuntimePort()
          ..executionIdentityTransform = (_) => identity;
        final completion = await _adapter(runtime).execute(owner, request);
        _expectFailure(completion, 'local_command_effect_uncertain');
      }
    });

    test(
      'maps ambiguous execution dispositions to effect uncertainty',
      () async {
        for (final disposition in const [
          LocalCommandRuntimeExecutionDisposition.ownerExpired,
          LocalCommandRuntimeExecutionDisposition.effectUncertain,
        ]) {
          final runtime = _FakeRuntimePort()
            ..executionDisposition = disposition;
          final completion = await _adapter(
            runtime,
          ).execute(_owner(), _request());
          _expectFailure(completion, 'local_command_effect_uncertain');
        }
      },
    );

    test('marks a result tool mismatch as effect uncertain', () async {
      final runtime = _FakeRuntimePort()
        ..result = const McpToolResult(
          toolName: 'other-tool',
          result: 'wrong',
          isSuccess: true,
        );
      final completion = await _adapter(runtime).execute(_owner(), _request());

      _expectFailure(completion, 'local_command_effect_uncertain');
      expect(completion.value!.errorMessage, contains('another tool'));
    });

    test('marks post-dispatch owner changes as effect uncertain', () async {
      final runtime = _FakeRuntimePort()
        ..ownerDispositions.addAll([
          LocalCommandRuntimeOwnerDisposition.current,
          LocalCommandRuntimeOwnerDisposition.current,
          LocalCommandRuntimeOwnerDisposition.ownerExpired,
        ]);
      final completion = await _adapter(runtime).execute(_owner(), _request());

      _expectFailure(completion, 'local_command_effect_uncertain');
      expect(completion.value!.errorMessage, contains('in flight'));
    });

    test('preserves an exact rejected runtime result', () async {
      final rejected = const McpToolResult(
        toolName: _toolName,
        result: '{"ok":false,"code":"launch_rejected"}',
        isSuccess: false,
        errorMessage: 'Launch rejected',
      );
      final runtime = _FakeRuntimePort()
        ..executionDisposition =
            LocalCommandRuntimeExecutionDisposition.rejected
        ..result = rejected;
      final completion = await _adapter(runtime).execute(_owner(), _request());

      expect(
        completion.disposition,
        LocalCommandCompletionDisposition.completed,
      );
      expect(completion.value, same(rejected));
      expect(completion.effectSettlement!.settle(), isTrue);
    });

    test('rejects a successful result labeled as a rejected launch', () async {
      final runtime = _FakeRuntimePort()
        ..executionDisposition =
            LocalCommandRuntimeExecutionDisposition.rejected;
      final completion = await _adapter(runtime).execute(_owner(), _request());

      _expectFailure(completion, 'local_command_effect_uncertain');
      expect(completion.value!.errorMessage, contains('rejected launch'));
    });

    test(
      'callback bridge delegates exact lifecycle and execution calls',
      () async {
        final owner = _owner();
        final request = _request();
        final identities = <LocalCommandOperationIdentity>[];
        final operations = <LocalCommandRuntimeExecution>[];
        final port = CallbackLocalCommandRuntimePort(
          acknowledgeOwner: (identity) {
            identities.add(identity);
            return LocalCommandRuntimeOwnerAcknowledgement.current(
              identity: identity,
            );
          },
          execute: (operation) {
            operations.add(operation);
            return operation.runEffect(
              () async => LocalCommandRuntimeExecutionAcknowledgement.completed(
                identity: operation.identity,
                result: _success(),
              ),
            );
          },
        );

        final completion = await _adapter(port).execute(owner, request);

        expect(completion.value!.isSuccess, isTrue);
        expect(completion.effectSettlement!.settle(), isTrue);
        expect(identities, hasLength(4));
        expect(operations.single.identity, request.identityFor(owner));
      },
    );

    test('revokes a delayed launch before the raw effect starts', () async {
      final owner = _owner();
      final started = Completer<void>();
      final release = Completer<void>();
      var effectCalls = 0;
      final authority = LocalCommandExecutionAuthority();
      final port = CallbackLocalCommandRuntimePort(
        acknowledgeOwner: (identity) =>
            LocalCommandRuntimeOwnerAcknowledgement.current(identity: identity),
        execute: (operation) async {
          started.complete();
          await release.future;
          return operation.runEffect(() async {
            effectCalls += 1;
            return LocalCommandRuntimeExecutionAcknowledgement.completed(
              identity: operation.identity,
              result: _success(),
            );
          });
        },
      );
      final adapter = _adapter(port, authority: authority);

      final pending = adapter.execute(owner, _request());
      await started.future;
      expect(adapter.clearOwner(owner), isNull);
      release.complete();
      final completion = await pending;

      expect(
        completion.disposition,
        LocalCommandCompletionDisposition.ownerExpired,
      );
      expect(effectCalls, 0);
      expect(adapter.pendingEffectRecovery, isNull);
    });

    test(
      'retains commit-then-throw and rejects foreign recovery receipts',
      () async {
        final authority = LocalCommandExecutionAuthority();
        final runtime = _FakeRuntimePort()
          ..executionError = StateError('lost acknowledgement');
        final adapter = _adapter(runtime, authority: authority);

        final completion = await adapter.execute(_owner(), _request());
        _expectFailure(completion, 'local_command_effect_uncertain');
        final receipt = adapter.pendingEffectRecovery;
        expect(receipt, isNotNull);

        final blocked = await adapter.execute(
          ChatTurnOwner(
            conversationId: 'conversation-b',
            interactionGeneration: 1,
          ),
          _request(toolCallId: 'call-2'),
        );
        _expectFailure(blocked, 'local_command_execution_busy');

        final foreignAdapter = _adapter(
          _FakeRuntimePort()..executionError = StateError('foreign failure'),
          authority: LocalCommandExecutionAuthority(),
        );
        await foreignAdapter.execute(_owner(), _request());
        final foreignReceipt = foreignAdapter.pendingEffectRecovery!;
        expect(adapter.clearEffectRecovery(foreignReceipt), isFalse);
        expect(adapter.clearEffectRecovery(receipt!), isTrue);
        expect(adapter.pendingEffectRecovery, isNull);
      },
    );
  });
}

LocalCommandToolRuntimeAdapter _adapter(
  LocalCommandRuntimePort runtime, {
  LocalCommandExecutionAuthority? authority,
}) {
  return LocalCommandToolRuntimeAdapter(
    runtimePort: runtime,
    executionAuthority: authority ?? LocalCommandExecutionAuthority(),
  );
}

ChatTurnOwner _owner() =>
    ChatTurnOwner(conversationId: 'conversation-a', interactionGeneration: 4);

LocalCommandExecutionRequest _request({
  String toolCallId = 'call-1',
  String toolName = _toolName,
  String command = 'touch output.txt',
  String workingDirectory = '/workspace',
  Map<String, dynamic> arguments = const {
    'command': 'touch output.txt',
    'working_directory': '/workspace',
  },
  Duration timeout = const Duration(seconds: 15),
}) {
  return LocalCommandExecutionRequest(
    toolCallId: toolCallId,
    toolName: toolName,
    command: command,
    workingDirectory: workingDirectory,
    arguments: arguments,
    timeout: timeout,
  );
}

McpToolResult _success() => const McpToolResult(
  toolName: _toolName,
  result: 'completed',
  isSuccess: true,
);

LocalCommandOperationIdentity _poisonIdentity(
  LocalCommandOperationIdentity source, {
  ChatTurnOwner? owner,
  String? toolCallId,
  String? toolName,
  String? argumentDigest,
}) {
  return LocalCommandOperationIdentity(
    owner: owner ?? source.owner,
    toolCallId: toolCallId ?? source.toolCallId,
    toolName: toolName ?? source.toolName,
    argumentDigest: argumentDigest ?? source.argumentDigest,
  );
}

void _expectFailure(
  LocalCommandCompletion<McpToolResult> completion,
  String code,
) {
  expect(completion.disposition, LocalCommandCompletionDisposition.completed);
  expect(completion.value!.isSuccess, isFalse);
  final payload = jsonDecode(completion.value!.result) as Map<String, dynamic>;
  expect(payload['code'], code);
}

final class _FakeRuntimePort implements LocalCommandRuntimePort {
  final List<LocalCommandRuntimeOwnerDisposition> ownerDispositions = [];
  final List<LocalCommandOperationIdentity> ownerAcknowledgements = [];
  final List<LocalCommandRuntimeExecution> operations = [];
  LocalCommandOperationIdentity Function(LocalCommandOperationIdentity)?
  ownerIdentityTransform;
  LocalCommandOperationIdentity Function(LocalCommandOperationIdentity)?
  executionIdentityTransform;
  LocalCommandRuntimeExecutionDisposition executionDisposition =
      LocalCommandRuntimeExecutionDisposition.completed;
  McpToolResult result = _success();
  Object? ownerError;
  Object? executionError;

  @override
  LocalCommandRuntimeOwnerAcknowledgement acknowledgeOwner(
    LocalCommandOperationIdentity identity,
  ) {
    ownerAcknowledgements.add(identity);
    if (ownerError case final error?) throw error;
    final disposition = ownerDispositions.isEmpty
        ? LocalCommandRuntimeOwnerDisposition.current
        : ownerDispositions.removeAt(0);
    return LocalCommandRuntimeOwnerAcknowledgement(
      identity: ownerIdentityTransform?.call(identity) ?? identity,
      disposition: disposition,
    );
  }

  @override
  Future<LocalCommandRuntimeExecutionAcknowledgement> execute(
    LocalCommandRuntimeExecution operation,
  ) {
    operations.add(operation);
    return operation.runEffect(() async {
      if (executionError case final error?) throw error;
      final identity =
          executionIdentityTransform?.call(operation.identity) ??
          operation.identity;
      return switch (executionDisposition) {
        LocalCommandRuntimeExecutionDisposition.completed =>
          LocalCommandRuntimeExecutionAcknowledgement.completed(
            identity: identity,
            result: result,
          ),
        LocalCommandRuntimeExecutionDisposition.rejected =>
          LocalCommandRuntimeExecutionAcknowledgement.rejected(
            identity: identity,
            result: result,
          ),
        LocalCommandRuntimeExecutionDisposition.ownerExpired =>
          LocalCommandRuntimeExecutionAcknowledgement.ownerExpired(
            identity: identity,
          ),
        LocalCommandRuntimeExecutionDisposition.effectUncertain =>
          LocalCommandRuntimeExecutionAcknowledgement.effectUncertain(
            identity: identity,
          ),
      };
    });
  }
}
