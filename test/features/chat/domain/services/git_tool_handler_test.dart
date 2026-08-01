import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/git_process_execution_coordinator.dart';
import 'package:caverno/features/chat/domain/services/git_tool_handler.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 3,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 3,
  );

  group('GitToolHandler command execution', () {
    test('recursively freezes captured and normalized arguments', () async {
      final nested = <String, dynamic>{
        'items': <Object?>[
          <String, dynamic>{'owner': 'owner-a', 'value': 'captured'},
        ],
      };
      final source = <String, dynamic>{
        'command': 'git status',
        'working_directory': 'repo',
        'metadata': nested,
      };
      final fixture = _fixture();
      final input = _input(ownerA, source);

      source['command'] = 'commit -am changed';
      (nested['items'] as List).add('changed');
      (nested['items'] as List).first['value'] = 'changed';
      (nested['items'] as List).first['owner'] = 'visible';
      final result = await fixture.handler.handleExecuteCommand(input);

      expect(result.isSuccess, isTrue);
      expect(input.arguments['command'], 'git status');
      final capturedNested = input.arguments['metadata'] as Map;
      final capturedItems = capturedNested['items'] as List;
      expect(capturedItems, [
        {'owner': 'owner-a', 'value': 'captured'},
      ]);
      expect(fixture.execution.calls.single.request.command, 'status');
      expect(
        fixture.execution.calls.single.request.workingDirectory,
        '/repo/a/repo',
      );
      expect(
        fixture.execution.calls.single.request.arguments['metadata'],
        capturedNested,
      );
      expect(
        () => input.arguments['command'] = 'mutate',
        throwsUnsupportedError,
      );
      expect(() => capturedNested['new'] = true, throwsUnsupportedError);
      expect(() => capturedItems.add('mutate'), throwsUnsupportedError);
      expect(
        () => (capturedItems.first as Map)['value'] = 'mutate',
        throwsUnsupportedError,
      );
      expect(
        () => (capturedItems.first as Map)['owner'] = 'mutate',
        throwsUnsupportedError,
      );
    });

    test('rejects non-JSON command arguments before execution', () {
      for (final invalidValue in <Object?>[
        <Object?>{'owner-a'},
        <Object?, Object?>{7: 'owner-a'},
        double.nan,
      ]) {
        expect(
          () => _input(ownerA, {
            'command': 'status',
            'working_directory': '/repo',
            'invalid': invalidValue,
          }),
          throwsArgumentError,
          reason: invalidValue.runtimeType.toString(),
        );
      }
    });

    test('maps invalid command and working directory exactly', () async {
      final missingCommand = _fixture();
      final commandResult = await missingCommand.handler.handleExecuteCommand(
        _input(ownerA, const {'command': 'git'}, repositoryPath: '/repo/a'),
      );
      expect(commandResult.result, isEmpty);
      expect(commandResult.isSuccess, isFalse);
      expect(
        commandResult.errorMessage,
        'command is required and working_directory must be provided or inferred from the selected coding project',
      );

      final missingDirectory = _fixture();
      final directoryResult = await missingDirectory.handler
          .handleExecuteCommand(
            _input(ownerA, const {
              'command': 'commit -m initial',
            }, repositoryPath: null),
          );
      expect(
        directoryResult.errorMessage,
        'command is required and working_directory must be provided or inferred from the selected coding project',
      );
      expect(missingCommand.events, isEmpty);
      expect(missingDirectory.events, isEmpty);
    });

    test('normalizes paths from the exact owner repository', () async {
      final fixture = _fixture();

      await fixture.handler.handleExecuteCommand(
        _input(ownerA, const {
          'command': 'git git status',
          'working_directory': 'packages/a',
        }, repositoryPath: '/repositories/a'),
      );
      await fixture.handler.handleExecuteCommand(
        _input(ownerB, const {
          'command': 'status',
          'cwd': 'packages/b',
        }, repositoryPath: '/repositories/b'),
      );

      expect(fixture.execution.calls.map((call) => call.owner), [
        ownerA,
        ownerB,
      ]);
      expect(
        fixture.execution.calls.map((call) => call.request.workingDirectory),
        ['/repositories/a/packages/a', '/repositories/b/packages/b'],
      );
      expect(fixture.execution.calls.first.request.arguments['cwd'], isNull);
      expect(
        fixture.execution.calls.last.request.arguments['cwd'],
        'packages/b',
      );
      expect(
        jsonEncode(fixture.execution.calls.first.request.arguments),
        isNot(contains('/repositories/b')),
      );
    });

    test('read-only commands bypass every approval operation', () async {
      final fixture = _fixture(
        gate: ToolApprovalGateDecision.denied('must not be consulted'),
        expired: _failure('git_execute_command', 'expired'),
      );

      final result = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA, command: 'git status'),
      );

      expect(result, fixture.execution.result);
      expect(fixture.events, ['execute-command:conversation-a']);
      expect(fixture.approval.lookups, isEmpty);
      expect(fixture.approval.expirationChecks, isEmpty);
    });

    test(
      'returns an owner-scoped cached denial before gate resolution',
      () async {
        final cached = _failure('git_execute_command', 'cached denial');
        final fixture = _fixture(cachedDenials: {ownerA: cached});

        final result = await fixture.handler.handleExecuteCommand(
          _commandInput(ownerA),
        );

        expect(result, cached);
        expect(fixture.events, ['lookup:conversation-a']);
        expect(fixture.execution.calls, isEmpty);
      },
    );

    test('maps auto-review denial text exactly and remembers it', () async {
      final fixture = _fixture(
        gate: ToolApprovalGateDecision.denied('unsafe repository state'),
      );

      final result = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA),
      );

      expect(
        result.result,
        'Auto-review denied this action. Rationale: unsafe repository state',
      );
      expect(
        result.errorMessage,
        'Auto-review denied: unsafe repository state',
      );
      expect(result.isSuccess, isFalse);
      expect(fixture.events, [
        'lookup:conversation-a',
        'gate:conversation-a',
        'remember-denial:conversation-a',
      ]);
    });

    test('maps manual denial text exactly and does not execute', () async {
      final fixture = _fixture(
        gate: ToolApprovalGateDecision.needsManualApproval,
        manualApproval: false,
      );

      final result = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA, reason: 'Create the initial commit.'),
      );

      expect(result.result, isEmpty);
      expect(result.errorMessage, 'User denied git command execution');
      expect(result.isSuccess, isFalse);
      expect(
        fixture.approval.manualRequests.single.reason,
        'Create the initial commit.',
      );
      expect(fixture.events, [
        'lookup:conversation-a',
        'gate:conversation-a',
        'manual:conversation-a',
        'remember-denial:conversation-a',
      ]);
      expect(fixture.execution.calls, isEmpty);
    });

    test('preserves allow, expiry, execution, and remember ordering', () async {
      final fixture = _fixture(
        gate: ToolApprovalGateDecision.needsManualApproval,
      );

      final result = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA),
      );

      expect(result, fixture.execution.result);
      expect(fixture.events, [
        'lookup:conversation-a',
        'gate:conversation-a',
        'manual:conversation-a',
        'expired:conversation-a',
        'execute-command:conversation-a',
        'remember-result:conversation-a',
        'expired:conversation-a',
      ]);
      final request = fixture.approval.gateRequests.single;
      expect(request.toolCallId, 'call-conversation-a');
      expect(request.toolName, 'git_execute_command');
      expect(request.actionKind, 'git_execute_command');
      expect(request.commandSummary, 'commit -m initial');
      expect(request.workingDirectory, '/repo/a');
    });

    test('returns expiration without execution after approval', () async {
      final expired = _failure('git_execute_command', 'Approval expired');
      final fixture = _fixture(expired: expired);

      final result = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA),
      );

      expect(result, expired);
      expect(fixture.events, [
        'lookup:conversation-a',
        'gate:conversation-a',
        'expired:conversation-a',
      ]);
      expect(fixture.execution.calls, isEmpty);
    });

    test('returns and remembers execution failures unchanged', () async {
      final failure = _failure('git_execute_command', 'git failed');
      final fixture = _fixture(commandResult: failure);

      final result = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA),
      );

      expect(result, failure);
      expect(fixture.approval.rememberedResults, [failure]);
    });

    test('rejects a mismatched no-effect cache acknowledgement', () async {
      final failure = _failure('git_execute_command', 'git failed');
      final fixture = _fixture(commandResult: failure);
      fixture.approval.rememberedResultOverride = const McpToolResult(
        toolName: 'other_git_tool',
        result: '{"exit_code":0}',
        isSuccess: true,
      );

      final result = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA),
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'Git result cache acknowledgement mismatch');
    });

    test('full access executes without storing an approval grant', () async {
      final fixture = _fixture(gate: ToolApprovalGateDecision.fullAccess);

      await fixture.handler.handleExecuteCommand(_commandInput(ownerA));

      expect(fixture.events, [
        'lookup:conversation-a',
        'gate:conversation-a',
        'expired:conversation-a',
        'execute-command:conversation-a',
      ]);
      expect(fixture.approval.rememberedResults, isEmpty);
    });

    test('approval poison cannot cross equal-generation owners', () async {
      final denialB = _failure('git_execute_command', 'owner B denied');
      final fixture = _fixture(
        cachedDenials: {ownerB: denialB},
        gatesByOwner: {
          ownerA: ToolApprovalGateDecision.autoReviewAllowed,
          ownerB: ToolApprovalGateDecision.denied('owner B only'),
        },
      );

      final resultA = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA),
      );
      final resultB = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerB),
      );

      expect(resultA.isSuccess, isTrue);
      expect(resultB, denialB);
      expect(fixture.execution.calls.map((call) => call.owner), [ownerA]);
      expect(fixture.approval.lookups.map((entry) => entry.$1), [
        ownerA,
        ownerB,
      ]);
    });

    test('binds every exact process identity field before approval', () async {
      final fixture = _fixture();
      final input = _input(
        ownerA,
        const {
          'working_directory': '/repo/a/packages/tool',
          'command': 'git commit -m exact',
          'metadata': {
            'labels': ['one', 'two'],
          },
        },
        repositoryPath: '/repo/a',
        worktreePath: '/worktrees/a',
      );

      await fixture.handler.handleExecuteCommand(input);

      final call = fixture.execution.calls.single;
      final identity = call.identity;
      expect(identity.owner, ownerA);
      expect(identity.toolCallId, input.toolCallId);
      expect(identity.toolName, input.toolName);
      expect(identity.repositoryIdentity, '/repo/a');
      expect(identity.worktreeIdentity, '/worktrees/a');
      expect(
        identity.argumentDigest,
        gitToolArgumentDigest(call.request.arguments),
      );
    });

    test('owner retirement before handoff releases a successor', () async {
      final fixture = _fixture();
      fixture.execution.beforeHandoff = (_) {
        fixture.processCoordinator.clearOwner(ownerA);
      };

      final retired = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA),
      );
      fixture.execution.beforeHandoff = null;
      final successor = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerB),
      );

      expect(
        retired.errorMessage,
        'The Git process owner expired before execution',
      );
      expect(successor.isSuccess, isTrue);
      expect(
        fixture.execution.startedIdentities.map((identity) => identity.owner),
        [ownerB],
      );
    });

    test(
      'preflight failure abandons the reservation for a successor',
      () async {
        final fixture = _fixture();
        fixture.execution.preflightError = StateError('preflight failed');

        await expectLater(
          fixture.handler.handleExecuteCommand(_commandInput(ownerA)),
          throwsA(isA<StateError>()),
        );
        fixture.execution.preflightError = null;
        final successor = await fixture.handler.handleExecuteCommand(
          _commandInput(ownerB),
        );

        expect(successor.isSuccess, isTrue);
        expect(fixture.execution.startedIdentities, hasLength(1));
        expect(fixture.execution.startedIdentities.single.owner, ownerB);
      },
    );

    test('launch failure settles no effect and releases a successor', () async {
      final fixture = _fixture();
      fixture.execution.launchFailure = true;

      final failed = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA),
      );
      fixture.execution.launchFailure = false;
      final successor = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerB),
      );

      expect(failed.errorMessage, 'Git process launch failed');
      expect(successor.isSuccess, isTrue);
      expect(fixture.execution.startedIdentities, hasLength(2));
    });

    test('serializes concurrent executions for the same repository', () async {
      final fixture = _fixture();
      final handoff = Completer<void>();
      final release = Completer<void>();
      fixture.execution.afterHandoff = (_) {
        if (!handoff.isCompleted) handoff.complete();
      };
      fixture.execution.waitAfterHandoff = release.future;

      final first = fixture.handler.handleExecuteCommand(_commandInput(ownerA));
      await handoff.future;
      final blocked = await fixture.handler.handleExecuteCommand(
        _input(
          ownerB,
          const {
            'command': 'commit -m initial',
            'working_directory': '/repo/a',
          },
          repositoryPath: '/repo/a',
          worktreePath: '/worktrees/b',
        ),
      );
      release.complete();
      final completed = await first;

      expect(completed.isSuccess, isTrue);
      expect(
        blocked.errorMessage,
        'Another Git process is active for this repository and worktree',
      );
      expect(fixture.execution.calls, hasLength(1));
    });

    test('late committed effect requires reconciliation and warns', () async {
      final fixture = _fixture();
      fixture.execution.reconciliationConfirmed = true;
      fixture.execution.afterHandoff = (_) {
        fixture.processCoordinator.clearOwner(ownerA);
      };

      final late = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA),
      );
      fixture.execution.afterHandoff = null;
      final successor = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerB),
      );

      expect(late.isSuccess, isFalse);
      expect(late.result, fixture.execution.result.result);
      expect(late.errorMessage, contains('partial effects'));
      expect(late.errorMessage, contains('reconcile any effects'));
      expect(successor.isSuccess, isTrue);
    });

    test('unreconciled partial effect keeps the repository fenced', () async {
      final fixture = _fixture();
      fixture.execution.effectKind = GitProcessEffectKind.partialOrUnknown;

      final partial = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerA),
      );
      final blocked = await fixture.handler.handleExecuteCommand(
        _commandInput(ownerB),
      );

      expect(partial.isSuccess, isFalse);
      expect(partial.errorMessage, contains('inspect repository'));
      expect(partial.errorMessage, contains('reconcile any effects'));
      expect(
        blocked.errorMessage,
        'Another Git process is active for this repository and worktree',
      );
    });

    test(
      'mismatched final cache result retains the committed effect receipt',
      () async {
        final fixture = _fixture();
        fixture.approval.rememberedResultOverride = const McpToolResult(
          toolName: 'other_git_tool',
          result: '{"exit_code":0}',
          isSuccess: true,
        );

        final result = await fixture.handler.handleExecuteCommand(
          _commandInput(ownerA),
        );
        final blocked = await fixture.handler.handleExecuteCommand(
          _input(
            ownerB,
            const {
              'command': 'commit -m successor',
              'working_directory': '/repo/a',
            },
            repositoryPath: '/repo/a',
            worktreePath: '/worktrees/b',
          ),
        );
        final retirement = fixture.processCoordinator.clearOwner(ownerA);

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, contains('reconcile any effects'));
        expect(
          blocked.errorMessage,
          'Another Git process is active for this repository and worktree',
        );
        expect(retirement.reconciliationRequired, hasLength(1));
        expect(retirement.reconciliationRequired.single.identity.owner, ownerA);
      },
    );

    test(
      'final cache exception retains the committed effect receipt',
      () async {
        final fixture = _fixture();
        fixture.approval.rememberResultError = StateError('cache failed');

        final result = await fixture.handler.handleExecuteCommand(
          _commandInput(ownerA),
        );
        final retirement = fixture.processCoordinator.clearOwner(ownerA);

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, contains('reconcile any effects'));
        expect(retirement.reconciliationRequired, hasLength(1));
        expect(
          retirement.reconciliationRequired.single.identity.toolCallId,
          'call-conversation-a',
        );
      },
    );
  });

  group('GitToolHandler worktree finishing', () {
    test('maps a missing worktree exactly without consulting approval', () async {
      final fixture = _fixture();

      final result = await fixture.handler.handleFinishWorktreeSession(
        _finishInput(
          ownerA,
          const {},
          repositoryPath: null,
          worktreePath: null,
        ),
      );

      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'worktree_path is required or the current conversation must be associated with a worktree',
      );
      expect(fixture.events, isEmpty);
    });

    test('normalizes all explicit finish options and manual summary', () async {
      final fixture = _fixture(
        gate: ToolApprovalGateDecision.needsManualApproval,
      );

      await fixture.handler.handleFinishWorktreeSession(
        _finishInput(ownerA, const {
          'worktree_path': '/worktrees/explicit',
          'base_branch': ' release ',
          'remove_worktree': 'no',
          'merge_message': ' Merge focused work ',
          'reason': 'Finish this exact session.',
        }, worktreePath: '/worktrees/owner-fallback'),
      );

      final request = fixture.worktree.calls.single.request;
      final identity = fixture.worktree.calls.single.identity;
      expect(request.worktreePath, '/worktrees/explicit');
      expect(request.baseBranch, 'release');
      expect(request.removeWorktree, isFalse);
      expect(request.mergeMessage, 'Merge focused work');
      expect(
        request.arguments,
        containsPair('merge_message', 'Merge focused work'),
      );
      final approval = fixture.approval.manualRequests.single;
      expect(
        approval.commandSummary,
        'finish worktree session: merge into release',
      );
      expect(approval.workingDirectory, '/worktrees/explicit');
      expect(approval.reason, 'Finish this exact session.');
      expect(approval.actionKind, 'git_finish_worktree_session');
      expect(identity.owner, ownerA);
      expect(identity.toolCallId, 'call-conversation-a');
      expect(identity.toolName, 'git_finish_worktree_session');
      expect(identity.repositoryIdentity, '/repo/a');
      expect(identity.worktreeIdentity, '/worktrees/explicit');
      expect(identity.argumentDigest, gitToolArgumentDigest(request.arguments));
    });

    test('uses only the exact owner worktree fallback', () async {
      final fixture = _fixture();

      await fixture.handler.handleFinishWorktreeSession(
        _finishInput(
          ownerA,
          const {},
          repositoryPath: null,
          worktreePath: '/worktrees/a',
        ),
      );
      await fixture.handler.handleFinishWorktreeSession(
        _finishInput(
          ownerB,
          const {},
          repositoryPath: null,
          worktreePath: '/worktrees/b',
        ),
      );

      expect(fixture.worktree.calls.map((call) => call.request.worktreePath), [
        '/worktrees/a',
        '/worktrees/b',
      ]);
      expect(
        fixture.worktree.calls.first.request.commandSummary,
        'finish worktree session: merge into main and remove /worktrees/a',
      );
      expect(
        jsonEncode(fixture.worktree.calls.first.request.arguments),
        isNot(contains('/worktrees/b')),
      );
    });

    test(
      'resolves relative worktree paths under the owner repository',
      () async {
        final fixture = _fixture();

        await fixture.handler.handleFinishWorktreeSession(
          _finishInput(
            ownerA,
            const {'worktree_path': 'trees/a'},
            repositoryPath: '/repositories/a',
            worktreePath: '/poison/b',
          ),
        );

        expect(
          fixture.worktree.calls.single.request.worktreePath,
          '/repositories/a/trees/a',
        );
      },
    );

    test(
      'preserves repository-root fallback used by current resolver',
      () async {
        final fixture = _fixture();

        await fixture.handler.handleFinishWorktreeSession(
          _finishInput(
            ownerA,
            const {},
            repositoryPath: '/repositories/a',
            worktreePath: '/worktrees/a',
          ),
        );

        expect(
          fixture.worktree.calls.single.request.worktreePath,
          '/repositories/a',
        );
      },
    );

    test('preserves every remove_worktree coercion branch', () async {
      final cases = <(Object?, bool)>[
        (null, true),
        (true, true),
        (false, false),
        (1, true),
        (0, false),
        (-2, true),
        (' true ', true),
        ('1', true),
        ('yes', true),
        ('y', true),
        (' false ', false),
        ('0', false),
        ('no', false),
        ('n', false),
        ('unknown', true),
        (const <String>[], true),
      ];

      for (final (value, expected) in cases) {
        final fixture = _fixture();
        await fixture.handler.handleFinishWorktreeSession(
          _finishInput(ownerA, {
            'worktree_path': '/worktrees/a',
            'remove_worktree': value,
          }),
        );
        final request = fixture.worktree.calls.single.request;
        expect(request.removeWorktree, expected, reason: 'value: $value');
        expect(
          request.arguments['remove_worktree'],
          expected,
          reason: 'value: $value',
        );
      }
    });

    test(
      'defaults base branch and preserves blank merge argument compatibility',
      () async {
        final fixture = _fixture();

        await fixture.handler.handleFinishWorktreeSession(
          _finishInput(ownerA, const {
            'worktree_path': '/worktrees/a',
            'base_branch': ' ',
            'merge_message': '   ',
          }),
        );

        final request = fixture.worktree.calls.single.request;
        expect(request.baseBranch, 'main');
        expect(request.mergeMessage, isNull);
        expect(request.arguments['merge_message'], '   ');
        expect(
          request.commandSummary,
          'finish worktree session: merge into main and remove /worktrees/a',
        );
      },
    );

    test('maps finish denial and execution failure exactly', () async {
      final deniedFixture = _fixture(
        gate: ToolApprovalGateDecision.needsManualApproval,
        manualApproval: false,
      );
      final denied = await deniedFixture.handler.handleFinishWorktreeSession(
        _finishInput(ownerA, const {'worktree_path': '/worktrees/a'}),
      );
      expect(denied.result, isEmpty);
      expect(denied.errorMessage, 'User denied worktree session completion');
      expect(deniedFixture.worktree.calls, isEmpty);

      final failure = _failure('git_finish_worktree_session', 'merge conflict');
      final failedFixture = _fixture(finishResult: failure);
      final failed = await failedFixture.handler.handleFinishWorktreeSession(
        _finishInput(ownerA, const {'worktree_path': '/worktrees/a'}),
      );
      expect(failed, failure);
      expect(failedFixture.approval.rememberedResults, [failure]);
    });
  });

  group('GitToolHandler lifecycle interpretation', () {
    test('recursively freezes ordered lifecycle evidence', () {
      final nested = <String, dynamic>{
        'values': <Object?>[
          <String, dynamic>{'marker': 'CODING_GOAL_CAPTURED'},
        ],
      };
      final arguments = <String, dynamic>{
        'command': 'git init',
        'nested': nested,
      };
      final sourceResults = <ToolResultInfo>[
        ToolResultInfo(
          id: 'git-init',
          name: 'git_execute_command',
          arguments: arguments,
          result: _gitPayload(),
        ),
      ];
      final input = _lifecycleInput(ownerA, sourceResults);

      arguments['command'] = 'git status';
      (nested['values'] as List).add('changed');
      (nested['values'] as List).first['marker'] = 'CHANGED';
      sourceResults.clear();

      expect(input.toolResults.single.arguments['command'], 'git init');
      expect(input.toolResults.single.arguments['nested'], {
        'values': [
          {'marker': 'CODING_GOAL_CAPTURED'},
        ],
      });
      expect(() => input.toolResults.clear(), throwsUnsupportedError);
      expect(
        () => input.toolResults.single.arguments['command'] = 'mutate',
        throwsUnsupportedError,
      );
      final frozenNested = input.toolResults.single.arguments['nested'] as Map;
      expect(() => frozenNested['new'] = true, throwsUnsupportedError);
      expect(
        () => (frozenNested['values'] as List).add('mutate'),
        throwsUnsupportedError,
      );
    });

    test('requires active Git revert goal and non-empty results', () {
      final fixture = _fixture();
      final complete = _completeLifecycle();
      final cases = [
        GitLifecycleInput(
          owner: ownerA,
          goalIsActive: true,
          goalObjective: 'Complete the Git revert lifecycle',
          toolResults: const [],
        ),
        GitLifecycleInput(
          owner: ownerA,
          goalIsActive: false,
          goalObjective: 'Complete the Git revert lifecycle',
          toolResults: complete,
        ),
        GitLifecycleInput(
          owner: ownerA,
          goalIsActive: true,
          goalObjective: 'Complete the repository revert lifecycle',
          toolResults: complete,
        ),
        GitLifecycleInput(
          owner: ownerA,
          goalIsActive: true,
          goalObjective: 'Complete the Git lifecycle',
          toolResults: complete,
        ),
      ];

      for (final input in cases) {
        expect(
          fixture.handler.satisfiesCurrentGoalGitLifecycle(input),
          isFalse,
        );
      }
    });

    test('requires every lifecycle step', () {
      final fixture = _fixture();
      final complete = _completeLifecycle();
      expect(
        fixture.handler.satisfiesCurrentGoalGitLifecycle(
          _lifecycleInput(ownerA, complete),
        ),
        isTrue,
      );

      for (var index = 0; index < complete.length; index++) {
        final missing = [...complete]..removeAt(index);
        expect(
          fixture.handler.satisfiesCurrentGoalGitLifecycle(
            _lifecycleInput(ownerA, missing),
          ),
          isFalse,
          reason: 'missing lifecycle result index $index',
        );
      }
    });

    test('ignores failed file creation and failed Git exits', () {
      final fixture = _fixture();
      final failedWrite = _completeLifecycle();
      failedWrite[1] = _writeResult(success: false);
      expect(
        fixture.handler.satisfiesCurrentGoalGitLifecycle(
          _lifecycleInput(ownerA, failedWrite),
        ),
        isFalse,
      );

      for (final index in [0, 2, 3, 4, 5]) {
        final failedGit = _completeLifecycle();
        final original = failedGit[index];
        failedGit[index] = ToolResultInfo(
          id: original.id,
          name: original.name,
          arguments: original.arguments,
          result: _gitPayload(exitCode: 1),
        );
        expect(
          fixture.handler.satisfiesCurrentGoalGitLifecycle(
            _lifecycleInput(ownerA, failedGit),
          ),
          isFalse,
          reason: 'failed Git result index $index',
        );
      }
    });

    test('normalizes argument commands and payload fallback', () {
      final fixture = _fixture();
      final results = [
        _gitResult('GIT init'),
        _writeResult(),
        _gitResult(' git add . '),
        _gitResult(
          'git commit -m initial',
          includeArgument: false,
          includePayloadCommand: true,
        ),
        _gitResult('GIT revert --no-edit HEAD'),
        _gitResult('git status --short'),
        _gitResult(null, includeArgument: false, includePayloadCommand: false),
      ];

      expect(
        fixture.handler.satisfiesCurrentGoalGitLifecycle(
          _lifecycleInput(ownerA, results),
        ),
        isTrue,
      );
    });

    test('distinguishes clean and dirty status payloads', () {
      final fixture = _fixture();
      final cases = <(String, String, bool)>[
        ('', '', true),
        ('On branch main\nnothing to commit, working tree clean', '', true),
        (' M lib/main.dart', '', false),
        ('', 'fatal: status failed', false),
      ];

      for (final (stdout, stderr, expected) in cases) {
        final results = _completeLifecycle(
          statusStdout: stdout,
          statusStderr: stderr,
        );
        expect(
          fixture.handler.satisfiesCurrentGoalGitLifecycle(
            _lifecycleInput(ownerA, results),
          ),
          expected,
          reason: 'stdout=$stdout stderr=$stderr',
        );
      }

      final plainStatus = _completeLifecycle();
      plainStatus[5] = ToolResultInfo(
        id: 'status',
        name: 'git_execute_command',
        arguments: const {'command': 'status'},
        result: 'exit_code: 0',
      );
      expect(
        fixture.handler.satisfiesCurrentGoalGitLifecycle(
          _lifecycleInput(ownerA, plainStatus),
        ),
        isTrue,
      );
    });

    test('requires a clean status after the last revert', () {
      final fixture = _fixture();
      final statusBeforeOnly = [
        _gitResult('init'),
        _writeResult(),
        _gitResult('add .'),
        _gitResult('commit -m initial'),
        _gitResult('status'),
        _gitResult('revert --no-edit HEAD'),
      ];
      expect(
        fixture.handler.satisfiesCurrentGoalGitLifecycle(
          _lifecycleInput(ownerA, statusBeforeOnly),
        ),
        isFalse,
      );

      final cleanThenSecondRevert = [
        ..._completeLifecycle(),
        _gitResult('revert --no-edit HEAD'),
      ];
      expect(
        fixture.handler.satisfiesCurrentGoalGitLifecycle(
          _lifecycleInput(ownerA, cleanThenSecondRevert),
        ),
        isFalse,
      );

      final ordered = [...cleanThenSecondRevert, _gitResult('status')];
      expect(
        fixture.handler.satisfiesCurrentGoalGitLifecycle(
          _lifecycleInput(ownerA, ordered),
        ),
        isTrue,
      );
    });

    test('keeps lifecycle evidence isolated by exact owner', () {
      final fixture = _fixture();
      final inputA = _lifecycleInput(ownerA, _completeLifecycle());
      final inputB = GitLifecycleInput(
        owner: ownerB,
        goalIsActive: true,
        goalObjective: 'Complete the Git revert lifecycle',
        toolResults: [_gitResult('status')],
      );

      expect(fixture.handler.satisfiesCurrentGoalGitLifecycle(inputA), isTrue);
      expect(fixture.handler.satisfiesCurrentGoalGitLifecycle(inputB), isFalse);
      expect(inputA.owner, ownerA);
      expect(inputB.owner, ownerB);
    });

    test('builds the exact response without a marker', () {
      final fixture = _fixture();

      final response = fixture.handler.buildGitLifecycleCompletionResponse(
        _lifecycleInput(ownerA, _completeLifecycle()),
      );

      expect(
        response,
        'The Git lifecycle completed successfully: git init, file creation, '
        'git add, git commit, git revert, and the final git status all '
        'succeeded with a clean working tree. Goal complete. Tests passed.',
      );
    });

    test('selects argument marker before result marker in result order', () {
      final fixture = _fixture();
      final first = ToolResultInfo(
        id: 'first',
        name: 'write_file',
        arguments: const {'marker': 'CODING_GOAL_ARGUMENTS'},
        result: 'CODING_GOAL_RESULT',
      );
      final later = ToolResultInfo(
        id: 'later',
        name: 'write_file',
        arguments: const {'marker': 'CODING_GOAL_LATER'},
        result: 'CODING_GOAL_LATER_RESULT',
      );

      final response = fixture.handler.buildGitLifecycleCompletionResponse(
        _lifecycleInput(ownerA, [first, later]),
      );

      expect(
        response,
        'The Git lifecycle completed successfully: git init, file creation, '
        'git add, git commit, git revert, and the final git status all '
        'succeeded with a clean working tree. Marker: CODING_GOAL_ARGUMENTS. '
        'Goal complete. Tests passed.',
      );
    });

    test('uses result marker and ignores lowercase marker text', () {
      final fixture = _fixture();
      final results = [
        ToolResultInfo(
          id: 'lowercase',
          name: 'write_file',
          arguments: const {'marker': 'coding_goal_lowercase'},
          result: 'coding_goal_lowercase_result',
        ),
        ToolResultInfo(
          id: 'uppercase',
          name: 'write_file',
          arguments: const {},
          result: 'created CODING_GOAL_RESULT_ONLY successfully',
        ),
      ];

      final response = fixture.handler.buildGitLifecycleCompletionResponse(
        _lifecycleInput(ownerA, results),
      );

      expect(response, contains('Marker: CODING_GOAL_RESULT_ONLY.'));
      expect(response, isNot(contains('coding_goal_lowercase')));
    });
  });
}

_Fixture _fixture({
  ToolApprovalGateDecision gate = ToolApprovalGateDecision.autoReviewAllowed,
  bool manualApproval = true,
  McpToolResult? expired,
  Map<ChatTurnOwner, McpToolResult> cachedDenials = const {},
  Map<ChatTurnOwner, ToolApprovalGateDecision> gatesByOwner = const {},
  McpToolResult commandResult = const McpToolResult(
    toolName: 'git_execute_command',
    result: '{"exit_code":0}',
    isSuccess: true,
  ),
  McpToolResult finishResult = const McpToolResult(
    toolName: 'git_finish_worktree_session',
    result: '{"ok":true}',
    isSuccess: true,
  ),
}) {
  final events = <String>[];
  final execution = _ExecutionPort(events, result: commandResult);
  final worktree = _WorktreePort(events, result: finishResult);
  final approval = _ApprovalPort(
    events,
    gate: gate,
    manualApproval: manualApproval,
    expired: expired,
    cachedDenials: cachedDenials,
    gatesByOwner: gatesByOwner,
  );
  final processCoordinator = GitProcessExecutionCoordinator();
  return _Fixture(
    events: events,
    execution: execution,
    worktree: worktree,
    approval: approval,
    processCoordinator: processCoordinator,
    handler: GitToolHandler(
      executionPort: execution,
      worktreeSessionPort: worktree,
      approvalPort: approval,
      processCoordinator: processCoordinator,
    ),
  );
}

final class _Fixture {
  const _Fixture({
    required this.events,
    required this.execution,
    required this.worktree,
    required this.approval,
    required this.processCoordinator,
    required this.handler,
  });

  final List<String> events;
  final _ExecutionPort execution;
  final _WorktreePort worktree;
  final _ApprovalPort approval;
  final GitProcessExecutionCoordinator processCoordinator;
  final GitToolHandler handler;
}

final class _ExecutionPort implements GitExecutionPort {
  _ExecutionPort(this.events, {required this.result});

  final List<String> events;
  final McpToolResult result;
  final List<
    ({
      ChatTurnOwner owner,
      GitCommandExecutionRequest request,
      GitProcessExecutionIdentity identity,
    })
  >
  calls = [];
  final List<GitProcessExecutionIdentity> startedIdentities = [];
  Object? preflightError;
  bool launchFailure = false;
  GitProcessEffectKind? effectKind;
  bool reconciliationConfirmed = false;
  void Function(GitProcessExecutionIdentity identity)? beforeHandoff;
  void Function(GitProcessExecutionIdentity identity)? afterHandoff;
  Future<void>? waitAfterHandoff;

  @override
  Future<GitRawProcessCompletion> execute(
    GitCommandExecutionRequest request,
    GitProcessStartAuthorization authorization,
  ) async {
    final owner = request.source.owner;
    events.add('execute-command:${owner.conversationId}');
    calls.add((
      owner: owner,
      request: request,
      identity: authorization.identity,
    ));
    if (preflightError case final error?) throw error;
    beforeHandoff?.call(authorization.identity);
    if (!authorization.beginProcessHandoff()) {
      return GitRawProcessCompletion(
        identity: authorization.identity,
        result: result,
        effectKind: GitProcessEffectKind.noEffect,
      );
    }
    startedIdentities.add(authorization.identity);
    if (launchFailure) {
      throw GitProcessLaunchFailure(
        identity: authorization.identity,
        result: _failure(request.source.toolName, 'Git process launch failed'),
      );
    }
    afterHandoff?.call(authorization.identity);
    await waitAfterHandoff;
    final classifiedEffect =
        effectKind ??
        (request.command == 'status'
            ? GitProcessEffectKind.noEffect
            : result.isSuccess
            ? GitProcessEffectKind.committed
            : GitProcessEffectKind.noEffect);
    return GitRawProcessCompletion(
      identity: authorization.identity,
      result: result,
      effectKind: classifiedEffect,
      effectDetails: {
        'command': request.command,
        'workingDirectory': request.workingDirectory,
      },
      reconciliation: reconciliationConfirmed
          ? GitProcessReconciliationConfirmation(
              identity: authorization.identity,
              details: const {'repositoryStateVerified': true},
            )
          : null,
    );
  }
}

final class _WorktreePort implements GitWorktreeSessionPort {
  _WorktreePort(this.events, {required this.result});

  final List<String> events;
  final McpToolResult result;
  final List<
    ({
      ChatTurnOwner owner,
      GitWorktreeSessionRequest request,
      GitProcessExecutionIdentity identity,
    })
  >
  calls = [];

  @override
  Future<GitRawProcessCompletion> finish(
    GitWorktreeSessionRequest request,
    GitProcessStartAuthorization authorization,
  ) async {
    final owner = request.source.owner;
    events.add('finish-worktree:${owner.conversationId}');
    calls.add((
      owner: owner,
      request: request,
      identity: authorization.identity,
    ));
    authorization.beginProcessHandoff();
    return GitRawProcessCompletion(
      identity: authorization.identity,
      result: result,
      effectKind: result.isSuccess
          ? GitProcessEffectKind.committed
          : GitProcessEffectKind.noEffect,
    );
  }
}

final class _ApprovalPort implements GitApprovalPort {
  _ApprovalPort(
    this.events, {
    required this.gate,
    required this.manualApproval,
    required this.expired,
    required this.cachedDenials,
    required this.gatesByOwner,
  });

  final List<String> events;
  final ToolApprovalGateDecision gate;
  final bool manualApproval;
  final McpToolResult? expired;
  final Map<ChatTurnOwner, McpToolResult> cachedDenials;
  final Map<ChatTurnOwner, ToolApprovalGateDecision> gatesByOwner;
  final List<(ChatTurnOwner, GitApprovalRequest)> lookups = [];
  final List<GitApprovalRequest> gateRequests = [];
  final List<GitApprovalRequest> manualRequests = [];
  final List<GitApprovalRequest> expirationChecks = [];
  final List<McpToolResult> rememberedDenials = [];
  final List<McpToolResult> rememberedResults = [];
  McpToolResult? rememberedResultOverride;
  Object? rememberResultError;

  @override
  McpToolResult? lookupDenial(ChatTurnOwner owner, GitApprovalRequest request) {
    events.add('lookup:${owner.conversationId}');
    lookups.add((owner, request));
    return cachedDenials[owner];
  }

  @override
  Future<ToolApprovalGateDecision> resolveGate(
    ChatTurnOwner owner,
    GitApprovalRequest request,
  ) async {
    events.add('gate:${owner.conversationId}');
    gateRequests.add(request);
    return gatesByOwner[owner] ?? gate;
  }

  @override
  Future<bool> requestManualApproval(
    ChatTurnOwner owner,
    GitApprovalRequest request,
  ) async {
    events.add('manual:${owner.conversationId}');
    manualRequests.add(request);
    return manualApproval;
  }

  @override
  McpToolResult rememberDenial(
    ChatTurnOwner owner,
    GitApprovalRequest request,
    McpToolResult result,
  ) {
    events.add('remember-denial:${owner.conversationId}');
    rememberedDenials.add(result);
    return result;
  }

  @override
  McpToolResult rememberResult(
    ChatTurnOwner owner,
    GitApprovalRequest request,
    McpToolResult result,
  ) {
    events.add('remember-result:${owner.conversationId}');
    rememberedResults.add(result);
    if (rememberResultError case final error?) throw error;
    return rememberedResultOverride ?? result;
  }

  @override
  McpToolResult? expiredResult(
    ChatTurnOwner owner,
    GitApprovalRequest request,
  ) {
    events.add('expired:${owner.conversationId}');
    expirationChecks.add(request);
    return expired;
  }
}

GitToolCallInput _input(
  ChatTurnOwner owner,
  Map<String, dynamic> arguments, {
  String? repositoryPath = '/repo/a',
  String? worktreePath = '/worktrees/a',
  String toolName = 'git_execute_command',
}) {
  return GitToolCallInput(
    owner: owner,
    toolCallId: 'call-${owner.conversationId}',
    toolName: toolName,
    arguments: arguments,
    ownerRepositoryPath: repositoryPath,
    ownerWorktreePath: worktreePath,
  );
}

GitToolCallInput _commandInput(
  ChatTurnOwner owner, {
  String command = 'commit -m initial',
  String? reason,
}) {
  return _input(owner, {
    'command': command,
    'working_directory': '/repo/a',
    'reason': ?reason,
  });
}

GitToolCallInput _finishInput(
  ChatTurnOwner owner,
  Map<String, dynamic> arguments, {
  String? repositoryPath = '/repo/a',
  String? worktreePath = '/worktrees/a',
}) {
  return _input(
    owner,
    arguments,
    repositoryPath: repositoryPath,
    worktreePath: worktreePath,
    toolName: 'git_finish_worktree_session',
  );
}

GitLifecycleInput _lifecycleInput(
  ChatTurnOwner owner,
  List<ToolResultInfo> results,
) {
  return GitLifecycleInput(
    owner: owner,
    goalIsActive: true,
    goalObjective: '  Complete the GIT revert lifecycle  ',
    toolResults: results,
  );
}

List<ToolResultInfo> _completeLifecycle({
  String statusStdout = '',
  String statusStderr = '',
}) {
  return [
    _gitResult('git init'),
    _writeResult(),
    _gitResult('git add .'),
    _gitResult('git commit -m initial'),
    _gitResult('git revert --no-edit HEAD'),
    _gitResult('git status', stdout: statusStdout, stderr: statusStderr),
  ];
}

ToolResultInfo _gitResult(
  String? command, {
  int exitCode = 0,
  String stdout = '',
  String stderr = '',
  bool includeArgument = true,
  bool includePayloadCommand = false,
}) {
  return ToolResultInfo(
    id: 'git-${command ?? 'missing'}',
    name: 'git_execute_command',
    arguments: {if (includeArgument && command != null) 'command': command},
    result: _gitPayload(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      command: includePayloadCommand ? command : null,
    ),
  );
}

ToolResultInfo _writeResult({bool success = true}) {
  return ToolResultInfo(
    id: 'write',
    name: 'write_file',
    arguments: const {'path': '/repo/a/example.txt'},
    result: success
        ? '{"path":"/repo/a/example.txt"}'
        : '{"error":"write failed"}',
  );
}

String _gitPayload({
  int exitCode = 0,
  String stdout = '',
  String stderr = '',
  String? command,
}) {
  return jsonEncode({
    'exit_code': exitCode,
    'stdout': stdout,
    'stderr': stderr,
    'command': ?command,
  });
}

McpToolResult _failure(String toolName, String message) {
  return McpToolResult(
    toolName: toolName,
    result: '',
    isSuccess: false,
    errorMessage: message,
  );
}
