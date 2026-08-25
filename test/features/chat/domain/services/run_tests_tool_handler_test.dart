import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/local_command_tool_handler.dart';
import 'package:caverno/features/chat/domain/services/run_tests_tool_handler.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

const _rootA = '/workspace/owner-a';
const _rootB = '/workspace/owner-b';

void main() {
  final ownerA = ChatTurnOwner(
    conversationId: 'conversation-a',
    interactionGeneration: 4,
  );
  final ownerB = ChatTurnOwner(
    conversationId: 'conversation-b',
    interactionGeneration: 4,
  );

  group('RunTestsToolHandler validation and construction', () {
    test('normalizes and validates the exact tool attempt identity', () {
      final input = RunTestsToolInput(
        owner: ownerA,
        toolCallId: ' call-a ',
        toolName: ' run_tests ',
        ownerProjectRoot: _rootA,
        arguments: const {},
      );

      expect(input.toolCallId, 'call-a');
      expect(input.toolName, 'run_tests');
      for (final identity in [(' ', 'run_tests'), ('call-a', '\n')]) {
        expect(
          () => RunTestsToolInput(
            owner: ownerA,
            toolCallId: identity.$1,
            toolName: identity.$2,
            ownerProjectRoot: _rootA,
            arguments: const {},
          ),
          throwsArgumentError,
        );
      }
    });

    test('rejects a non-canonical tool name before project access', () async {
      final fixture = _fixture();

      final result = await fixture.handler.handle(
        _input(ownerA, const {
          'runner': 'dart',
        }, toolName: 'local_execute_command'),
      );

      expect(result.toolName, 'local_execute_command');
      expect(result.isSuccess, isFalse);
      expect(
        result.result,
        '{"code":"unsupported_tool","error":"RunTestsToolHandler only accepts run_tests"}',
      );
      expect(fixture.access.calls, isEmpty);
      expect(fixture.hasNoSideEffects, isTrue);
    });

    test(
      'returns an exact project access denial before reading evidence',
      () async {
        final denied = _result(
          toolName: 'run_tests',
          result: '{"code":"bookmark_restore_failed"}',
          isSuccess: false,
          errorMessage: 'Failed to restore security-scoped bookmark access',
        );
        final fixture = _fixture()..access.denials[ownerA] = denied;

        final result = await fixture.handler.handle(
          _input(ownerA, const {'runner': 'dart'}),
        );

        expect(result, same(denied));
        expect(fixture.access.calls.single.owner, ownerA);
        expect(fixture.access.calls.single.toolCallId, 'call-conversation-a');
        expect(fixture.access.calls.single.toolName, 'run_tests');
        expect(fixture.access.calls.single.projectRoot, _rootA);
        expect(fixture.evidence.totalCalls, 0);
        expect(fixture.rules.evaluations, isEmpty);
        expect(fixture.approval.totalCalls, 0);
        expect(fixture.execution.calls, isEmpty);
      },
    );

    test(
      'rejects an expired project access completion before evidence',
      () async {
        final fixture = _fixture()..access.expiredOwners.add(ownerA);

        final result = await fixture.handler.handle(
          _input(ownerA, const {'runner': 'dart'}),
        );

        expect(result.toolName, 'run_tests');
        expect(result.isSuccess, isFalse);
        expect(
          result.result,
          '{"code":"turn_expired","error":"The run_tests turn expired before project access completed"}',
        );
        expect(fixture.evidence.totalCalls, 0);
        expect(fixture.execution.calls, isEmpty);
      },
    );

    test('rejects poisoned project access completion identities', () async {
      final nextGeneration = ChatTurnOwner(
        conversationId: ownerA.conversationId,
        interactionGeneration: ownerA.interactionGeneration + 1,
      );
      final cases = <(RunTestsProjectAccessCompletion, String)>[
        (
          RunTestsProjectAccessCompletion.granted(
            owner: nextGeneration,
            toolCallId: 'call-conversation-a',
            toolName: 'run_tests',
          ),
          'Run tests project access owner mismatch.',
        ),
        (
          RunTestsProjectAccessCompletion.granted(
            owner: ownerA,
            toolCallId: 'poisoned-call',
            toolName: 'run_tests',
          ),
          'Run tests project access tool call mismatch.',
        ),
        (
          RunTestsProjectAccessCompletion.granted(
            owner: ownerA,
            toolCallId: 'call-conversation-a',
            toolName: 'read_file',
          ),
          'Run tests project access tool name mismatch.',
        ),
      ];

      for (final (completion, message) in cases) {
        final fixture = _fixture()
          ..access.completionOverrides[ownerA] = completion;

        await expectLater(
          fixture.handler.handle(_input(ownerA, const {'runner': 'dart'})),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              message,
            ),
          ),
        );

        expect(fixture.evidence.totalCalls, 0);
        expect(fixture.execution.calls, isEmpty);
      }
    });

    test('recursively freezes owner-bound input arguments', () async {
      final tags = <Object?>['focused'];
      final nested = <String, dynamic>{
        'items': <Object?>[
          <String, dynamic>{'value': 'captured'},
        ],
        'tags': tags,
        'labels': <String, Object?>{'7': 'owner-a'},
      };
      final source = <String, dynamic>{
        'runner': 'dart',
        'test_path': 'test/unit_test.dart',
        'metadata': nested,
      };
      final fixture = _fixture();
      final input = _input(ownerA, source);

      source['runner'] = 'flutter';
      (nested['items'] as List).add('changed');
      (nested['items'] as List).first['value'] = 'changed';
      tags.add('poisoned');
      (nested['labels'] as Map)['7'] = 'visible';
      await fixture.handler.handle(input);

      expect(input.toolCallId, 'call-conversation-a');
      expect(input.arguments['runner'], 'dart');
      expect(input.arguments['test_path'], 'test/unit_test.dart');
      final frozenNested = input.arguments['metadata'] as Map;
      final frozenItems = frozenNested['items'] as List;
      expect(frozenItems, [
        {'value': 'captured'},
      ]);
      expect(frozenNested['tags'], ['focused']);
      expect(frozenNested['labels'], {'7': 'owner-a'});
      expect(
        fixture.execution.calls.single.request.command,
        "dart test 'test/unit_test.dart'",
      );
      expect(
        () => input.arguments['runner'] = 'mutated',
        throwsUnsupportedError,
      );
      expect(() => frozenNested['new'] = true, throwsUnsupportedError);
      expect(() => frozenItems.add('mutated'), throwsUnsupportedError);
      expect(
        () => (frozenNested['tags'] as List<Object?>).add('poisoned'),
        throwsUnsupportedError,
      );
      expect(
        () => (frozenNested['labels'] as Map)['7'] = 'late',
        throwsUnsupportedError,
      );
      expect(
        () => (frozenItems.first as Map)['value'] = 'mutated',
        throwsUnsupportedError,
      );
    });

    test('rejects every non-JSON argument shape', () {
      final invalidValues = <Object?>[
        _MutableArgument(),
        <Object?, Object?>{7: 'invalid key'},
        <Object?>{'not-json'},
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];

      for (final invalidValue in invalidValues) {
        expect(
          () => _input(ownerA, {'runner': 'dart', 'metadata': invalidValue}),
          throwsArgumentError,
          reason: invalidValue.toString(),
        );
      }
    });

    test('returns the exact selected-project error', () async {
      final fixture = _fixture();

      final result = await fixture.handler.handle(
        _input(ownerA, const {}, projectRoot: '   '),
      );

      expect(result.toolName, 'run_tests');
      expect(result.isSuccess, isFalse);
      expect(
        result.result,
        '{"code":"project_required","error":"run_tests requires a selected coding project"}',
      );
      expect(
        result.errorMessage,
        'run_tests requires a selected coding project',
      );
      expect(fixture.hasNoSideEffects, isTrue);
    });

    test('uses normalized root, working_directory, and cwd paths', () async {
      final fixture = _fixture();

      await fixture.handler.handle(_input(ownerA, const {'runner': 'dart'}));
      await fixture.handler.handle(
        _input(ownerA, const {
          'runner': 'dart',
          'working_directory': 'packages/../packages/app',
        }),
      );
      await fixture.handler.handle(
        _input(ownerA, const {
          'runner': 'dart',
          'working_directory': ' ',
          'cwd': 'tools/checks',
        }),
      );

      expect(
        fixture.execution.calls.map((call) => call.request.workingDirectory),
        [_rootA, '$_rootA/packages/app', '$_rootA/tools/checks'],
      );
      expect(
        fixture.rules.evaluations.map((call) => call.request.workingDirectory),
        [_rootA, '$_rootA/packages/app', '$_rootA/tools/checks'],
      );
    });

    test('rejects relative and absolute working-directory escapes', () async {
      final cases = [
        const {'runner': 'dart', 'working_directory': '../owner-b'},
        const {'runner': 'dart', 'working_directory': _rootB},
        const {'runner': 'dart', 'cwd': '../../outside'},
      ];

      for (final arguments in cases) {
        final fixture = _fixture();
        final result = await fixture.handler.handle(_input(ownerA, arguments));

        expect(result.isSuccess, isFalse);
        expect(
          result.result,
          '{"code":"working_directory_outside_project","error":"working_directory must resolve inside the selected coding project"}',
        );
        expect(
          result.errorMessage,
          'working_directory must resolve inside the selected coding project',
        );
        expect(fixture.hasNoSideEffects, isTrue);
      }
    });

    test('rejects relative and absolute test-target escapes', () async {
      final cases = [
        const {'runner': 'dart', 'test_path': '../owner-b/test/a_test.dart'},
        const {'runner': 'dart', 'test_path': '$_rootB/test/b_test.dart'},
      ];

      for (final arguments in cases) {
        final fixture = _fixture();
        final result = await fixture.handler.handle(_input(ownerA, arguments));

        expect(result.isSuccess, isFalse);
        expect(
          result.result,
          '{"code":"test_path_outside_project","error":"test_path must resolve inside the selected coding project"}',
        );
        expect(
          result.errorMessage,
          'test_path must resolve inside the selected coding project',
        );
        expect(fixture.execution.calls, isEmpty);
        expect(fixture.approval.totalCalls, 0);
      }
    });

    test('rejects an unsupported runner after path validation', () async {
      final fixture = _fixture();

      final result = await fixture.handler.handle(
        _input(ownerA, const {'runner': 'python'}),
      );

      expect(result.isSuccess, isFalse);
      expect(
        result.result,
        '{"code":"unsupported_runner","error":"runner must be one of auto, flutter, or dart"}',
      );
      expect(
        result.errorMessage,
        'runner must be one of auto, flutter, or dart',
      );
      expect(fixture.hasNoSideEffects, isTrue);
    });

    test('normalizes explicit runner and FVM combinations exactly', () async {
      final cases = <(Object, bool, String)>[
        (' Flutter ', false, 'flutter test'),
        ('flutter', true, 'fvm flutter test'),
        (' DART ', false, 'dart test'),
        ('dart', true, 'fvm dart test'),
      ];

      for (final (runner, hasFvm, command) in cases) {
        final fixture = _fixture()..evidence.fvmOwners[ownerA] = hasFvm;
        await fixture.handler.handle(_input(ownerA, {'runner': runner}));

        expect(
          fixture.execution.calls.single.request.command,
          command,
          reason: 'runner=$runner hasFvm=$hasFvm',
        );
        expect(fixture.evidence.flutterChecks, isEmpty);
        expect(
          fixture.execution.calls.single.request.arguments['runner'],
          runner.toString().trim().toLowerCase(),
        );
      }
    });

    test('propagates owner evidence exceptions before approval', () async {
      final evidenceError = StateError('FVM evidence failed');
      final fixture = _fixture()..evidence.fvmError = evidenceError;

      await expectLater(
        fixture.handler.handle(_input(ownerA, const {'runner': 'dart'})),
        throwsA(same(evidenceError)),
      );

      expect(fixture.evidence.fvmChecks.single.owner, ownerA);
      expect(fixture.rules.evaluations, isEmpty);
      expect(fixture.approval.expiredOwners, isEmpty);
      expect(fixture.approval.totalCalls, 0);
      expect(fixture.execution.calls, isEmpty);
    });

    test('infers auto, empty, and omitted runners exactly', () async {
      final cases = <(Object?, Set<String>, String)>[
        (null, {'$_rootA/packages/app'}, 'flutter test'),
        ('', {_rootA}, 'flutter test'),
        (' auto ', const {}, 'dart test'),
      ];

      for (final (runner, flutterPaths, command) in cases) {
        final fixture = _fixture()
          ..evidence.flutterPackages[ownerA] = flutterPaths;
        final arguments = <String, dynamic>{
          'working_directory': 'packages/app',
          'runner': ?runner,
        };
        await fixture.handler.handle(_input(ownerA, arguments));

        expect(
          fixture.execution.calls.single.request.command,
          command,
          reason: 'runner=$runner flutterPaths=$flutterPaths',
        );
        expect(
          fixture.execution.calls.single.request.arguments,
          isNot(contains('runner')),
        );
      }
    });

    test(
      'short-circuits runner inference from package before project',
      () async {
        final fixture = _fixture()
          ..evidence.flutterPackages[ownerA] = {'$_rootA/packages/app', _rootA};

        await fixture.handler.handle(
          _input(ownerA, const {'working_directory': 'packages/app'}),
        );

        expect(fixture.evidence.flutterChecks.map((check) => check.path), [
          '$_rootA/packages/app',
        ]);
      },
    );

    test('infers a nested package root from the exact task target', () async {
      final fixture = _fixture()
        ..evidence.inferredRoots[ownerA] = '$_rootA/packages/app';

      await fixture.handler.handle(
        _input(ownerA, const {
          'runner': 'dart',
          'test_path': 'packages/app/test/widget_test.dart',
        }),
      );

      final inference = fixture.evidence.inferenceCalls.single;
      expect(inference.owner, ownerA);
      expect(inference.projectRoot, _rootA);
      expect(inference.workingDirectory, _rootA);
      expect(inference.testPath, 'packages/app/test/widget_test.dart');
      final execution = fixture.execution.calls.single.request;
      expect(execution.workingDirectory, '$_rootA/packages/app');
      expect(execution.command, "dart test 'test/widget_test.dart'");
      expect(
        execution.arguments['test_path'],
        'packages/app/test/widget_test.dart',
      );
    });

    test('does not infer a package when cwd is explicit', () async {
      final fixture = _fixture()
        ..evidence.inferredRoots[ownerA] = '$_rootA/poison';

      await fixture.handler.handle(
        _input(ownerA, const {
          'runner': 'dart',
          'working_directory': 'packages/app',
          'test_path': 'packages/app/test/widget_test.dart',
        }),
      );

      expect(fixture.evidence.inferenceCalls, isEmpty);
      final execution = fixture.execution.calls.single.request;
      expect(execution.workingDirectory, '$_rootA/packages/app');
      expect(execution.command, "dart test 'test/widget_test.dart'");
    });

    test('ignores an inferred package root outside the owner root', () async {
      final fixture = _fixture()
        ..evidence.inferredRoots[ownerA] = '$_rootB/packages/poison';

      await fixture.handler.handle(
        _input(ownerA, const {
          'runner': 'dart',
          'test_path': 'test/root_test.dart',
        }),
      );

      final execution = fixture.execution.calls.single.request;
      expect(execution.workingDirectory, _rootA);
      expect(execution.command, "dart test 'test/root_test.dart'");
    });

    test(
      'normalizes relative and absolute targets against nested cwd',
      () async {
        final cases = <(String, String)>[
          (
            'packages/app/test/relative_test.dart',
            "dart test 'test/relative_test.dart'",
          ),
          (
            '$_rootA/packages/app/test/absolute_test.dart',
            "dart test 'test/absolute_test.dart'",
          ),
          ('$_rootA/shared_test.dart', "dart test '$_rootA/shared_test.dart'"),
          ('packages/app', "dart test '.'"),
          ('packages/app/', "dart test '.'"),
        ];

        for (final (target, command) in cases) {
          final fixture = _fixture();
          await fixture.handler.handle(
            _input(ownerA, {
              'runner': 'dart',
              'working_directory': 'packages/app',
              'test_path': target,
            }),
          );

          expect(
            fixture.execution.calls.single.request.command,
            command,
            reason: 'target=$target',
          );
        }
      },
    );

    test(
      'uses path as test_path fallback and preserves the trimmed target',
      () async {
        final fixture = _fixture();

        await fixture.handler.handle(
          _input(ownerA, const {
            'runner': 'dart',
            'test_path': ' ',
            'path': ' test/fallback_test.dart ',
          }),
        );

        final execution = fixture.execution.calls.single.request;
        expect(execution.command, "dart test 'test/fallback_test.dart'");
        expect(execution.arguments['test_path'], 'test/fallback_test.dart');
      },
    );

    test('omits empty test targets and defaults an empty reason', () async {
      for (final arguments in [
        const <String, dynamic>{'runner': 'dart'},
        const <String, dynamic>{'runner': 'dart', 'test_path': '   '},
        const <String, dynamic>{
          'runner': 'dart',
          'test_path': ' ',
          'path': ' ',
          'reason': ' ',
        },
      ]) {
        final fixture = _fixture();
        await fixture.handler.handle(_input(ownerA, arguments));

        final execution = fixture.execution.calls.single.request;
        expect(execution.command, 'dart test');
        expect(execution.arguments, isNot(contains('test_path')));
        expect(execution.arguments['reason'], 'Run scoped test validation');
      }
    });

    test(
      'quotes spaces, apostrophes, and shell metacharacters exactly',
      () async {
        final fixture = _fixture();
        const target = r"test/my suite's $case;$(touch poison)_test.dart";

        await fixture.handler.handle(
          _input(ownerA, const {
            'runner': 'dart',
            'working_directory': 'packages/app',
            'test_path': target,
          }),
        );

        expect(
          fixture.execution.calls.single.request.command,
          r"""dart test 'test/my suite'"'"'s $case;$(touch poison)_test.dart'""",
        );
        expect(
          fixture.execution.calls.single.request.arguments['test_path'],
          target,
        );
      },
    );

    test('trims and stringifies an explicit reason', () async {
      final fixture = _fixture();

      await fixture.handler.handle(
        _input(ownerA, const {'runner': 'dart', 'reason': 42}),
      );

      expect(fixture.execution.calls.single.request.arguments['reason'], '42');
    });
  });

  group('RunTestsToolHandler approval and execution', () {
    test('uses the WS6-5 permission rule port for exact owner deny', () async {
      final fixture = _fixture()
        ..rules.decisions[ownerA] = CommandPermissionRuleDecision.deny
        ..rules.decisions[ownerB] = CommandPermissionRuleDecision.allow;

      final result = await fixture.handler.handle(
        _input(ownerA, const {'runner': 'dart'}),
      );

      expect(result.toolName, 'run_tests');
      expect(result.result, isEmpty);
      expect(
        result.errorMessage,
        'Local command was denied by a saved permission rule',
      );
      expect(fixture.rules.evaluations.single.owner, ownerA);
      expect(fixture.approval.expiredOwners, [ownerA]);
      expect(fixture.approval.totalCalls, 1);
      expect(fixture.execution.calls, isEmpty);
    });

    // SEC4.4g: a test run reaches the native shell, so the gate is consulted
    // even when a saved rule already says allow. The rule can still spare the
    // person a second dialog, but it can no longer decide alone.
    test('a saved allow still reaches the approval gate', () async {
      final fixture = _fixture()
        ..rules.decisions[ownerA] = CommandPermissionRuleDecision.allow;

      final result = await fixture.handler.handle(
        _input(ownerA, const {'runner': 'dart'}),
      );

      expect(result.isSuccess, isTrue);
      expect(fixture.execution.calls.single.owner, ownerA);
      expect(fixture.approval.gateCalls.single.owner, ownerA);
      // Three checks now, not two: the gate the saved rule no longer skips
      // brings its own expiry check, and every one of them must name the
      // owning turn.
      expect(fixture.approval.expiredOwners, [ownerA, ownerA, ownerA]);
    });

    test('remote interaction does not reuse a saved allow', () async {
      final fixture = _fixture()
        ..rules.decisions[ownerA] = CommandPermissionRuleDecision.allow
        ..approval.gates[ownerA] = ToolApprovalGateDecision.fullAccess;

      await fixture.handler.handle(
        _input(ownerA, const {'runner': 'dart'}, isRemoteInteraction: true),
      );

      expect(fixture.approval.gateCalls.single.owner, ownerA);
      expect(fixture.execution.calls.single.owner, ownerA);
    });

    test('returns an owner-scoped cached denial with run_tests name', () async {
      final cached = _result(
        toolName: 'local_execute_command',
        result: '',
        isSuccess: false,
        errorMessage: 'Previously denied',
      );
      final fixture = _fixture()..approval.cachedDenials[ownerA] = cached;

      final result = await fixture.handler.handle(
        _input(ownerA, const {'runner': 'dart'}),
      );

      expect(result.toolName, 'run_tests');
      expect(result.result, cached.result);
      expect(result.errorMessage, cached.errorMessage);
      expect(fixture.approval.lookupCalls.single.owner, ownerA);
      expect(fixture.approval.gateCalls, isEmpty);
      expect(fixture.execution.calls, isEmpty);
    });

    test('maps auto-review denial payload exactly', () async {
      final fixture = _fixture()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.denied(
          'Owner-scoped policy rejected validation',
        );

      final result = await fixture.handler.handle(
        _input(ownerA, const {'runner': 'dart'}),
      );

      expect(result.toolName, 'run_tests');
      expect(
        result.result,
        'Auto-review denied this action. Rationale: '
        'Owner-scoped policy rejected validation',
      );
      expect(
        result.errorMessage,
        'Auto-review denied: Owner-scoped policy rejected validation',
      );
      expect(fixture.approval.rememberedDenials.single.owner, ownerA);
      expect(fixture.execution.calls, isEmpty);
    });

    test('maps manual denial and approval exactly', () async {
      final deniedFixture = _fixture()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.needsManualApproval
        ..approval.manualDecisions[ownerA] = const LocalCommandManualApproval(
          approved: false,
        );

      final denied = await deniedFixture.handler.handle(
        _input(ownerA, const {'runner': 'dart'}),
      );

      expect(denied.toolName, 'run_tests');
      expect(denied.result, isEmpty);
      expect(denied.errorMessage, 'User denied local command execution');
      expect(deniedFixture.execution.calls, isEmpty);

      final allowedFixture = _fixture()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.needsManualApproval
        ..approval.manualDecisions[ownerA] = const LocalCommandManualApproval(
          approved: true,
        );
      final allowed = await allowedFixture.handler.handle(
        _input(ownerA, const {
          'runner': 'dart',
          'test_path': 'test/approved_test.dart',
          'reason': 'Run the focused test.',
        }, toolCallId: 'run-tests-approval-23'),
      );

      expect(allowed.isSuccess, isTrue);
      final approval = allowedFixture.approval.manualCalls.single.request;
      expect(approval.execution.command, "dart test 'test/approved_test.dart'");
      expect(approval.toolCallId, 'run-tests-approval-23');
      expect(approval.execution.workingDirectory, _rootA);
      expect(approval.reason, 'Run the focused test.');
      expect(allowedFixture.execution.calls.single.owner, ownerA);
      // SEC4.4g made this approval non-cacheable, so the result is not
      // remembered: the next identical call must ask again rather than replay
      // this one.
      expect(allowedFixture.approval.rememberedResults, isEmpty);
    });

    // A remembered *deny* still stands: SEC4.4g removed the standing yes, not
    // the standing no. The command it stores is the normalized one, so a rule
    // saved from a nested package matches what the handler will run next time.
    test('remembers the exact normalized test command rule', () async {
      final fixture = _fixture()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.needsManualApproval
        ..approval.manualDecisions[ownerA] = const LocalCommandManualApproval(
          approved: false,
          rememberedAction: RememberedCommandPermissionAction.deny,
          rememberedMatch: RememberedCommandPermissionMatch.exact,
        );

      await fixture.handler.handle(
        _input(ownerA, const {
          'runner': 'dart',
          'working_directory': 'packages/app',
          'test_path': 'packages/app/test/a_test.dart',
        }),
      );

      final remembered = fixture.rules.remembered.single;
      expect(remembered.owner, ownerA);
      expect(remembered.rule.action, RememberedCommandPermissionAction.deny);
      expect(remembered.rule.match, RememberedCommandPermissionMatch.exact);
      expect(remembered.rule.command, "dart test 'test/a_test.dart'");
      expect(remembered.rule.workingDirectory, '$_rootA/packages/app');
    });

    // The other half of the same rule: an allow is never written for a command
    // that needs a fresh approval, or the next turn would inherit a yes the
    // gate is meant to ask for again.
    test('does not remember an allow for a fresh-approval command', () async {
      final fixture = _fixture()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.needsManualApproval
        ..approval.manualDecisions[ownerA] = const LocalCommandManualApproval(
          approved: true,
          rememberedAction: RememberedCommandPermissionAction.allow,
          rememberedMatch: RememberedCommandPermissionMatch.exact,
        );

      await fixture.handler.handle(
        _input(ownerA, const {
          'runner': 'dart',
          'working_directory': 'packages/app',
          'test_path': 'packages/app/test/a_test.dart',
        }),
      );

      expect(fixture.rules.remembered, isEmpty);
      expect(fixture.execution.calls.single.owner, ownerA);
    });

    test('returns expiration before and after manual approval', () async {
      final preFixture = _fixture()..approval.expirationQueues[ownerA] = [true];
      final preResult = await preFixture.handler.handle(
        _input(ownerA, const {'runner': 'dart'}),
      );
      expect(preResult.toolName, 'run_tests');
      expect(preResult.result, isEmpty);
      expect(
        preResult.errorMessage,
        'The approval turn expired before execution',
      );
      expect(preFixture.execution.calls, isEmpty);

      final postFixture = _fixture()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.needsManualApproval
        ..approval.expirationQueues[ownerA] = [false, true];
      final postResult = await postFixture.handler.handle(
        _input(ownerA, const {'runner': 'dart'}),
      );
      expect(postResult.toolName, 'run_tests');
      expect(postResult.result, isEmpty);
      expect(
        postResult.errorMessage,
        'The approval turn expired before execution',
      );
      expect(postFixture.execution.calls, isEmpty);
    });

    test(
      'preserves success, failure, timeout, and process-error payloads',
      () async {
        final results = [
          _result(
            toolName: 'local_execute_command',
            result: jsonEncode({
              'command': 'dart test',
              'working_directory': _rootA,
              'exit_code': 0,
              'stdout': 'All tests passed.',
              'stderr': '',
            }),
            isExternal: true,
          ),
          _result(
            toolName: 'local_execute_command',
            result: jsonEncode({
              'command': 'dart test',
              'working_directory': _rootA,
              'exit_code': 1,
              'stdout': '',
              'stderr': 'One test failed.',
            }),
          ),
          _result(
            toolName: 'local_execute_command',
            result: jsonEncode({
              'command': 'dart test',
              'working_directory': _rootA,
              'stdout': 'partial',
              'stderr': '',
              'error': 'Command timed out after 60 seconds.',
              'timed_out': true,
              'timeout_ms': 60000,
              'process_terminated': true,
            }),
          ),
          _result(
            toolName: 'local_execute_command',
            result: '{"error":"ProcessException: dart not found"}',
            isSuccess: false,
            errorMessage: 'ProcessException: dart not found',
          ),
        ];

        for (final expected in results) {
          final fixture = _fixture()
            ..execution.resultsByOwner[ownerA] = expected;
          final result = await fixture.handler.handle(
            _input(ownerA, const {'runner': 'dart'}),
          );

          expect(result.toolName, 'run_tests');
          expect(result.result, expected.result);
          expect(result.isSuccess, expected.isSuccess);
          expect(result.errorMessage, expected.errorMessage);
          expect(result.isExternalMcpResult, expected.isExternalMcpResult);
          expect(
            fixture.execution.calls.single.request.timeout,
            const Duration(seconds: 60),
          );
        }
      },
    );

    test('propagates execution exceptions without approval caching', () async {
      final executionError = StateError('test process failed');
      final fixture = _fixture()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.autoReviewAllowed
        ..execution.errorsByOwner[ownerA] = executionError;

      await expectLater(
        fixture.handler.handle(_input(ownerA, const {'runner': 'dart'})),
        throwsA(same(executionError)),
      );

      expect(fixture.execution.calls.single.owner, ownerA);
      expect(fixture.approval.rememberedDenials, isEmpty);
      expect(fixture.approval.rememberedResults, isEmpty);
    });
  });

  group('RunTestsToolHandler owner poison', () {
    test('never crosses owner roots or task targets', () async {
      final fixture = _fixture()
        ..evidence.inferredRoots[ownerA] = '$_rootA/packages/a'
        ..evidence.inferredRoots[ownerB] = '$_rootB/packages/b';

      await fixture.handler.handle(
        _input(ownerA, const {
          'runner': 'dart',
          'test_path': 'packages/a/test/a_test.dart',
        }, projectRoot: _rootA),
      );
      await fixture.handler.handle(
        _input(ownerB, const {
          'runner': 'dart',
          'test_path': 'packages/b/test/b_test.dart',
        }, projectRoot: _rootB),
      );

      expect(fixture.execution.calls.map((call) => call.owner), [
        ownerA,
        ownerB,
      ]);
      expect(
        fixture.execution.calls.map((call) => call.request.workingDirectory),
        ['$_rootA/packages/a', '$_rootB/packages/b'],
      );
      expect(fixture.execution.calls.map((call) => call.request.command), [
        "dart test 'test/a_test.dart'",
        "dart test 'test/b_test.dart'",
      ]);
      expect(
        jsonEncode(fixture.execution.calls.first.request.arguments),
        isNot(anyOf(contains(_rootB), contains('b_test.dart'))),
      );
    });

    test('keeps runner and FVM evidence attached to exact owner', () async {
      final fixture = _fixture()
        ..evidence.flutterPackages[ownerA] = {_rootA}
        ..evidence.flutterPackages[ownerB] = const {}
        ..evidence.fvmOwners[ownerA] = true
        ..evidence.fvmOwners[ownerB] = false;

      await fixture.handler.handle(
        _input(ownerA, const {}, projectRoot: _rootA),
      );
      await fixture.handler.handle(
        _input(ownerB, const {}, projectRoot: _rootB),
      );

      expect(fixture.execution.calls.map((call) => call.request.command), [
        'fvm flutter test',
        'dart test',
      ]);
      expect(fixture.evidence.fvmChecks.map((check) => check.owner), [
        ownerA,
        ownerB,
      ]);
      expect(
        fixture.evidence.flutterChecks.map((check) => check.owner).toSet(),
        {ownerA, ownerB},
      );
    });

    test('does not reuse approval evidence from another owner', () async {
      final cachedB = _result(
        toolName: 'local_execute_command',
        result: '',
        isSuccess: false,
        errorMessage: 'Owner B denied',
      );
      final fixture = _fixture()
        ..approval.cachedDenials[ownerB] = cachedB
        ..approval.gates[ownerA] = ToolApprovalGateDecision.fullAccess
        ..approval.gates[ownerB] = ToolApprovalGateDecision.needsManualApproval;

      final resultA = await fixture.handler.handle(
        _input(ownerA, const {'runner': 'dart'}, projectRoot: _rootA),
      );
      final resultB = await fixture.handler.handle(
        _input(ownerB, const {'runner': 'dart'}, projectRoot: _rootB),
      );

      expect(resultA.isSuccess, isTrue);
      expect(resultB.errorMessage, 'Owner B denied');
      expect(fixture.execution.calls.map((call) => call.owner), [ownerA]);
      expect(fixture.approval.lookupCalls.map((call) => call.owner), [
        ownerA,
        ownerB,
      ]);
    });

    test(
      'does not reuse next-generation evidence for the same conversation',
      () async {
        final nextGeneration = ChatTurnOwner(
          conversationId: ownerA.conversationId,
          interactionGeneration: ownerA.interactionGeneration + 1,
        );
        final cachedNextGeneration = _result(
          toolName: 'local_execute_command',
          result: '',
          isSuccess: false,
          errorMessage: 'Next generation denied',
        );
        final fixture = _fixture()
          ..evidence.flutterPackages[ownerA] = const {}
          ..evidence.flutterPackages[nextGeneration] = {_rootA}
          ..evidence.fvmOwners[ownerA] = false
          ..evidence.fvmOwners[nextGeneration] = true
          ..approval.cachedDenials[nextGeneration] = cachedNextGeneration
          ..approval.gates[ownerA] = ToolApprovalGateDecision.fullAccess;

        final result = await fixture.handler.handle(
          _input(ownerA, const {}, projectRoot: _rootA),
        );

        expect(result.isSuccess, isTrue);
        expect(fixture.execution.calls.single.owner, ownerA);
        expect(fixture.execution.calls.single.request.command, 'dart test');
        expect(fixture.evidence.fvmChecks.single.owner, ownerA);
        expect(
          fixture.evidence.flutterChecks.map((call) => call.owner).toSet(),
          {ownerA},
        );
        expect(fixture.approval.lookupCalls.single.owner, ownerA);
      },
    );
  });

  group('DartProjectRunTestsEvidencePort', () {
    test('reads package, FVM, and target evidence from supplied paths', () {
      final root = Directory.systemTemp.createTempSync(
        'caverno-run-tests-evidence-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final package = Directory('${root.path}/packages/app')
        ..createSync(recursive: true);
      File('${package.path}/pubspec.yaml').writeAsStringSync(
        'name: app\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      File('${root.path}/.fvmrc').writeAsStringSync('{"flutter":"stable"}');
      File('${package.path}/test/widget_test.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');
      const port = DartProjectRunTestsEvidencePort();

      expect(port.isFlutterPackage(ownerA, package.path), isTrue);
      expect(
        port.hasFvmMetadata(
          ownerA,
          packageRoot: package.path,
          projectRoot: root.path,
        ),
        isTrue,
      );
      expect(
        port.inferPackageRootForTestPath(
          ownerA,
          projectRoot: root.path,
          workingDirectory: root.path,
          testPath: 'test/widget_test.dart',
        ),
        package.path,
      );
    });
  });
}

_Fixture _fixture() {
  final execution = _ExecutionPort();
  final approval = _ApprovalPort();
  final rules = _RuleStore();
  final evidence = _EvidencePort();
  final access = _ProjectAccessPort();
  return _Fixture(
    execution: execution,
    approval: approval,
    rules: rules,
    evidence: evidence,
    access: access,
    handler: RunTestsToolHandler(
      executionPort: execution,
      approvalPort: approval,
      permissionRuleStorePort: rules,
      projectAccessPort: access,
      evidencePort: evidence,
    ),
  );
}

final class _Fixture {
  const _Fixture({
    required this.execution,
    required this.approval,
    required this.rules,
    required this.evidence,
    required this.access,
    required this.handler,
  });

  final _ExecutionPort execution;
  final _ApprovalPort approval;
  final _RuleStore rules;
  final _EvidencePort evidence;
  final _ProjectAccessPort access;
  final RunTestsToolHandler handler;

  bool get hasNoSideEffects =>
      execution.calls.isEmpty &&
      approval.totalCalls == 0 &&
      rules.evaluations.isEmpty &&
      evidence.totalCalls == 0;
}

RunTestsToolInput _input(
  ChatTurnOwner owner,
  Map<String, dynamic> arguments, {
  String? projectRoot = _rootA,
  bool isRemoteInteraction = false,
  String? toolCallId,
  String toolName = 'run_tests',
}) {
  return RunTestsToolInput(
    owner: owner,
    toolCallId: toolCallId ?? 'call-${owner.conversationId}',
    toolName: toolName,
    ownerProjectRoot: projectRoot,
    arguments: arguments,
    isRemoteInteraction: isRemoteInteraction,
  );
}

typedef _ProjectAccessCall = ({
  ChatTurnOwner owner,
  String toolCallId,
  String toolName,
  String projectRoot,
});

final class _ProjectAccessPort implements RunTestsProjectAccessPort {
  final List<_ProjectAccessCall> calls = [];
  final Map<ChatTurnOwner, McpToolResult> denials = {};
  final Set<ChatTurnOwner> expiredOwners = {};
  final Map<ChatTurnOwner, RunTestsProjectAccessCompletion>
  completionOverrides = {};

  @override
  Future<RunTestsProjectAccessCompletion> ensureAccess(
    ChatTurnOwner owner, {
    required String toolCallId,
    required String toolName,
    required String projectRoot,
  }) async {
    calls.add((
      owner: owner,
      toolCallId: toolCallId,
      toolName: toolName,
      projectRoot: projectRoot,
    ));
    final override = completionOverrides[owner];
    if (override != null) return override;
    if (expiredOwners.contains(owner)) {
      return RunTestsProjectAccessCompletion.ownerExpired(
        owner: owner,
        toolCallId: toolCallId,
        toolName: toolName,
      );
    }
    final denial = denials[owner];
    if (denial != null) {
      return RunTestsProjectAccessCompletion.denied(
        owner: owner,
        toolCallId: toolCallId,
        toolName: toolName,
        failure: denial,
      );
    }
    return RunTestsProjectAccessCompletion.granted(
      owner: owner,
      toolCallId: toolCallId,
      toolName: toolName,
    );
  }
}

typedef _ExecutionCall = ({
  ChatTurnOwner owner,
  LocalCommandExecutionRequest request,
});

final class _ExecutionPort implements TestCommandExecutionPort {
  final List<_ExecutionCall> calls = [];
  final List<LocalCommandOperationIdentity> settlements = [];
  final Map<ChatTurnOwner, McpToolResult> resultsByOwner = {};
  final Map<ChatTurnOwner, Object> errorsByOwner = {};

  @override
  Future<LocalCommandCompletion<McpToolResult>> execute(
    ChatTurnOwner owner,
    LocalCommandExecutionRequest request,
  ) async {
    calls.add((owner: owner, request: request));
    final error = errorsByOwner[owner];
    if (error != null) {
      throw error;
    }
    final result =
        resultsByOwner[owner] ??
        _result(
          toolName: request.toolName,
          result: jsonEncode({
            'command': request.command,
            'working_directory': request.workingDirectory,
            'exit_code': 0,
            'stdout': '',
            'stderr': '',
          }),
        );
    // Mirror the production execution adapter: every completion that carries a
    // launched command's result also carries an identity-bound settlement.
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: request.toolCallId,
      value: result,
      effectDisposition: LocalCommandEffectDisposition.settlementRequired,
      effectSettlement: LocalCommandEffectSettlement(
        identity: request.identityFor(owner),
        settle: () {
          settlements.add(request.identityFor(owner));
          return true;
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

final class _RuleStore implements CommandPermissionRuleStorePort {
  final Map<ChatTurnOwner, CommandPermissionRuleDecision> decisions = {};
  final List<_RuleEvaluation> evaluations = [];
  final List<_RememberedRule> remembered = [];

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
    remembered.add((owner: owner, toolCallId: toolCallId, rule: rule));
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: toolCallId,
      value: null,
    );
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
typedef _RememberedResult = ({
  ChatTurnOwner owner,
  LocalCommandApprovalRequest request,
  McpToolResult result,
});

final class _ApprovalPort implements LocalCommandApprovalPort {
  final Map<ChatTurnOwner, McpToolResult> cachedDenials = {};
  final Map<ChatTurnOwner, ToolApprovalGateDecision> gates = {};
  final Map<ChatTurnOwner, LocalCommandManualApproval> manualDecisions = {};
  final Map<ChatTurnOwner, List<bool>> expirationQueues = {};
  final List<ChatTurnOwner> expiredOwners = [];
  final List<_ApprovalCall> lookupCalls = [];
  final List<_ApprovalCall> gateCalls = [];
  final List<_ManualApprovalCall> manualCalls = [];
  final List<_RememberedResult> rememberedDenials = [];
  final List<_RememberedResult> rememberedResults = [];

  int get totalCalls =>
      expiredOwners.length +
      lookupCalls.length +
      gateCalls.length +
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
    return cached == null
        ? null
        : LocalCommandCompletion.completed(
            owner: owner,
            toolCallId: request.toolCallId,
            value: cached,
          );
  }

  @override
  Future<LocalCommandCompletion<ToolApprovalGateDecision>> resolveGate(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
  ) async {
    gateCalls.add((owner: owner, request: request));
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: request.toolCallId,
      value: gates[owner] ?? ToolApprovalGateDecision.fullAccess,
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
    return LocalCommandCompletion.completed(
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
    final queue = expirationQueues[owner];
    return queue != null && queue.isNotEmpty && queue.removeAt(0);
  }

  @override
  LocalCommandCompletion<Object?> rememberDenial(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    McpToolResult result,
  ) {
    rememberedDenials.add((owner: owner, request: request, result: result));
    return LocalCommandCompletion.completed(
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
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: request.toolCallId,
      value: null,
    );
  }
}

final class _MutableArgument {
  var value = 0;
}

typedef _InferenceCall = ({
  ChatTurnOwner owner,
  String projectRoot,
  String workingDirectory,
  String testPath,
});
typedef _PathCheck = ({ChatTurnOwner owner, String path});
typedef _FvmCheck = ({
  ChatTurnOwner owner,
  String packageRoot,
  String projectRoot,
});

final class _EvidencePort implements RunTestsProjectEvidencePort {
  final Map<ChatTurnOwner, String?> inferredRoots = {};
  final Map<ChatTurnOwner, Set<String>> flutterPackages = {};
  final Map<ChatTurnOwner, bool> fvmOwners = {};
  final List<_InferenceCall> inferenceCalls = [];
  final List<_PathCheck> flutterChecks = [];
  final List<_FvmCheck> fvmChecks = [];
  Object? fvmError;

  int get totalCalls =>
      inferenceCalls.length + flutterChecks.length + fvmChecks.length;

  @override
  String? inferPackageRootForTestPath(
    ChatTurnOwner owner, {
    required String projectRoot,
    required String workingDirectory,
    required String testPath,
  }) {
    inferenceCalls.add((
      owner: owner,
      projectRoot: projectRoot,
      workingDirectory: workingDirectory,
      testPath: testPath,
    ));
    return inferredRoots[owner];
  }

  @override
  bool isFlutterPackage(ChatTurnOwner owner, String packageRoot) {
    flutterChecks.add((owner: owner, path: packageRoot));
    return flutterPackages[owner]?.contains(packageRoot) ?? false;
  }

  @override
  bool hasFvmMetadata(
    ChatTurnOwner owner, {
    required String packageRoot,
    required String projectRoot,
  }) {
    fvmChecks.add((
      owner: owner,
      packageRoot: packageRoot,
      projectRoot: projectRoot,
    ));
    if (fvmError case final error?) {
      throw error;
    }
    return fvmOwners[owner] ?? false;
  }
}

McpToolResult _result({
  required String toolName,
  required String result,
  bool isSuccess = true,
  String? errorMessage,
  bool isExternal = false,
}) {
  return McpToolResult(
    toolName: toolName,
    result: result,
    isSuccess: isSuccess,
    errorMessage: errorMessage,
    isExternalMcpResult: isExternal,
  );
}
