import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/local_command_tool_handler.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

const _toolName = 'local_execute_command';
const _ownerARoot = '/workspace/owner-a';
const _ownerBRoot = '/workspace/owner-b';
const _expiredMessage = 'The approval turn expired before execution';
const _effectUncertainMessage =
    'The local command may have completed after its owner expired; inspect '
    'possible process and filesystem effects before retrying';

ChatTurnOwner _owner(String conversationId, {int generation = 1}) =>
    ChatTurnOwner(
      conversationId: conversationId,
      interactionGeneration: generation,
    );

LocalCommandToolRequest _request({
  required ChatTurnOwner owner,
  String toolCallId = 'local-command-call',
  Map<String, dynamic> arguments = const {'command': 'touch output.txt'},
  String allowedRoot = _ownerARoot,
  String? defaultWorkingDirectory,
  bool remote = false,
}) {
  return LocalCommandToolRequest(
    owner: owner,
    toolCallId: toolCallId,
    toolName: _toolName,
    allowedWorkingDirectoryRoot: allowedRoot,
    defaultWorkingDirectory: defaultWorkingDirectory,
    arguments: arguments,
    isRemoteInteraction: remote,
  );
}

McpToolResult _toolResult(
  String result, {
  bool isSuccess = true,
  String? errorMessage,
}) {
  return McpToolResult(
    toolName: _toolName,
    result: result,
    isSuccess: isSuccess,
    errorMessage: errorMessage,
  );
}

void _expectExpired(McpToolResult result) {
  expect(result.toolName, _toolName);
  expect(result.result, isEmpty);
  expect(result.isSuccess, isFalse);
  expect(result.errorMessage, _expiredMessage);
}

void _expectEffectUncertain(McpToolResult result) {
  expect(result.toolName, _toolName);
  expect(result.result, isEmpty);
  expect(result.isSuccess, isFalse);
  expect(result.errorMessage, _effectUncertainMessage);
}

List<({ChatTurnOwner owner, String toolCallId, String error})> _poisonScopes(
  ChatTurnOwner owner,
  String toolCallId,
) => [
  (
    owner: _owner('other-conversation'),
    toolCallId: toolCallId,
    error: 'owner mismatch.',
  ),
  (
    owner: _owner(
      owner.conversationId,
      generation: owner.interactionGeneration + 1,
    ),
    toolCallId: toolCallId,
    error: 'owner mismatch.',
  ),
  (
    owner: owner,
    toolCallId: '$toolCallId-poison',
    error: 'tool call mismatch.',
  ),
];

void main() {
  group('LocalCommandToolHandler', () {
    test('recursively freezes request and execution arguments', () async {
      final owner = _owner('owner-a');
      final nestedOwners = <Object?>['owner-a'];
      final nestedList = <Object?>[
        'first',
        <String, dynamic>{
          'deep': <Object?>['stable'],
        },
      ];
      final nestedMap = <String, dynamic>{
        'value': 'stable',
        'items': nestedList,
        'owners': nestedOwners,
        'labels': <String, Object?>{'7': 'owner-a'},
      };
      final source = <String, dynamic>{'command': 'pwd', 'metadata': nestedMap};
      final request = _request(owner: owner, arguments: source);

      source['command'] = 'rm -rf build';
      nestedMap['value'] = 'mutated';
      nestedList.add('mutated');
      nestedOwners.add('owner-b');
      (nestedMap['labels'] as Map)['7'] = 'visible';
      ((nestedList[1] as Map<String, dynamic>)['deep'] as List<Object?>)[0] =
          'mutated';

      expect(request.arguments['command'], 'pwd');
      final frozenMetadata =
          request.arguments['metadata'] as Map<String, dynamic>;
      final frozenItems = frozenMetadata['items'] as List<Object?>;
      expect(frozenMetadata['value'], 'stable');
      expect(frozenItems, hasLength(2));
      expect(frozenMetadata['owners'], ['owner-a']);
      expect(frozenMetadata['labels'], {'7': 'owner-a'});
      expect(
        ((frozenItems[1] as Map<String, dynamic>)['deep'] as List<Object?>)
            .single,
        'stable',
      );
      expect(() => request.arguments['new'] = true, throwsUnsupportedError);
      expect(() => frozenMetadata['value'] = 'changed', throwsUnsupportedError);
      expect(() => frozenItems.add('changed'), throwsUnsupportedError);
      expect(
        () => (frozenMetadata['owners'] as List<Object?>).add('owner-b'),
        throwsUnsupportedError,
      );
      expect(
        () => (frozenMetadata['labels'] as Map)['7'] = 'late',
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((frozenItems[1] as Map<String, dynamic>)['deep']
                    as List<Object?>)[0] =
                'changed',
        throwsUnsupportedError,
      );

      final harness = _Harness();
      await harness.handler.handle(request);
      final execution = harness.execution.calls.single.request;
      expect(
        () => execution.arguments['command'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () =>
            (execution.arguments['metadata'] as Map<String, dynamic>)['value'] =
                'changed',
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((execution.arguments['metadata'] as Map<String, dynamic>)['owners']
                    as List<Object?>)
                .add('owner-b'),
        throwsUnsupportedError,
      );
    });

    test('rejects mutable leaves and non-string nested map keys', () {
      final owner = _owner('owner-a');

      expect(
        () => _request(
          owner: owner,
          arguments: {'command': 'pwd', 'mutable': _MutableArgument()},
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          owner: owner,
          arguments: {
            'command': 'pwd',
            'nested': <Object?>{'not-json'},
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          owner: owner,
          arguments: {'command': 'pwd', 'number': double.infinity},
        ),
        throwsArgumentError,
      );
      expect(
        () => _request(
          owner: owner,
          arguments: {
            'command': 'pwd',
            'nested': <Object?, Object?>{7: 'mutable key'},
          },
        ),
        throwsArgumentError,
      );
    });

    test(
      'returns the exact missing-command failure without side effects',
      () async {
        final harness = _Harness();
        final result = await harness.handler.handle(
          _request(
            owner: _owner('owner-a'),
            arguments: const {
              'command': ' <|im_end|> ',
              'working_directory': _ownerARoot,
            },
          ),
        );

        expect(result.toolName, _toolName);
        expect(result.result, isEmpty);
        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'command is required and working_directory must be provided or '
          'inferred from the selected coding project',
        );
        expect(harness.rules.evaluations, isEmpty);
        expect(harness.approval.totalCalls, 0);
        expect(harness.execution.calls, isEmpty);
      },
    );

    test(
      'uses the allowed project root when no directory is supplied',
      () async {
        final owner = _owner('owner-a');
        final harness = _Harness();
        final result = await harness.handler.handle(
          _request(owner: owner, arguments: const {'command': 'pwd'}),
        );

        expect(result.result, contains('"exit_code":0'));
        expect(harness.execution.calls, hasLength(1));
        final call = harness.execution.calls.single;
        expect(call.owner, owner);
        expect(call.request.command, 'pwd');
        expect(call.request.workingDirectory, _ownerARoot);
        expect(call.request.timeout, const Duration(seconds: 60));
        expect(
          call.request.arguments,
          containsPair('working_directory', _ownerARoot),
        );
        expect(harness.approval.resolveCalls, isEmpty);
        expect(harness.approval.expiredOwners, [owner, owner]);
      },
    );

    test(
      'uses an owner default directory when the argument is absent',
      () async {
        final owner = _owner('owner-a');
        final harness = _Harness();

        await harness.handler.handle(
          _request(
            owner: owner,
            arguments: const {'command': 'pwd'},
            defaultWorkingDirectory: '$_ownerARoot/packages/app',
          ),
        );

        expect(
          harness.execution.calls.single.request.workingDirectory,
          '$_ownerARoot/packages/app',
        );
        expect(
          harness.rules.evaluations.single.request.workingDirectory,
          '$_ownerARoot/packages/app',
        );
      },
    );

    test(
      'resolves explicit working_directory and cwd inside the root',
      () async {
        final owner = _owner('owner-a');
        final harness = _Harness();

        await harness.handler.handle(
          _request(
            owner: owner,
            arguments: const {
              'command': 'pwd',
              'working_directory': 'packages/app',
            },
          ),
        );
        await harness.handler.handle(
          _request(
            owner: owner,
            arguments: const {
              'command': ' pwd<|im_end|> ',
              'working_directory': ' ',
              'cwd': '$_ownerARoot/tools',
            },
          ),
        );

        expect(
          harness.execution.calls.map((call) => call.request.workingDirectory),
          ['$_ownerARoot/packages/app', '$_ownerARoot/tools'],
        );
        expect(harness.execution.calls.map((call) => call.request.command), [
          'pwd',
          'pwd',
        ]);
        expect(
          harness.execution.calls.last.request.arguments['cwd'],
          '$_ownerARoot/tools',
        );
      },
    );

    test('rejects relative, absolute, and default directory escapes', () async {
      final owner = _owner('owner-a');
      final cases = <LocalCommandToolRequest>[
        _request(
          owner: owner,
          arguments: const {
            'command': 'pwd',
            'working_directory': '../outside',
          },
        ),
        _request(
          owner: owner,
          arguments: const {
            'command': 'pwd',
            'working_directory': '/workspace/outside',
          },
        ),
        _request(
          owner: owner,
          arguments: const {'command': 'pwd'},
          defaultWorkingDirectory: '/workspace/outside',
        ),
      ];
      const expectedPayload =
          '{"code":"working_directory_outside_project",'
          '"error":"working_directory must resolve inside the selected coding project"}';

      for (final request in cases) {
        final harness = _Harness();
        final result = await harness.handler.handle(request);

        expect(result.toolName, _toolName);
        expect(result.result, expectedPayload);
        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'working_directory must resolve inside the selected coding project',
        );
        expect(harness.rules.evaluations, isEmpty);
        expect(harness.approval.totalCalls, 0);
        expect(harness.execution.calls, isEmpty);
      }
    });

    test('rejects a missing owner directory boundary exactly', () async {
      final harness = _Harness();
      final result = await harness.handler.handle(
        _request(
          owner: _owner('owner-a'),
          allowedRoot: '',
          arguments: const {'command': 'pwd'},
        ),
      );

      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'command is required and working_directory must be provided or '
        'inferred from the selected coding project',
      );
      expect(harness.execution.calls, isEmpty);
    });

    test('applies an exact-owner saved deny before approval', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..rules.decisions[owner] = CommandPermissionRuleDecision.deny;

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'Local command was denied by a saved permission rule',
      );
      expect(harness.approval.expiredOwners, [owner]);
      expect(harness.approval.totalCalls, 1);
      expect(harness.execution.calls, isEmpty);
    });

    test(
      'uses a local saved allow but never uses it for remote execution',
      () async {
        final owner = _owner('owner-a');
        final localHarness = _Harness()
          ..rules.decisions[owner] = CommandPermissionRuleDecision.allow;
        final remoteHarness = _Harness()
          ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
          ..approval.gates[owner] = ToolApprovalGateDecision.fullAccess;

        await localHarness.handler.handle(_request(owner: owner));
        await remoteHarness.handler.handle(
          _request(owner: owner, remote: true),
        );

        expect(localHarness.execution.calls, hasLength(1));
        expect(localHarness.approval.resolveCalls, isEmpty);
        expect(localHarness.approval.rememberedResults, isEmpty);
        expect(remoteHarness.execution.calls, hasLength(1));
        expect(remoteHarness.approval.resolveCalls.single.owner, owner);
        expect(remoteHarness.approval.manualCalls, isEmpty);
        expect(remoteHarness.approval.rememberedResults, isEmpty);
      },
    );

    test('runs a remote read-only command without approval', () async {
      final owner = _owner('owner-a');
      final harness = _Harness();

      await harness.handler.handle(
        _request(
          owner: owner,
          remote: true,
          arguments: const {'command': 'git status --short'},
        ),
      );

      expect(harness.execution.calls, hasLength(1));
      expect(harness.approval.resolveCalls, isEmpty);
      expect(harness.approval.manualCalls, isEmpty);
    });

    test('executes a manual approval and remembers its result', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.needsManualApproval
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: true,
        );
      final toolRequest = _request(
        owner: owner,
        toolCallId: 'local-command-approval-17',
        arguments: const {
          'command': 'touch output.txt',
          'reason': 'Create the requested artifact',
        },
      );

      final result = await harness.handler.handle(toolRequest);

      expect(result, same(harness.execution.results.single));
      expect(harness.approval.resolveCalls.single.owner, owner);
      final approvalRequest = harness.approval.manualCalls.single.request;
      expect(approvalRequest.toolCallId, 'local-command-approval-17');
      expect(approvalRequest.execution.toolCallId, 'local-command-approval-17');
      expect(approvalRequest.execution.command, 'touch output.txt');
      expect(approvalRequest.execution.workingDirectory, _ownerARoot);
      expect(approvalRequest.reason, 'Create the requested artifact');
      expect(approvalRequest.warningTitle, isNull);
      expect(approvalRequest.warningMessage, isNull);
      expect(harness.execution.calls.single.owner, owner);
      expect(harness.execution.settlements, hasLength(1));
      expect(
        harness.execution.calls.single.request.toolCallId,
        'local-command-approval-17',
      );
      expect(harness.approval.rememberedResults.single.owner, owner);
      expect(
        harness.approval.rememberedResults.single.request,
        same(approvalRequest),
      );
    });

    test('maps a manual denial to the exact cached payload', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: false,
        );

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result.toolName, _toolName);
      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'User denied local command execution');
      expect(harness.execution.calls, isEmpty);
      expect(harness.approval.rememberedDenials, hasLength(1));
      expect(harness.approval.rememberedDenials.single.result, same(result));
    });

    test(
      'forces explicit approval and forwards the exact risk warning',
      () async {
        final owner = _owner('owner-a');
        final harness = _Harness()
          ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
          ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
            approved: true,
          );

        await harness.handler.handle(
          _request(owner: owner, arguments: const {'command': 'rm -rf build'}),
        );

        expect(harness.approval.resolveCalls, hasLength(1));
        final request = harness.approval.manualCalls.single.request;
        expect(request.warningTitle, 'Recursive file deletion');
        expect(
          request.warningMessage,
          'This command can permanently remove files or directories. '
          'Review the target path before approving it.',
        );
        expect(harness.execution.calls, hasLength(1));
      },
    );

    test('persists an exact remembered allow rule for the owner', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: true,
          rememberedAction: RememberedCommandPermissionAction.allow,
          rememberedMatch: RememberedCommandPermissionMatch.exact,
        );

      await harness.handler.handle(
        _request(
          owner: owner,
          arguments: const {
            'command': 'dart format lib',
            'working_directory': 'packages/app',
          },
        ),
      );

      expect(harness.rules.rememberedRules, hasLength(1));
      final remembered = harness.rules.rememberedRules.single;
      expect(remembered.owner, owner);
      expect(remembered.rule.action, RememberedCommandPermissionAction.allow);
      expect(remembered.rule.match, RememberedCommandPermissionMatch.exact);
      expect(remembered.rule.command, 'dart format lib');
      expect(remembered.rule.workingDirectory, '$_ownerARoot/packages/app');
      expect(harness.execution.calls, hasLength(1));
    });

    test('persists a remembered deny before returning the denial', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: false,
          rememberedAction: RememberedCommandPermissionAction.deny,
          rememberedMatch: RememberedCommandPermissionMatch.prefix,
        );

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result.errorMessage, 'User denied local command execution');
      expect(harness.rules.rememberedRules, hasLength(1));
      expect(
        harness.rules.rememberedRules.single.rule.action,
        RememberedCommandPermissionAction.deny,
      );
      expect(
        harness.rules.rememberedRules.single.rule.match,
        RememberedCommandPermissionMatch.prefix,
      );
      expect(harness.execution.calls, isEmpty);
    });

    test('does not persist a remembered rule for remote interaction', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: true,
          rememberedAction: RememberedCommandPermissionAction.allow,
          rememberedMatch: RememberedCommandPermissionMatch.exact,
        );

      await harness.handler.handle(_request(owner: owner, remote: true));

      expect(harness.rules.rememberedRules, isEmpty);
      expect(harness.execution.calls, hasLength(1));
    });

    test('returns a cached denial without resolving approval again', () async {
      final owner = _owner('owner-a');
      final cached = _toolResult(
        '',
        isSuccess: false,
        errorMessage: 'Previously denied',
      );
      final harness = _Harness()..approval.cachedDenials[owner] = cached;

      final result = await harness.handler.handle(_request(owner: owner));

      expect(result, same(cached));
      expect(harness.approval.lookupCalls, hasLength(1));
      expect(harness.approval.resolveCalls, isEmpty);
      expect(harness.execution.calls, isEmpty);
    });

    test('maps auto-review denial to the exact cached payload', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.denied(
          'Unsafe external input',
        );

      final result = await harness.handler.handle(_request(owner: owner));

      expect(
        result.result,
        'Auto-review denied this action. Rationale: Unsafe external input',
      );
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'Auto-review denied: Unsafe external input');
      expect(harness.approval.rememberedDenials, hasLength(1));
      expect(harness.approval.manualCalls, isEmpty);
      expect(harness.execution.calls, isEmpty);
    });

    test(
      'preserves exact exit, timeout, and execution-error payloads',
      () async {
        final owner = _owner('owner-a');
        final payloads = <String>[
          jsonEncode({
            'command': 'dart test',
            'working_directory': _ownerARoot,
            'exit_code': 2,
            'stdout': '',
            'stderr': 'tests failed',
          }),
          jsonEncode({
            'command': 'dart test',
            'working_directory': _ownerARoot,
            'stdout': 'partial output',
            'stderr': '',
            'error': 'Command timed out after 60 seconds.',
            'timed_out': true,
            'timeout_ms': 60000,
            'process_terminated': true,
          }),
          jsonEncode({
            'command': 'dart test',
            'working_directory': _ownerARoot,
            'error': 'ProcessException: executable not found',
          }),
        ];

        for (final payload in payloads) {
          final expected = _toolResult(payload);
          final harness = _Harness()
            ..approval.gates[owner] = ToolApprovalGateDecision.fullAccess
            ..execution.nextResult = expected;

          final result = await harness.handler.handle(
            _request(owner: owner, arguments: const {'command': 'dart test'}),
          );

          expect(result, same(expected));
          expect(result.result, payload);
          expect(result.isSuccess, isTrue);
          expect(
            harness.execution.calls.single.request.timeout,
            const Duration(seconds: 60),
          );
        }
      },
    );

    test('propagates execution exceptions without caching a result', () async {
      final owner = _owner('owner-a');
      final executionError = StateError('command execution failed');
      final harness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.autoReviewAllowed
        ..execution.error = executionError;

      await expectLater(
        harness.handler.handle(_request(owner: owner)),
        throwsA(same(executionError)),
      );

      expect(harness.execution.calls.single.owner, owner);
      expect(harness.approval.rememberedDenials, isEmpty);
      expect(harness.approval.rememberedResults, isEmpty);
    });

    test('propagates approval exceptions before execution', () async {
      final owner = _owner('owner-a');
      final approvalError = StateError('approval resolution failed');
      final harness = _Harness()..approval.gateError = approvalError;

      await expectLater(
        harness.handler.handle(_request(owner: owner)),
        throwsA(same(approvalError)),
      );

      expect(harness.approval.resolveCalls.single.owner, owner);
      expect(harness.approval.manualCalls, isEmpty);
      expect(harness.approval.rememberedDenials, isEmpty);
      expect(harness.approval.rememberedResults, isEmpty);
      expect(harness.execution.calls, isEmpty);
    });

    test(
      'propagates remembered-rule failures before command execution',
      () async {
        final owner = _owner('owner-a');
        final rememberError = StateError('rule persistence failed');
        final harness = _Harness()
          ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
            approved: true,
            rememberedAction: RememberedCommandPermissionAction.allow,
            rememberedMatch: RememberedCommandPermissionMatch.exact,
          )
          ..rules.rememberError = rememberError;

        await expectLater(
          harness.handler.handle(_request(owner: owner)),
          throwsA(same(rememberError)),
        );

        expect(harness.rules.rememberAttempts.single.owner, owner);
        expect(harness.rules.rememberedRules, isEmpty);
        expect(harness.approval.rememberedResults, isEmpty);
        expect(harness.execution.calls, isEmpty);
      },
    );

    test('rejects poisoned gate completions before any side effect', () async {
      final owner = _owner('owner-a');
      const toolCallId = 'gate-call';

      for (final poison in _poisonScopes(owner, toolCallId)) {
        final harness = _Harness()
          ..approval.nextGateCompletion = LocalCommandCompletion.completed(
            owner: poison.owner,
            toolCallId: poison.toolCallId,
            value: ToolApprovalGateDecision.fullAccess,
          );

        await expectLater(
          harness.handler.handle(
            _request(owner: owner, toolCallId: toolCallId),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Local command gate ${poison.error}',
            ),
          ),
        );
        expect(harness.approval.manualCalls, isEmpty);
        expect(harness.approval.rememberedDenials, isEmpty);
        expect(harness.execution.calls, isEmpty);
      }
    });

    test(
      'rejects poisoned manual completions before rules or execution',
      () async {
        final owner = _owner('owner-a');
        const toolCallId = 'manual-call';

        for (final poison in _poisonScopes(owner, toolCallId)) {
          final harness = _Harness()
            ..approval.nextManualCompletion = LocalCommandCompletion.completed(
              owner: poison.owner,
              toolCallId: poison.toolCallId,
              value: const LocalCommandManualApproval(approved: true),
            );

          await expectLater(
            harness.handler.handle(
              _request(owner: owner, toolCallId: toolCallId),
            ),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                'Local command manual approval ${poison.error}',
              ),
            ),
          );
          expect(harness.rules.rememberAttempts, isEmpty);
          expect(harness.approval.rememberedResults, isEmpty);
          expect(harness.execution.calls, isEmpty);
        }
      },
    );

    test('maps ownerExpired gate and manual completions exactly', () async {
      final owner = _owner('owner-a');
      const toolCallId = 'expired-approval-call';
      final gateHarness = _Harness()
        ..approval.nextGateCompletion = LocalCommandCompletion.ownerExpired(
          owner: owner,
          toolCallId: toolCallId,
        );

      final gateResult = await gateHarness.handler.handle(
        _request(owner: owner, toolCallId: toolCallId),
      );
      _expectExpired(gateResult);
      expect(gateHarness.approval.manualCalls, isEmpty);
      expect(gateHarness.execution.calls, isEmpty);

      final manualHarness = _Harness()
        ..approval.nextManualCompletion = LocalCommandCompletion.ownerExpired(
          owner: owner,
          toolCallId: toolCallId,
        );
      final manualResult = await manualHarness.handler.handle(
        _request(owner: owner, toolCallId: toolCallId),
      );
      _expectExpired(manualResult);
      expect(manualHarness.rules.rememberAttempts, isEmpty);
      expect(manualHarness.execution.calls, isEmpty);
    });

    test('rejects poisoned rule writes and never executes them', () async {
      final owner = _owner('owner-a');
      const toolCallId = 'rule-call';

      for (final poison in _poisonScopes(owner, toolCallId)) {
        final harness = _Harness()
          ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
            approved: true,
            rememberedAction: RememberedCommandPermissionAction.allow,
            rememberedMatch: RememberedCommandPermissionMatch.exact,
          )
          ..rules.nextCompletion = LocalCommandCompletion<Object?>.completed(
            owner: poison.owner,
            toolCallId: poison.toolCallId,
            value: null,
          );

        await expectLater(
          harness.handler.handle(
            _request(owner: owner, toolCallId: toolCallId),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'Local command permission rule write ${poison.error}',
            ),
          ),
        );
        expect(harness.rules.rememberedRules, isEmpty);
        expect(harness.execution.calls, isEmpty);
        expect(harness.approval.rememberedResults, isEmpty);
      }
    });

    test('ownerExpired rule writes are not committed or executed', () async {
      final owner = _owner('owner-a');
      const toolCallId = 'stale-rule-call';
      final harness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: true,
          rememberedAction: RememberedCommandPermissionAction.allow,
          rememberedMatch: RememberedCommandPermissionMatch.exact,
        )
        ..rules.nextCompletion = LocalCommandCompletion<Object?>.ownerExpired(
          owner: owner,
          toolCallId: toolCallId,
        );

      final result = await harness.handler.handle(
        _request(owner: owner, toolCallId: toolCallId),
      );

      _expectExpired(result);
      expect(harness.rules.rememberAttempts, hasLength(1));
      expect(harness.rules.rememberedRules, isEmpty);
      expect(harness.execution.calls, isEmpty);
      expect(harness.approval.rememberedResults, isEmpty);
    });

    test(
      'rejects poisoned execution scope and tool names before caching',
      () async {
        final owner = _owner('owner-a');
        const toolCallId = 'execution-call';
        final success = _toolResult('completed');

        for (final poison in _poisonScopes(owner, toolCallId)) {
          final harness = _Harness()
            ..execution.nextCompletion = LocalCommandCompletion.completed(
              owner: poison.owner,
              toolCallId: poison.toolCallId,
              value: success,
            );

          final result = await harness.handler.handle(
            _request(owner: owner, toolCallId: toolCallId),
          );
          _expectEffectUncertain(result);
          expect(harness.approval.rememberedResults, isEmpty);
        }

        final wrongToolHarness = _Harness()
          ..execution.nextResult = const McpToolResult(
            toolName: 'other_tool',
            result: 'completed',
            isSuccess: true,
          );
        final wrongToolResult = await wrongToolHarness.handler.handle(
          _request(owner: owner, toolCallId: toolCallId),
        );
        _expectEffectUncertain(wrongToolResult);
        expect(wrongToolHarness.approval.rememberedResults, isEmpty);

        final wrongCachedHarness = _Harness()
          ..approval.cachedDenials[owner] = const McpToolResult(
            toolName: 'other_tool',
            result: '',
            isSuccess: false,
          );
        await expectLater(
          wrongCachedHarness.handler.handle(_request(owner: owner)),
          throwsA(isA<StateError>()),
        );
        expect(wrongCachedHarness.approval.resolveCalls, isEmpty);
      },
    );

    test(
      'stale read-only, preapproved, and gated execution is never cached',
      () async {
        final owner = _owner('owner-a');
        final readOnly = _Harness();
        final preapproved = _Harness()
          ..rules.decisions[owner] = CommandPermissionRuleDecision.allow;
        final gated = _Harness();
        final cases =
            <
              ({
                String label,
                _Harness harness,
                LocalCommandToolRequest request,
              })
            >[
              (
                label: 'read-only',
                harness: readOnly,
                request: _request(
                  owner: owner,
                  toolCallId: 'read-only-call',
                  arguments: const {'command': 'git status --short'},
                ),
              ),
              (
                label: 'preapproved',
                harness: preapproved,
                request: _request(owner: owner, toolCallId: 'preapproved-call'),
              ),
              (
                label: 'gated',
                harness: gated,
                request: _request(owner: owner, toolCallId: 'gated-call'),
              ),
            ];

        for (final testCase in cases) {
          testCase.harness.execution.nextCompletion =
              LocalCommandCompletion.ownerExpired(
                owner: owner,
                toolCallId: testCase.request.toolCallId,
              );

          final result = await testCase.harness.handler.handle(
            testCase.request,
          );

          _expectEffectUncertain(result);
          expect(
            testCase.harness.approval.rememberedResults,
            isEmpty,
            reason: testCase.label,
          );
        }
      },
    );

    test('expiry takes precedence over a saved denial', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..rules.decisions[owner] = CommandPermissionRuleDecision.deny
        ..approval.expirationQueue.add(true);

      final result = await harness.handler.handle(_request(owner: owner));

      _expectExpired(result);
      expect(harness.rules.evaluations, isEmpty);
      expect(harness.execution.calls, isEmpty);
    });

    test('rejects a cached denial from another exact call', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.nextCachedDenialCompletion =
            LocalCommandCompletion.completed(
              owner: owner,
              toolCallId: 'another-call',
              value: _toolResult('denied', isSuccess: false),
            );

      final result = await harness.handler.handle(_request(owner: owner));

      _expectExpired(result);
      expect(harness.approval.resolveCalls, isEmpty);
      expect(harness.execution.calls, isEmpty);
    });

    test(
      'does not trust a denial-cache acknowledgement from another call',
      () async {
        final owner = _owner('owner-a');
        final harness = _Harness()
          ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
            approved: false,
          )
          ..approval.nextRememberDenialCompletion =
              LocalCommandCompletion<Object?>.completed(
                owner: owner,
                toolCallId: 'another-call',
                value: null,
              );

        final result = await harness.handler.handle(_request(owner: owner));

        _expectExpired(result);
        expect(harness.approval.rememberedDenials, hasLength(1));
        expect(harness.execution.calls, isEmpty);
      },
    );

    test(
      'warns when result-cache acknowledgement belongs to another call',
      () async {
        final owner = _owner('owner-a');
        final harness = _Harness()
          ..approval.nextRememberResultCompletion =
              LocalCommandCompletion<Object?>.completed(
                owner: owner,
                toolCallId: 'another-call',
                value: null,
              );

        final result = await harness.handler.handle(_request(owner: owner));

        _expectEffectUncertain(result);
        expect(harness.execution.calls, hasLength(1));
        expect(harness.approval.rememberedResults, hasLength(1));
        expect(harness.execution.settlements, isEmpty);
      },
    );

    test('warns when the owner expires during result persistence', () async {
      final owner = _owner('owner-a');
      final harness = _Harness();
      harness.approval.afterRememberResult = () {
        harness.approval.expirationQueue.add(true);
      };

      final result = await harness.handler.handle(_request(owner: owner));

      _expectEffectUncertain(result);
      expect(harness.execution.calls, hasLength(1));
      expect(harness.approval.rememberedResults, hasLength(1));
      expect(harness.execution.settlements, isEmpty);
    });

    test(
      'retains execution settlement when result persistence throws',
      () async {
        final owner = _owner('owner-a');
        final harness = _Harness()
          ..approval.rememberResultError = StateError('cache write failed');

        final result = await harness.handler.handle(_request(owner: owner));

        _expectEffectUncertain(result);
        expect(harness.approval.rememberedResults, hasLength(1));
        expect(harness.execution.settlements, isEmpty);
      },
    );

    test('warns when final execution settlement is not accepted', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()..execution.settlementResult = false;

      final result = await harness.handler.handle(_request(owner: owner));

      _expectEffectUncertain(result);
      expect(harness.execution.settlements, hasLength(1));
    });

    test('warns when execution throws after the owner expires', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()..execution.error = StateError('late failure');
      harness.execution.afterExecute = () {
        harness.approval.expirationQueue.add(true);
      };

      final result = await harness.handler.handle(_request(owner: owner));

      _expectEffectUncertain(result);
      expect(harness.approval.rememberedResults, isEmpty);
    });

    test('rejects expired owners before and after manual approval', () async {
      final owner = _owner('owner-a');
      final preHarness = _Harness()
        ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
        ..approval.expirationQueue.add(true);

      final preResult = await preHarness.handler.handle(_request(owner: owner));
      _expectExpired(preResult);
      expect(preHarness.execution.calls, isEmpty);

      final postHarness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: true,
          rememberedAction: RememberedCommandPermissionAction.allow,
          rememberedMatch: RememberedCommandPermissionMatch.exact,
        )
        ..approval.expirationQueue.addAll([false, true]);

      final postResult = await postHarness.handler.handle(
        _request(owner: owner),
      );
      _expectExpired(postResult);
      expect(postHarness.rules.rememberedRules, isEmpty);
      expect(postHarness.execution.calls, isEmpty);
    });

    test('rejects expiration immediately before approved execution', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.autoReviewAllowed
        ..approval.expirationQueue.addAll([false, true]);

      final result = await harness.handler.handle(_request(owner: owner));

      _expectExpired(result);
      expect(harness.approval.manualCalls, isEmpty);
      expect(harness.execution.calls, isEmpty);
      expect(harness.approval.rememberedResults, isEmpty);
    });

    test('never reads visible-owner roots or permission decisions', () async {
      final ownerA = _owner('same-conversation', generation: 1);
      final visibleOwnerB = _owner('same-conversation', generation: 2);
      const visibleRoot = _ownerBRoot;
      final deniedHarness = _Harness()
        ..rules.decisions[ownerA] = CommandPermissionRuleDecision.deny
        ..rules.decisions[visibleOwnerB] = CommandPermissionRuleDecision.allow;

      final denied = await deniedHarness.handler.handle(
        _request(
          owner: ownerA,
          allowedRoot: _ownerARoot,
          arguments: const {
            'command': 'touch owner-a.txt',
            'working_directory': 'package',
          },
        ),
      );

      expect(denied.errorMessage, contains('saved permission rule'));
      expect(deniedHarness.rules.evaluations.single.owner, ownerA);
      expect(deniedHarness.execution.calls, isEmpty);

      final executionHarness = _Harness()
        ..rules.decisions[ownerA] = CommandPermissionRuleDecision.ask
        ..rules.decisions[visibleOwnerB] = CommandPermissionRuleDecision.deny
        ..approval.gates[ownerA] = ToolApprovalGateDecision.fullAccess
        ..approval.gates[visibleOwnerB] = ToolApprovalGateDecision.denied(
          'Visible owner denied',
        );

      await executionHarness.handler.handle(
        _request(
          owner: ownerA,
          allowedRoot: _ownerARoot,
          arguments: const {
            'command': 'touch owner-a.txt',
            'working_directory': 'package',
          },
        ),
      );

      final execution = executionHarness.execution.calls.single;
      expect(execution.owner, ownerA);
      expect(execution.request.workingDirectory, '$_ownerARoot/package');
      expect(
        execution.request.workingDirectory,
        isNot(startsWith(visibleRoot)),
      );
      expect(executionHarness.approval.resolveCalls.single.owner, ownerA);
      expect(
        executionHarness.approval.resolveCalls.single.owner,
        isNot(visibleOwnerB),
      );
    });
  });
}

final class _Harness {
  _Harness()
    : execution = _FakeExecutionPort(),
      approval = _FakeApprovalPort(),
      rules = _FakeRuleStore() {
    handler = LocalCommandToolHandler(
      executionPort: execution,
      approvalPort: approval,
      permissionRuleStorePort: rules,
    );
  }

  final _FakeExecutionPort execution;
  final _FakeApprovalPort approval;
  final _FakeRuleStore rules;
  late final LocalCommandToolHandler handler;
}

typedef _ExecutionCall = ({
  ChatTurnOwner owner,
  LocalCommandExecutionRequest request,
});

final class _FakeExecutionPort implements LocalCommandExecutionPort {
  final List<_ExecutionCall> calls = [];
  final List<McpToolResult> results = [];
  final List<LocalCommandOperationIdentity> settlements = [];
  LocalCommandCompletion<McpToolResult>? nextCompletion;
  McpToolResult? nextResult;
  void Function()? afterExecute;
  Object? error;
  Object? settlementError;
  bool settlementResult = true;

  @override
  Future<LocalCommandCompletion<McpToolResult>> execute(
    ChatTurnOwner owner,
    LocalCommandExecutionRequest request,
  ) async {
    calls.add((owner: owner, request: request));
    afterExecute?.call();
    if (error case final error?) {
      throw error;
    }
    if (nextCompletion case final completion?) {
      if (completion.value case final result?) results.add(result);
      return completion;
    }
    final result =
        nextResult ??
        _toolResult(
          jsonEncode({
            'command': request.command,
            'working_directory': request.workingDirectory,
            'exit_code': 0,
            'stdout': '',
            'stderr': '',
          }),
        );
    results.add(result);
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: request.toolCallId,
      value: result,
      effectDisposition: LocalCommandEffectDisposition.settlementRequired,
      effectSettlement: LocalCommandEffectSettlement(
        identity: request.identityFor(owner),
        settle: () {
          settlements.add(request.identityFor(owner));
          if (settlementError case final error?) throw error;
          return settlementResult;
        },
      ),
    );
  }
}

typedef _RuleEvaluation = ({
  ChatTurnOwner owner,
  CommandPermissionRuleRequest request,
});
typedef _RememberedRule = ({
  ChatTurnOwner owner,
  String toolCallId,
  RememberedCommandPermissionRule rule,
});

final class _FakeRuleStore implements CommandPermissionRuleStorePort {
  final Map<ChatTurnOwner, CommandPermissionRuleDecision> decisions = {};
  final List<_RuleEvaluation> evaluations = [];
  final List<_RememberedRule> rememberAttempts = [];
  final List<_RememberedRule> rememberedRules = [];
  LocalCommandCompletion<Object?>? nextCompletion;
  Object? rememberError;

  @override
  CommandPermissionRuleDecision evaluate(
    ChatTurnOwner owner,
    CommandPermissionRuleRequest request,
  ) {
    evaluations.add((owner: owner, request: request));
    return decisions[owner] ?? CommandPermissionRuleDecision.ask;
  }

  @override
  Future<LocalCommandCompletion<Object?>> remember(
    ChatTurnOwner owner,
    String toolCallId,
    RememberedCommandPermissionRule rule,
  ) async {
    final use = (owner: owner, toolCallId: toolCallId, rule: rule);
    rememberAttempts.add(use);
    if (rememberError case final error?) {
      throw error;
    }
    final completion =
        nextCompletion ??
        LocalCommandCompletion<Object?>.completed(
          owner: owner,
          toolCallId: toolCallId,
          value: null,
        );
    if (completion.disposition == LocalCommandCompletionDisposition.completed &&
        completion.owner == owner &&
        completion.toolCallId == toolCallId) {
      rememberedRules.add(use);
    }
    return completion;
  }
}

typedef _ApprovalCall = ({
  ChatTurnOwner owner,
  LocalCommandApprovalRequest request,
});
typedef _ManualApprovalCall = ({
  ChatTurnOwner owner,
  LocalCommandApprovalRequest request,
  ToolApprovalGateDecision gate,
});
typedef _RememberedApprovalResult = ({
  ChatTurnOwner owner,
  LocalCommandApprovalRequest request,
  McpToolResult result,
});

final class _FakeApprovalPort implements LocalCommandApprovalPort {
  final Map<ChatTurnOwner, McpToolResult> cachedDenials = {};
  final Map<ChatTurnOwner, ToolApprovalGateDecision> gates = {};
  final Map<ChatTurnOwner, LocalCommandManualApproval> manualDecisions = {};
  final List<bool> expirationQueue = [];
  final List<ChatTurnOwner> expiredOwners = [];
  final List<String> expiredToolCallIds = [];
  final List<_ApprovalCall> lookupCalls = [];
  final List<_ApprovalCall> resolveCalls = [];
  final List<_ManualApprovalCall> manualCalls = [];
  final List<_RememberedApprovalResult> rememberedDenials = [];
  final List<_RememberedApprovalResult> rememberedResults = [];
  LocalCommandCompletion<ToolApprovalGateDecision>? nextGateCompletion;
  LocalCommandCompletion<LocalCommandManualApproval>? nextManualCompletion;
  LocalCommandCompletion<McpToolResult>? nextCachedDenialCompletion;
  LocalCommandCompletion<Object?>? nextRememberDenialCompletion;
  LocalCommandCompletion<Object?>? nextRememberResultCompletion;
  void Function()? afterRememberDenial;
  void Function()? afterRememberResult;
  Object? gateError;
  Object? rememberResultError;

  int get totalCalls =>
      expiredOwners.length +
      lookupCalls.length +
      resolveCalls.length +
      manualCalls.length +
      rememberedDenials.length +
      rememberedResults.length;

  @override
  LocalCommandCompletion<McpToolResult>? lookupDenial(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
  ) {
    lookupCalls.add((owner: owner, request: request));
    final cached = cachedDenials[owner];
    return nextCachedDenialCompletion ??
        (cached == null
            ? null
            : LocalCommandCompletion.completed(
                owner: owner,
                toolCallId: request.toolCallId,
                value: cached,
              ));
  }

  @override
  Future<LocalCommandCompletion<ToolApprovalGateDecision>> resolveGate(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
  ) async {
    resolveCalls.add((owner: owner, request: request));
    if (gateError case final error?) {
      throw error;
    }
    return nextGateCompletion ??
        LocalCommandCompletion.completed(
          owner: owner,
          toolCallId: request.toolCallId,
          value: gates[owner] ?? ToolApprovalGateDecision.needsManualApproval,
        );
  }

  @override
  Future<LocalCommandCompletion<LocalCommandManualApproval>>
  requestManualApproval(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    ToolApprovalGateDecision gate,
  ) async {
    manualCalls.add((owner: owner, request: request, gate: gate));
    return nextManualCompletion ??
        LocalCommandCompletion.completed(
          owner: owner,
          toolCallId: request.toolCallId,
          value:
              manualDecisions[owner] ??
              const LocalCommandManualApproval(approved: true),
        );
  }

  @override
  bool isExpired(ChatTurnOwner owner, String toolCallId) {
    expiredOwners.add(owner);
    expiredToolCallIds.add(toolCallId);
    if (expirationQueue.isEmpty) return false;
    return expirationQueue.removeAt(0);
  }

  @override
  LocalCommandCompletion<Object?> rememberDenial(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    McpToolResult result,
  ) {
    rememberedDenials.add((owner: owner, request: request, result: result));
    afterRememberDenial?.call();
    return nextRememberDenialCompletion ??
        LocalCommandCompletion.completed(
          owner: owner,
          toolCallId: request.toolCallId,
          value: null,
        );
  }

  @override
  LocalCommandCompletion<Object?> rememberResult(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    McpToolResult result,
  ) {
    rememberedResults.add((owner: owner, request: request, result: result));
    afterRememberResult?.call();
    if (rememberResultError case final error?) throw error;
    return nextRememberResultCompletion ??
        LocalCommandCompletion.completed(
          owner: owner,
          toolCallId: request.toolCallId,
          value: null,
        );
  }
}

final class _MutableArgument {
  var value = 0;
}
