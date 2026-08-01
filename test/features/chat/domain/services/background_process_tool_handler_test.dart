import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/background_process_tool_handler.dart';
import 'package:caverno/features/chat/domain/services/local_command_tool_handler.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

const _ownerARoot = '/workspace/owner-a';
const _ownerBRoot = '/workspace/owner-b';
final _fixedTime = DateTime.utc(2026, 7, 30, 12);

ChatTurnOwner _owner(String conversationId, {int generation = 1}) =>
    ChatTurnOwner(
      conversationId: conversationId,
      interactionGeneration: generation,
    );

BackgroundProcessToolRequest _startRequest({
  required ChatTurnOwner owner,
  Map<String, dynamic> arguments = const {'command': 'touch output.txt'},
  String allowedRoot = _ownerARoot,
  String? defaultWorkingDirectory,
  bool remote = false,
}) {
  return BackgroundProcessToolRequest(
    owner: owner,
    toolCallId: 'start-${owner.interactionGeneration}',
    toolName: 'process_start',
    allowedWorkingDirectoryRoot: allowedRoot,
    defaultWorkingDirectory: defaultWorkingDirectory,
    arguments: arguments,
    isRemoteInteraction: remote,
  );
}

BackgroundProcessToolRequest _cancelRequest({
  required ChatTurnOwner owner,
  Object? jobId = 'job-1',
  String allowedRoot = _ownerARoot,
  String? defaultWorkingDirectory,
}) {
  return BackgroundProcessToolRequest(
    owner: owner,
    toolCallId: 'cancel-${owner.interactionGeneration}',
    toolName: 'process_cancel',
    allowedWorkingDirectoryRoot: allowedRoot,
    defaultWorkingDirectory: defaultWorkingDirectory,
    arguments: {'job_id': jobId},
  );
}

McpToolResult _result(
  String toolName,
  String payload, {
  bool isSuccess = true,
  String? errorMessage,
  bool isExternal = false,
}) {
  return McpToolResult(
    toolName: toolName,
    result: payload,
    isSuccess: isSuccess,
    errorMessage: errorMessage,
    isExternalMcpResult: isExternal,
  );
}

BackgroundProcessIdentity _identity(
  String processId, {
  String? backendId,
  bool isRunning = true,
}) => (
  externalProcessId: processId,
  backendProcessId: backendId ?? 'backend-$processId',
  isRunning: isRunning,
);

BackgroundProcessStartResult _startValue(McpToolResult result) {
  Map<String, dynamic>? payload;
  try {
    payload = jsonDecode(result.result) as Map<String, dynamic>;
  } catch (_) {
    payload = null;
  }
  final processId = payload?['job_id']?.toString();
  return (
    result: result,
    identity: processId == null ? null : _identity(processId),
    startedByRequest:
        payload?['ok'] == true && payload?['duplicate_existing'] != true,
  );
}

void _expectExpired(McpToolResult result, String toolName) {
  expect(result.toolName, toolName);
  expect(result.result, isEmpty);
  expect(result.isSuccess, isFalse);
  expect(result.errorMessage, 'The approval turn expired before execution');
}

void _expectEffectUncertain(McpToolResult result, String toolName) {
  expect(result.toolName, toolName);
  expect(result.result, isEmpty);
  expect(result.isSuccess, isFalse);
  expect(
    result.errorMessage,
    'The background process action may have completed after its owner expired; '
    'inspect the process and possible side effects before retrying',
  );
}

void main() {
  group('BackgroundProcessToolHandler', () {
    test('recursively freezes request, environment, and start input', () async {
      final owner = _owner('owner-a');
      final allowedKeys = <Object?>['PATHS'];
      final searchPath = <Object?>[
        '/usr/bin',
        <String, dynamic>{
          'fallback': <Object?>['/opt/bin'],
        },
      ];
      final environment = <String, dynamic>{
        'PATHS': searchPath,
        'MODE': 'stable',
        'ALLOWED_KEYS': allowedKeys,
        'LABELS': <String, Object?>{'7': 'owner-a'},
      };
      final arguments = <String, dynamic>{
        'command': 'pwd',
        'environment': environment,
      };
      final request = _startRequest(owner: owner, arguments: arguments);

      arguments['command'] = 'rm -rf build';
      environment['MODE'] = 'mutated';
      allowedKeys.add('MODE');
      (environment['LABELS'] as Map)['7'] = 'visible';
      searchPath.add('/tmp');
      ((searchPath[1] as Map<String, dynamic>)['fallback']
              as List<Object?>)[0] =
          '/mutated';

      expect(request.arguments['command'], 'pwd');
      final frozenEnvironment =
          request.arguments['environment'] as Map<String, dynamic>;
      final frozenPaths = frozenEnvironment['PATHS'] as List<Object?>;
      expect(frozenEnvironment['MODE'], 'stable');
      expect(frozenEnvironment['ALLOWED_KEYS'], ['PATHS']);
      expect(frozenEnvironment['LABELS'], {'7': 'owner-a'});
      expect(frozenPaths, hasLength(2));
      expect(
        ((frozenPaths[1] as Map<String, dynamic>)['fallback'] as List<Object?>)
            .single,
        '/opt/bin',
      );
      expect(
        () => request.arguments['command'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () => (frozenEnvironment['LABELS'] as Map)['7'] = 'late',
        throwsUnsupportedError,
      );
      expect(
        () => frozenEnvironment['MODE'] = 'changed',
        throwsUnsupportedError,
      );
      expect(() => frozenPaths.add('changed'), throwsUnsupportedError);
      expect(
        () => (frozenEnvironment['ALLOWED_KEYS'] as List<Object?>).add('MODE'),
        throwsUnsupportedError,
      );

      final harness = _Harness();
      await harness.handler.handle(request);
      final operation = harness.execution.startCalls.single.operation;
      expect(operation.toolCallId, 'start-1');
      expect(operation.arguments['environment'], frozenEnvironment);
      expect(
        () =>
            (operation.arguments['environment']
                    as Map<String, dynamic>)['MODE'] =
                'changed',
        throwsUnsupportedError,
      );
    });

    test('rejects every non-JSON argument shape', () {
      final owner = _owner('owner-a');
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
          () => _startRequest(
            owner: owner,
            arguments: {
              'command': 'pwd',
              'environment': {'invalid': invalidValue},
            },
          ),
          throwsArgumentError,
          reason: invalidValue.toString(),
        );
      }
    });

    test('returns the exact missing-command failure', () async {
      final harness = _Harness();
      final result = await harness.handler.handle(
        _startRequest(
          owner: _owner('owner-a'),
          arguments: const {
            'command': ' <|im_end|> ',
            'working_directory': _ownerARoot,
          },
        ),
      );

      expect(result.toolName, 'process_start');
      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'command is required and working_directory must be provided or '
        'inferred from the selected coding project',
      );
      expect(harness.rules.evaluations, isEmpty);
      expect(harness.approval.totalCalls, 0);
      expect(harness.execution.startCalls, isEmpty);
    });

    test('resolves root, owner default, working_directory, and cwd', () async {
      final owner = _owner('owner-a');
      final harness = _Harness();
      final requests = [
        _startRequest(owner: owner, arguments: const {'command': 'pwd'}),
        _startRequest(
          owner: owner,
          arguments: const {'command': 'pwd'},
          defaultWorkingDirectory: '$_ownerARoot/package',
        ),
        _startRequest(
          owner: owner,
          arguments: const {'command': 'pwd', 'working_directory': 'tools'},
        ),
        _startRequest(
          owner: owner,
          arguments: const {
            'command': ' pwd<|im_end|> ',
            'working_directory': ' ',
            'cwd': '$_ownerARoot/scripts',
          },
        ),
      ];

      for (final request in requests) {
        await harness.handler.handle(request);
      }

      expect(
        harness.execution.startCalls.map(
          (call) => call.operation.workingDirectory,
        ),
        [
          _ownerARoot,
          '$_ownerARoot/package',
          '$_ownerARoot/tools',
          '$_ownerARoot/scripts',
        ],
      );
      expect(
        harness.execution.startCalls.map((call) => call.operation.command),
        everyElement('pwd'),
      );
      expect(
        harness.execution.startCalls.last.operation.arguments['cwd'],
        '$_ownerARoot/scripts',
      );
    });

    test('rejects relative, absolute, and default cwd escapes exactly', () async {
      final owner = _owner('owner-a');
      final cases = [
        _startRequest(
          owner: owner,
          arguments: const {
            'command': 'pwd',
            'working_directory': '../outside',
          },
        ),
        _startRequest(
          owner: owner,
          arguments: const {
            'command': 'pwd',
            'working_directory': '/workspace/outside',
          },
        ),
        _startRequest(
          owner: owner,
          arguments: const {'command': 'pwd'},
          defaultWorkingDirectory: '/workspace/outside',
        ),
      ];
      const payload =
          '{"code":"working_directory_outside_project",'
          '"error":"working_directory must resolve inside the selected coding project"}';

      for (final request in cases) {
        final harness = _Harness();
        final result = await harness.handler.handle(request);

        expect(result.result, payload);
        expect(result.isSuccess, isFalse);
        expect(
          result.errorMessage,
          'working_directory must resolve inside the selected coding project',
        );
        expect(harness.rules.evaluations, isEmpty);
        expect(harness.execution.startCalls, isEmpty);
      }
    });

    test('rejects a missing start boundary as missing cwd', () async {
      final harness = _Harness();
      final result = await harness.handler.handle(
        _startRequest(
          owner: _owner('owner-a'),
          allowedRoot: '',
          arguments: const {'command': 'pwd'},
        ),
      );

      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('working_directory'));
      expect(harness.execution.startCalls, isEmpty);
    });

    test('applies saved start deny and local safe allow precedence', () async {
      final owner = _owner('owner-a');
      final deniedHarness = _Harness()
        ..rules.decisions[owner] = CommandPermissionRuleDecision.deny;
      final allowedHarness = _Harness()
        ..rules.decisions[owner] = CommandPermissionRuleDecision.allow;

      final denied = await deniedHarness.handler.handle(
        _startRequest(owner: owner),
      );
      final allowed = await allowedHarness.handler.handle(
        _startRequest(owner: owner),
      );

      expect(denied.result, isEmpty);
      expect(denied.isSuccess, isFalse);
      expect(
        denied.errorMessage,
        'Local command was denied by a saved permission rule',
      );
      expect(deniedHarness.approval.totalCalls, 0);
      expect(deniedHarness.execution.startCalls, isEmpty);
      expect(allowed.isSuccess, isTrue);
      expect(allowedHarness.execution.startCalls, hasLength(1));
      expect(allowedHarness.approval.resolveCalls, isEmpty);
    });

    test('does not use a safe saved allow for a remote start', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
        ..approval.gates[owner] = ToolApprovalGateDecision.fullAccess;

      await harness.handler.handle(_startRequest(owner: owner, remote: true));

      expect(harness.approval.resolveCalls.single.owner, owner);
      expect(harness.approval.manualCalls, isEmpty);
      expect(harness.execution.startCalls, hasLength(1));
      expect(harness.approval.rememberedResults, isEmpty);
    });

    test('starts a read-only command without approval', () async {
      final owner = _owner('owner-a');
      final harness = _Harness();

      await harness.handler.handle(
        _startRequest(
          owner: owner,
          remote: true,
          arguments: const {'command': 'git status --short'},
        ),
      );

      expect(harness.execution.startCalls, hasLength(1));
      expect(harness.approval.resolveCalls, isEmpty);
    });

    test(
      'requires approval for risky commands despite a saved allow',
      () async {
        final owner = _owner('owner-a');
        final harness = _Harness()
          ..rules.decisions[owner] = CommandPermissionRuleDecision.allow;

        await harness.handler.handle(
          _startRequest(
            owner: owner,
            arguments: const {
              'command': 'rm -rf build',
              'reason': 'Rebuild generated output',
            },
          ),
        );

        final call = harness.approval.manualCalls.single;
        expect(call.owner, owner);
        expect(call.request.toolCallId, 'start-1');
        expect(call.request.reason, 'Rebuild generated output');
        expect(call.request.warningTitle, 'Recursive file deletion');
        expect(
          call.request.warningMessage,
          'This command can permanently remove files or directories. '
          'Review the target path before approving it.',
        );
        expect(harness.execution.startCalls, hasLength(1));
      },
    );

    test('maps manual start denial to the exact cached result', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: false,
        );

      final result = await harness.handler.handle(_startRequest(owner: owner));

      expect(result.toolName, 'process_start');
      expect(result.result, isEmpty);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'User denied background process start');
      expect(harness.approval.rememberedDenials.single.result, same(result));
      expect(harness.execution.startCalls, isEmpty);
    });

    test('persists a remembered start rule for the exact owner', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: true,
          rememberedAction: RememberedCommandPermissionAction.allow,
          rememberedMatch: RememberedCommandPermissionMatch.exact,
        );

      await harness.handler.handle(
        _startRequest(
          owner: owner,
          arguments: const {
            'command': 'dart run tool/build.dart',
            'working_directory': 'package',
          },
        ),
      );

      final remembered = harness.rules.rememberedRules.single;
      expect(remembered.owner, owner);
      expect(remembered.toolCallId, 'start-1');
      expect(remembered.rule.action, RememberedCommandPermissionAction.allow);
      expect(remembered.rule.match, RememberedCommandPermissionMatch.exact);
      expect(remembered.rule.command, 'dart run tool/build.dart');
      expect(remembered.rule.workingDirectory, '$_ownerARoot/package');
      expect(harness.approval.rememberedResults, hasLength(1));
    });

    test('does not persist a remembered start rule remotely', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: true,
          rememberedAction: RememberedCommandPermissionAction.allow,
          rememberedMatch: RememberedCommandPermissionMatch.exact,
        );

      await harness.handler.handle(_startRequest(owner: owner, remote: true));

      expect(harness.rules.rememberedRules, isEmpty);
      expect(harness.execution.startCalls, hasLength(1));
    });

    test('returns a cached start denial before resolving the gate', () async {
      final owner = _owner('owner-a');
      final cached = _result(
        'process_start',
        '',
        isSuccess: false,
        errorMessage: 'Previously denied',
      );
      final harness = _Harness()..approval.cachedDenials[owner] = cached;

      final result = await harness.handler.handle(_startRequest(owner: owner));

      expect(result, same(cached));
      expect(harness.approval.resolveCalls, isEmpty);
      expect(harness.execution.startCalls, isEmpty);
    });

    test('maps auto-review start denial exactly', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.denied(
          'Untrusted command source',
        );

      final result = await harness.handler.handle(_startRequest(owner: owner));

      expect(
        result.result,
        'Auto-review denied this action. Rationale: Untrusted command source',
      );
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'Auto-review denied: Untrusted command source',
      );
      expect(harness.approval.rememberedDenials, hasLength(1));
      expect(harness.execution.startCalls, isEmpty);
    });

    test('preserves exact start success and failure payloads', () async {
      final owner = _owner('owner-a');
      final payloads = [
        jsonEncode({
          'ok': true,
          'job_id': 'proc-new',
          'status': 'running',
          'command': 'dart run tool/build.dart',
          'working_directory': _ownerARoot,
          'started_at': _fixedTime.toIso8601String(),
          'note': 'The process is running in the background.',
        }),
        jsonEncode({
          'ok': false,
          'code': 'process_start_failed',
          'command': 'dart run tool/build.dart',
          'working_directory': _ownerARoot,
          'error': 'ProcessException: executable not found',
        }),
      ];

      for (final payload in payloads) {
        final expected = _result('process_start', payload);
        final harness = _Harness(clock: () => _fixedTime)
          ..approval.gates[owner] = ToolApprovalGateDecision.fullAccess
          ..execution.nextStartResult = expected;

        final result = await harness.handler.handle(
          _startRequest(
            owner: owner,
            arguments: const {'command': 'dart run tool/build.dart'},
          ),
        );

        expect(result, same(expected));
        expect(result.result, payload);
        expect(result.isSuccess, isTrue);
      }
    });

    test('propagates start exceptions without caching a result', () async {
      final owner = _owner('owner-a');
      final startError = StateError('background start failed');
      final harness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.autoReviewAllowed
        ..execution.startError = startError;

      await expectLater(
        harness.handler.handle(_startRequest(owner: owner)),
        throwsA(same(startError)),
      );

      expect(harness.execution.startCalls.single.owner, owner);
      expect(harness.approval.rememberedDenials, isEmpty);
      expect(harness.approval.rememberedResults, isEmpty);
    });

    test('applies ProcessStartResultPolicy to stale start results', () async {
      final owner = _owner('owner-a');
      final startedAt = _fixedTime.subtract(
        const Duration(seconds: 5, microseconds: 1),
      );
      final harness = _Harness(clock: () => _fixedTime)
        ..approval.gates[owner] = ToolApprovalGateDecision.autoReviewAllowed
        ..execution.nextStartResult = _result(
          'process_start',
          jsonEncode({
            'ok': true,
            'job_id': 'proc-old',
            'status': 'running',
            'command': 'dart run tool/build.dart',
            'working_directory': _ownerARoot,
            'started_at': startedAt.toIso8601String(),
          }),
          isExternal: true,
        );

      final result = await harness.handler.handle(
        _startRequest(
          owner: owner,
          arguments: const {'command': 'dart run tool/build.dart'},
        ),
      );

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, 'process_start returned a stale job result.');
      expect(jsonDecode(result.result), {
        'ok': false,
        'code': 'background_process_start_stale_result',
        'error':
            'process_start returned a non-duplicate job result whose started_at '
            'predates this tool call. Treat the start result as stale until the '
            'process state is verified.',
        'job_id': 'proc-old',
        'command': 'dart run tool/build.dart',
        'working_directory': _ownerARoot,
        'started_at': startedAt.toIso8601String(),
        'tool_dispatched_at': _fixedTime.toIso8601String(),
        'required_action':
            'Use process_status, process_tail, or process_wait for the job_id '
            'if it should still be monitored. Do not report the command as '
            'newly started from this result.',
      });
      expect(harness.approval.rememberedResults.single.result, same(result));
    });

    test('allows an old duplicate-existing start result unchanged', () async {
      final owner = _owner('owner-a');
      final payload = jsonEncode({
        'ok': true,
        'job_id': 'proc-existing',
        'status': 'running',
        'duplicate_existing': true,
        'started_at': _fixedTime
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
      });
      final expected = _result('process_start', payload);
      final harness = _Harness(clock: () => _fixedTime)
        ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
        ..execution.nextStartResult = expected;

      final result = await harness.handler.handle(_startRequest(owner: owner));

      expect(result, same(expected));
      expect(result.result, payload);
    });

    test('rejects exact start expiration boundaries', () async {
      final owner = _owner('owner-a');
      final preHarness = _Harness()
        ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
        ..approval.expirationQueue.add(true);
      _expectExpired(
        await preHarness.handler.handle(_startRequest(owner: owner)),
        'process_start',
      );
      expect(preHarness.execution.startCalls, isEmpty);

      final manualHarness = _Harness()
        ..approval.expirationQueue.addAll([false, false, true]);
      _expectExpired(
        await manualHarness.handler.handle(_startRequest(owner: owner)),
        'process_start',
      );
      expect(manualHarness.execution.startCalls, isEmpty);

      final executionHarness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.autoReviewAllowed
        ..approval.expirationQueue.addAll([false, false, true]);
      _expectExpired(
        await executionHarness.handler.handle(_startRequest(owner: owner)),
        'process_start',
      );
      expect(executionHarness.execution.startCalls, isEmpty);
    });

    test('rolls back a newly started process after owner expiry', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
        ..approval.expirationQueue.addAll([false, true]);

      final result = await harness.handler.handle(_startRequest(owner: owner));

      _expectExpired(result, 'process_start');
      final rollback = harness.execution.cancelCalls.single;
      expect(rollback.owner, owner);
      expect(rollback.toolCallId, 'start-1');
      expect(rollback.identity.externalProcessId, 'job-1');
      expect(rollback.requireTermination, isTrue);
      expect(harness.approval.rememberedResults, isEmpty);
    });

    test('does not roll back a duplicate process after owner expiry', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
        ..approval.expirationQueue.addAll([false, true])
        ..execution.nextStartResult = _result(
          'process_start',
          jsonEncode({
            'ok': true,
            'job_id': 'existing',
            'status': 'running',
            'duplicate_existing': true,
          }),
        );

      final result = await harness.handler.handle(_startRequest(owner: owner));

      _expectExpired(result, 'process_start');
      expect(harness.execution.cancelCalls, isEmpty);
    });

    test('warns when a new start lacks a rollback identity', () async {
      final owner = _owner('owner-a');
      final started = _result(
        'process_start',
        '{"ok":true,"job_id":"job-1","status":"running"}',
      );
      final harness = _Harness()
        ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
        ..approval.expirationQueue.addAll([false, true])
        ..execution.nextStartCompletion = LocalCommandCompletion.completed(
          owner: owner,
          toolCallId: 'start-1',
          value: (result: started, identity: null, startedByRequest: true),
        );

      _expectEffectUncertain(
        await harness.handler.handle(_startRequest(owner: owner)),
        'process_start',
      );
      expect(harness.execution.cancelCalls, isEmpty);
    });

    test('rejects poisoned start identity and effect classification', () async {
      final owner = _owner('owner-a');
      final cases = <BackgroundProcessStartResult>[
        (
          result: _result(
            'process_start',
            '{"ok":true,"job_id":"job-1","status":"running"}',
          ),
          identity: _identity('job-2'),
          startedByRequest: true,
        ),
        (
          result: _result(
            'process_start',
            '{"ok":true,"job_id":"job-1","status":"running"}',
          ),
          identity: _identity('job-1', backendId: ' '),
          startedByRequest: true,
        ),
        (
          result: _result(
            'process_start',
            '{"ok":true,"job_id":"job-1","status":"running"}',
          ),
          identity: _identity('job-1'),
          startedByRequest: false,
        ),
        (
          result: _result(
            'process_start',
            '{"ok":true,"job_id":"job-1","status":"running",'
                '"duplicate_existing":true}',
          ),
          identity: _identity('job-1'),
          startedByRequest: true,
        ),
      ];

      for (final started in cases) {
        final harness = _Harness()
          ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
          ..execution.nextStartCompletion = LocalCommandCompletion.completed(
            owner: owner,
            toolCallId: 'start-1',
            value: started,
          );

        _expectEffectUncertain(
          await harness.handler.handle(_startRequest(owner: owner)),
          'process_start',
        );
        expect(harness.execution.cancelCalls, isEmpty);
        expect(harness.approval.rememberedResults, isEmpty);
      }
    });

    test('returns the exact missing process ID payload', () async {
      final harness = _Harness();
      final cases = [null, '', '   '];

      for (final jobId in cases) {
        final result = await harness.handler.handle(
          _cancelRequest(owner: _owner('owner-a'), jobId: jobId),
        );
        expect(
          result.result,
          '{"ok":false,"code":"job_id_required","error":"job_id is required"}',
        );
        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, 'job_id is required');
      }
      expect(harness.approval.totalCalls, 0);
      expect(harness.lookup.calls, isEmpty);
      expect(harness.execution.cancelCalls, isEmpty);
    });

    test(
      'approves and cancels with exact prompt and payload semantics',
      () async {
        final owner = _owner('owner-a');
        final identity = _identity('job-1');
        final payload = jsonEncode({
          'ok': true,
          'job_id': 'job-1',
          'status': 'running',
          'cancel_requested': true,
        });
        final expected = _result('process_cancel', payload);
        final harness = _Harness()
          ..lookup.identities[owner] = {'job-1': identity}
          ..execution.nextCancelResult = expected;

        final result = await harness.handler.handle(
          _cancelRequest(
            owner: owner,
            defaultWorkingDirectory: '$_ownerARoot/package',
          ),
        );

        expect(result, same(expected));
        final approval = harness.approval.manualCalls.single;
        expect(approval.owner, owner);
        expect(approval.request.toolCallId, 'cancel-1');
        expect(approval.request.execution.command, 'process_cancel job-1');
        expect(
          approval.request.execution.workingDirectory,
          '$_ownerARoot/package',
        );
        expect(approval.request.execution.arguments, {'job_id': 'job-1'});
        expect(approval.request.reason, 'Cancel background process job-1');
        expect(approval.request.warningTitle, 'Cancel background process?');
        expect(
          approval.request.warningMessage,
          'This stops a running local command and may leave partial side effects.',
        );
        expect(harness.lookup.calls.single.owner, owner);
        expect(harness.lookup.calls.single.processId, 'job-1');
        expect(harness.lookup.calls.single.toolCallId, 'cancel-1');
        expect(harness.execution.cancelCalls.single.identity, same(identity));
        expect(harness.execution.cancelCalls.single.toolCallId, 'cancel-1');
        expect(
          harness.execution.cancelCalls.single.requireTermination,
          isFalse,
        );
        expect(
          harness.approval.rememberedResults.single.result,
          same(expected),
        );
      },
    );

    test('uses root and dot cancellation prompt directories', () async {
      final owner = _owner('owner-a');
      final rootHarness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: false,
        );
      final dotHarness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: false,
        );

      await rootHarness.handler.handle(_cancelRequest(owner: owner));
      await dotHarness.handler.handle(
        _cancelRequest(owner: owner, allowedRoot: ''),
      );

      expect(
        rootHarness
            .approval
            .manualCalls
            .single
            .request
            .execution
            .workingDirectory,
        _ownerARoot,
      );
      expect(
        dotHarness
            .approval
            .manualCalls
            .single
            .request
            .execution
            .workingDirectory,
        '.',
      );
    });

    test('maps manual and auto-review cancellation denial exactly', () async {
      final owner = _owner('owner-a');
      final manualHarness = _Harness()
        ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
          approved: false,
        );
      final autoHarness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.denied(
          'Cancellation is unsafe',
        );

      final manual = await manualHarness.handler.handle(
        _cancelRequest(owner: owner),
      );
      final auto = await autoHarness.handler.handle(
        _cancelRequest(owner: owner),
      );

      expect(manual.result, isEmpty);
      expect(manual.isSuccess, isFalse);
      expect(
        manual.errorMessage,
        'User denied background process cancellation',
      );
      expect(
        auto.result,
        'Auto-review denied this action. Rationale: Cancellation is unsafe',
      );
      expect(auto.isSuccess, isFalse);
      expect(auto.errorMessage, 'Auto-review denied: Cancellation is unsafe');
      expect(manualHarness.lookup.calls, isEmpty);
      expect(autoHarness.lookup.calls, isEmpty);
    });

    test('returns cached cancel denial before lookup', () async {
      final owner = _owner('owner-a');
      final cached = _result(
        'process_cancel',
        '',
        isSuccess: false,
        errorMessage: 'Previously denied',
      );
      final harness = _Harness()..approval.cachedDenials[owner] = cached;

      final result = await harness.handler.handle(_cancelRequest(owner: owner));

      expect(result, same(cached));
      expect(harness.approval.resolveCalls, isEmpty);
      expect(harness.lookup.calls, isEmpty);
    });

    test('returns exact not-found result after owner-aware lookup', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.autoReviewAllowed;

      final result = await harness.handler.handle(
        _cancelRequest(owner: owner, jobId: 'missing'),
      );

      expect(
        result.result,
        '{"ok":false,"code":"job_not_found","job_id":"missing",'
        '"error":"No background process job exists for job_id: missing"}',
      );
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      expect(harness.lookup.calls.single.owner, owner);
      expect(harness.execution.cancelCalls, isEmpty);
      expect(harness.approval.rememberedResults.single.result, same(result));
    });

    test(
      'cancels already-exited identities without changing payload',
      () async {
        final owner = _owner('owner-a');
        final identity = _identity('finished', isRunning: false);
        final payload = jsonEncode({
          'ok': true,
          'job_id': 'finished',
          'status': 'exited',
          'exit_code': 0,
          'cancel_requested': true,
        });
        final expected = _result('process_cancel', payload);
        final harness = _Harness()
          ..approval.gates[owner] = ToolApprovalGateDecision.fullAccess
          ..lookup.identities[owner] = {'finished': identity}
          ..execution.nextCancelResult = expected;

        final result = await harness.handler.handle(
          _cancelRequest(owner: owner, jobId: ' finished '),
        );

        expect(result, same(expected));
        expect(result.result, payload);
        expect(
          harness.execution.cancelCalls.single.identity.isRunning,
          isFalse,
        );
        expect(harness.approval.rememberedResults, isEmpty);
      },
    );

    test('preserves exact cancellation backend failure payload', () async {
      final owner = _owner('owner-a');
      final identity = _identity('job-1');
      final payload = jsonEncode({
        'ok': false,
        'code': 'process_cancel_failed',
        'job_id': 'job-1',
        'error': 'Process termination failed',
      });
      final expected = _result('process_cancel', payload);
      final harness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.fullAccess
        ..lookup.identities[owner] = {'job-1': identity}
        ..execution.nextCancelResult = expected;

      final result = await harness.handler.handle(_cancelRequest(owner: owner));

      expect(result, same(expected));
      expect(result.result, payload);
      expect(result.isSuccess, isTrue);
    });

    test('propagates lookup exceptions before cancellation', () async {
      final owner = _owner('owner-a');
      final lookupError = StateError('background lookup failed');
      final harness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.autoReviewAllowed
        ..lookup.error = lookupError;

      await expectLater(
        harness.handler.handle(_cancelRequest(owner: owner)),
        throwsA(same(lookupError)),
      );

      expect(harness.lookup.calls.single.owner, owner);
      expect(harness.execution.cancelCalls, isEmpty);
      expect(harness.approval.rememberedResults, isEmpty);
    });

    test(
      'propagates cancellation exceptions without caching a result',
      () async {
        final owner = _owner('owner-a');
        final cancelError = StateError('background cancellation failed');
        final identity = _identity('job-1');
        final harness = _Harness()
          ..approval.gates[owner] = ToolApprovalGateDecision.autoReviewAllowed
          ..lookup.identities[owner] = {'job-1': identity}
          ..execution.cancelError = cancelError;

        await expectLater(
          harness.handler.handle(_cancelRequest(owner: owner)),
          throwsA(same(cancelError)),
        );

        expect(harness.execution.cancelCalls.single.owner, owner);
        expect(harness.execution.cancelCalls.single.identity, same(identity));
        expect(harness.approval.rememberedResults, isEmpty);
      },
    );

    test('rejects an expired owner before cancellation lookup', () async {
      final owner = _owner('owner-a');
      final harness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.fullAccess
        ..approval.expirationQueue.addAll([false, true])
        ..lookup.identities[owner] = {'job-1': _identity('job-1')};

      final result = await harness.handler.handle(_cancelRequest(owner: owner));

      _expectExpired(result, 'process_cancel');
      expect(harness.lookup.calls, isEmpty);
      expect(harness.execution.cancelCalls, isEmpty);
    });

    test(
      'maps owner-expired async completions without later effects',
      () async {
        final owner = _owner('owner-a');
        final gateHarness = _Harness()
          ..approval.nextGateCompletion = LocalCommandCompletion.ownerExpired(
            owner: owner,
            toolCallId: 'start-1',
          );
        _expectExpired(
          await gateHarness.handler.handle(_startRequest(owner: owner)),
          'process_start',
        );
        expect(gateHarness.execution.startCalls, isEmpty);

        final manualHarness = _Harness()
          ..approval.nextManualCompletion = LocalCommandCompletion.ownerExpired(
            owner: owner,
            toolCallId: 'start-1',
          );
        _expectExpired(
          await manualHarness.handler.handle(_startRequest(owner: owner)),
          'process_start',
        );
        expect(manualHarness.execution.startCalls, isEmpty);

        final ruleHarness = _Harness()
          ..approval.manualDecisions[owner] = const LocalCommandManualApproval(
            approved: true,
            rememberedAction: RememberedCommandPermissionAction.allow,
            rememberedMatch: RememberedCommandPermissionMatch.exact,
          )
          ..rules.nextCompletion = LocalCommandCompletion<Object?>.ownerExpired(
            owner: owner,
            toolCallId: 'start-1',
          );
        _expectExpired(
          await ruleHarness.handler.handle(_startRequest(owner: owner)),
          'process_start',
        );
        expect(ruleHarness.rules.rememberedRules, isEmpty);
        expect(ruleHarness.execution.startCalls, isEmpty);

        final startHarness = _Harness()
          ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
          ..execution.nextStartCompletion = LocalCommandCompletion.ownerExpired(
            owner: owner,
            toolCallId: 'start-1',
          );
        _expectEffectUncertain(
          await startHarness.handler.handle(_startRequest(owner: owner)),
          'process_start',
        );
        expect(startHarness.execution.cancelCalls, isEmpty);

        final lookupHarness = _Harness()
          ..approval.gates[owner] = ToolApprovalGateDecision.fullAccess
          ..lookup.nextCompletion = LocalCommandCompletion.ownerExpired(
            owner: owner,
            toolCallId: 'cancel-1',
          );
        _expectExpired(
          await lookupHarness.handler.handle(_cancelRequest(owner: owner)),
          'process_cancel',
        );
        expect(lookupHarness.execution.cancelCalls, isEmpty);

        final cancelHarness = _Harness()
          ..approval.gates[owner] = ToolApprovalGateDecision.fullAccess
          ..lookup.identities[owner] = {'job-1': _identity('job-1')}
          ..execution.nextCancelCompletion =
              LocalCommandCompletion.ownerExpired(
                owner: owner,
                toolCallId: 'cancel-1',
              );
        _expectEffectUncertain(
          await cancelHarness.handler.handle(_cancelRequest(owner: owner)),
          'process_cancel',
        );
        expect(cancelHarness.approval.rememberedResults, isEmpty);
      },
    );

    test('rejects mismatched completion scopes and process IDs', () async {
      final owner = _owner('owner-a');
      final foreignOwner = _owner('owner-b');
      final gateHarness = _Harness()
        ..approval.nextGateCompletion = LocalCommandCompletion.completed(
          owner: foreignOwner,
          toolCallId: 'start-1',
          value: ToolApprovalGateDecision.fullAccess,
        );
      await expectLater(
        gateHarness.handler.handle(_startRequest(owner: owner)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Background process completion scope mismatch.',
          ),
        ),
      );

      final startHarness = _Harness()
        ..rules.decisions[owner] = CommandPermissionRuleDecision.allow
        ..execution.nextStartCompletion = LocalCommandCompletion.completed(
          owner: owner,
          toolCallId: 'foreign-call',
          value: _startValue(
            _result(
              'process_start',
              '{"ok":true,"job_id":"job-1","status":"running"}',
            ),
          ),
        );
      _expectEffectUncertain(
        await startHarness.handler.handle(_startRequest(owner: owner)),
        'process_start',
      );

      final lookupHarness = _Harness()
        ..approval.gates[owner] = ToolApprovalGateDecision.fullAccess
        ..lookup.identities[owner] = {'job-1': _identity('foreign-job')};
      await expectLater(
        lookupHarness.handler.handle(_cancelRequest(owner: owner)),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Background process lookup ID mismatch.',
          ),
        ),
      );
      expect(lookupHarness.execution.cancelCalls, isEmpty);
    });

    test('isolates cancellation by conversation and generation', () async {
      final ownerA = _owner('conversation-a');
      final ownerB = _owner('conversation-b');
      final ownerANext = _owner('conversation-a', generation: 2);
      final identityA = _identity('shared', backendId: 'backend-a');
      final identityANext = _identity('shared', backendId: 'backend-a-next');
      final harness = _Harness()
        ..approval.gates[ownerA] = ToolApprovalGateDecision.fullAccess
        ..approval.gates[ownerB] = ToolApprovalGateDecision.fullAccess
        ..approval.gates[ownerANext] = ToolApprovalGateDecision.fullAccess
        ..lookup.identities[ownerA] = {'shared': identityA}
        ..lookup.identities[ownerANext] = {'shared': identityANext};

      final foreign = await harness.handler.handle(
        _cancelRequest(
          owner: ownerB,
          allowedRoot: _ownerBRoot,
          jobId: 'shared',
        ),
      );
      final current = await harness.handler.handle(
        _cancelRequest(owner: ownerA, jobId: 'shared'),
      );
      final next = await harness.handler.handle(
        _cancelRequest(owner: ownerANext, jobId: 'shared'),
      );

      expect(jsonDecode(foreign.result), containsPair('code', 'job_not_found'));
      expect(current.isSuccess, isTrue);
      expect(next.isSuccess, isTrue);
      expect(
        harness.execution.cancelCalls.map(
          (call) => call.identity.backendProcessId,
        ),
        ['backend-a', 'backend-a-next'],
      );
      expect(harness.execution.cancelCalls.map((call) => call.owner), [
        ownerA,
        ownerANext,
      ]);
      expect(harness.lookup.calls.map((call) => call.owner), [
        ownerB,
        ownerA,
        ownerANext,
      ]);
    });

    test('never uses a visible owner for start roots or rules', () async {
      final ownerA = _owner('conversation', generation: 1);
      final visibleOwner = _owner('conversation', generation: 2);
      final harness = _Harness()
        ..rules.decisions[ownerA] = CommandPermissionRuleDecision.ask
        ..rules.decisions[visibleOwner] = CommandPermissionRuleDecision.deny
        ..approval.gates[ownerA] = ToolApprovalGateDecision.fullAccess
        ..approval.gates[visibleOwner] = ToolApprovalGateDecision.denied(
          'Visible owner denied',
        );

      await harness.handler.handle(
        _startRequest(
          owner: ownerA,
          allowedRoot: _ownerARoot,
          arguments: const {
            'command': 'touch owner-a.txt',
            'working_directory': 'package',
          },
        ),
      );

      expect(harness.rules.evaluations.single.owner, ownerA);
      expect(harness.approval.resolveCalls.single.owner, ownerA);
      final call = harness.execution.startCalls.single;
      expect(call.owner, ownerA);
      expect(call.operation.workingDirectory, '$_ownerARoot/package');
      expect(call.operation.workingDirectory, isNot(startsWith(_ownerBRoot)));
    });

    test('rejects unsupported tools', () {
      final harness = _Harness();
      final request = BackgroundProcessToolRequest(
        owner: _owner('owner-a'),
        toolCallId: 'status-1',
        toolName: 'process_status',
        allowedWorkingDirectoryRoot: _ownerARoot,
        arguments: const {'job_id': 'job-1'},
      );

      expect(
        () => harness.handler.handle(request),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.invalidValue,
            'invalidValue',
            'process_status',
          ),
        ),
      );
    });
  });
}

final class _Harness {
  _Harness({DateTime Function()? clock})
    : execution = _FakeExecutionPort(),
      lookup = _FakeLookupPort(),
      approval = _FakeApprovalPort(),
      rules = _FakeRuleStore() {
    handler = BackgroundProcessToolHandler(
      executionPort: execution,
      lookupPort: lookup,
      approvalPort: approval,
      permissionRuleStorePort: rules,
      clock: clock ?? () => _fixedTime,
    );
  }

  final _FakeExecutionPort execution;
  final _FakeLookupPort lookup;
  final _FakeApprovalPort approval;
  final _FakeRuleStore rules;
  late final BackgroundProcessToolHandler handler;
}

typedef _StartCall = ({
  ChatTurnOwner owner,
  LocalCommandExecutionRequest operation,
});
typedef _CancelCall = ({
  ChatTurnOwner owner,
  String toolCallId,
  BackgroundProcessIdentity identity,
  bool requireTermination,
});

final class _FakeExecutionPort implements BackgroundProcessExecutionPort {
  final List<_StartCall> startCalls = [];
  final List<_CancelCall> cancelCalls = [];
  LocalCommandCompletion<BackgroundProcessStartResult>? nextStartCompletion;
  LocalCommandCompletion<McpToolResult>? nextCancelCompletion;
  McpToolResult? nextStartResult;
  McpToolResult? nextCancelResult;
  Object? startError;
  Object? cancelError;

  @override
  Future<LocalCommandCompletion<BackgroundProcessStartResult>> start(
    ChatTurnOwner owner,
    LocalCommandExecutionRequest operation,
  ) async {
    startCalls.add((owner: owner, operation: operation));
    if (startError case final error?) {
      throw error;
    }
    if (nextStartCompletion case final completion?) return completion;
    final result =
        nextStartResult ??
        _result(
          'process_start',
          jsonEncode({
            'ok': true,
            'job_id': 'job-${startCalls.length}',
            'status': 'running',
          }),
        );
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: operation.toolCallId,
      value: _startValue(result),
    );
  }

  @override
  Future<LocalCommandCompletion<McpToolResult>> cancel(
    ChatTurnOwner owner,
    String toolCallId,
    BackgroundProcessIdentity identity, {
    bool requireTermination = false,
  }) async {
    cancelCalls.add((
      owner: owner,
      toolCallId: toolCallId,
      identity: identity,
      requireTermination: requireTermination,
    ));
    if (cancelError case final error?) {
      throw error;
    }
    if (nextCancelCompletion case final completion?) return completion;
    final result =
        nextCancelResult ??
        _result(
          'process_cancel',
          jsonEncode({
            'ok': true,
            'job_id': identity.externalProcessId,
            'status': identity.isRunning ? 'running' : 'exited',
            'cancel_requested': true,
          }),
        );
    return LocalCommandCompletion.completed(
      owner: owner,
      toolCallId: toolCallId,
      value: result,
    );
  }
}

typedef _LookupCall = ({
  ChatTurnOwner owner,
  String toolCallId,
  String processId,
});

final class _FakeLookupPort implements BackgroundProcessLookupPort {
  final Map<ChatTurnOwner, Map<String, BackgroundProcessIdentity>> identities =
      {};
  final List<_LookupCall> calls = [];
  LocalCommandCompletion<BackgroundProcessIdentity?>? nextCompletion;
  Object? error;

  @override
  Future<LocalCommandCompletion<BackgroundProcessIdentity?>> lookup(
    ChatTurnOwner owner,
    String toolCallId,
    String externalProcessId,
  ) async {
    calls.add((
      owner: owner,
      toolCallId: toolCallId,
      processId: externalProcessId,
    ));
    if (error case final error?) {
      throw error;
    }
    return nextCompletion ??
        LocalCommandCompletion.completed(
          owner: owner,
          toolCallId: toolCallId,
          value: identities[owner]?[externalProcessId],
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
typedef _ManualCall = ({
  ChatTurnOwner owner,
  LocalCommandApprovalRequest request,
  ToolApprovalGateDecision gate,
});
typedef _RememberedResult = ({
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
  final List<_ManualCall> manualCalls = [];
  final List<_RememberedResult> rememberedDenials = [];
  final List<_RememberedResult> rememberedResults = [];
  LocalCommandCompletion<ToolApprovalGateDecision>? nextGateCompletion;
  LocalCommandCompletion<LocalCommandManualApproval>? nextManualCompletion;
  LocalCommandCompletion<McpToolResult>? nextCachedDenialCompletion;
  LocalCommandCompletion<Object?>? nextRememberDenialCompletion;
  LocalCommandCompletion<Object?>? nextRememberResultCompletion;

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
    return expirationQueue.isEmpty ? false : expirationQueue.removeAt(0);
  }

  @override
  LocalCommandCompletion<Object?> rememberDenial(
    ChatTurnOwner owner,
    LocalCommandApprovalRequest request,
    McpToolResult result,
  ) {
    rememberedDenials.add((owner: owner, request: request, result: result));
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
