import 'dart:convert';
import 'dart:io';

import 'package:caverno/features/chat/data/datasources/background_process_monitor_service.dart';
import 'package:caverno/features/chat/data/datasources/background_process_tools.dart';
import 'package:caverno/features/chat/data/datasources/built_in_local_command_tool_handler.dart';
import 'package:caverno/features/chat/data/datasources/first_party_tool_execution_result.dart';
import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _CommandCall = ({String command, String workingDirectory});
typedef _ProcessStartCall = ({
  String command,
  String workingDirectory,
  String? label,
});
typedef _ProcessValueCall = ({String jobId, int? value});
typedef _ProcessListCall = ({
  List<String>? jobIds,
  bool includeFinished,
  int? limit,
});

ChatTurnOwner _turnOwner({
  String conversationId = 'local-command-handler',
  int generation = 1,
}) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: generation,
  );
}

void main() {
  group('BuiltInLocalCommandToolHandler', () {
    final owner = _turnOwner();

    test('owns the exact ordered local command family', () {
      final unsupportedTools = _FakeBackgroundProcessTools(supported: false);
      final unsupportedHandler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: unsupportedTools,
      );
      final supportedHandler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: _FakeBackgroundProcessTools(),
      );

      expect(BuiltInLocalCommandToolHandler.toolNames, const [
        'local_execute_command',
        'process_start',
        'process_status',
        'process_tail',
        'process_wait',
        'process_cancel',
        'process_list',
        'run_tests',
      ]);
      expect(
        _definitionName(unsupportedHandler.localExecuteCommandDefinition),
        'local_execute_command',
      );
      expect(unsupportedHandler.processDefinitions.map(_definitionName), const [
        'process_start',
        'process_status',
        'process_tail',
        'process_wait',
        'process_cancel',
        'process_list',
      ]);
      expect(
        _definitionName(unsupportedHandler.runTestsDefinition),
        'run_tests',
      );
      for (final name in BuiltInLocalCommandToolHandler.toolNames) {
        expect(unsupportedHandler.handles(name), isTrue, reason: name);
      }
      expect(unsupportedHandler.handles('run_python_script'), isFalse);
      expect(unsupportedHandler.supportsBackgroundProcesses, isFalse);
      expect(supportedHandler.supportsBackgroundProcesses, isTrue);
    });

    test('rejects an unknown tool name', () async {
      final handler = BuiltInLocalCommandToolHandler();

      expect(
        () => handler.execute(name: 'unknown', arguments: const {}),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.invalidValue,
            'invalidValue',
            'unknown',
          ),
        ),
      );
    });

    test('requires an exact owner for background process state', () async {
      final tools = _FakeBackgroundProcessTools();
      final monitor = _FakeBackgroundProcessMonitorService();
      addTearDown(monitor.dispose);
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: tools,
        backgroundProcessMonitorService: monitor,
      );
      const cases = <(String, Map<String, dynamic>)>[
        (
          'local_execute_command',
          {
            'command': 'sleep 1',
            'working_directory': '/tmp',
            'background': true,
          },
        ),
        ('process_start', {'command': 'sleep 1', 'working_directory': '/tmp'}),
        ('process_status', {'job_id': 'job'}),
        ('process_tail', {'job_id': 'job'}),
        ('process_wait', {'job_id': 'job'}),
        ('process_cancel', {'job_id': 'job'}),
        ('process_list', {}),
      ];

      for (final testCase in cases) {
        final result = await handler.execute(
          name: testCase.$1,
          arguments: testCase.$2,
        );
        expect(result.isSuccess, isFalse, reason: testCase.$1);
        expect(
          jsonDecode(result.result),
          containsPair('code', 'chat_turn_owner_required'),
          reason: testCase.$1,
        );
      }
      expect(tools.totalCalls, 0);
      expect(monitor.listCalls, isEmpty);
    });

    test(
      'rejects missing required arguments without invoking dependencies',
      () async {
        final foregroundCalls = <_CommandCall>[];
        final tools = _FakeBackgroundProcessTools();
        final handler = BuiltInLocalCommandToolHandler(
          backgroundProcessTools: tools,
          foregroundCommandRunner:
              ({required command, required workingDirectory}) async {
                foregroundCalls.add((
                  command: command,
                  workingDirectory: workingDirectory,
                ));
                return 'unexpected';
              },
        );
        const cases = [
          (
            'local_execute_command',
            <String, dynamic>{},
            'command and working_directory are required',
          ),
          (
            'local_execute_command',
            <String, dynamic>{'command': 'echo ok'},
            'command and working_directory are required',
          ),
          (
            'process_start',
            <String, dynamic>{'working_directory': '/tmp'},
            'command and working_directory are required',
          ),
          ('process_status', <String, dynamic>{}, 'job_id is required'),
          ('process_tail', <String, dynamic>{}, 'job_id is required'),
          ('process_wait', <String, dynamic>{}, 'job_id is required'),
          ('process_cancel', <String, dynamic>{}, 'job_id is required'),
        ];

        for (final testCase in cases) {
          final result = await handler.execute(
            owner: owner,
            name: testCase.$1,
            arguments: testCase.$2,
          );
          expect(result.toolName, testCase.$1);
          expect(result.result, isEmpty);
          expect(result.isSuccess, isFalse);
          expect(result.errorMessage, testCase.$3);
        }
        expect(foregroundCalls, isEmpty);
        expect(tools.totalCalls, 0);
      },
    );

    test('normalizes and forwards a foreground command', () async {
      final calls = <_CommandCall>[];
      final handler = BuiltInLocalCommandToolHandler(
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              calls.add((command: command, workingDirectory: workingDirectory));
              return '{"ok":false,"code":"runner_failure"}';
            },
      );

      final result = await handler.execute(
        owner: owner,
        name: 'local_execute_command',
        arguments: const {
          'command': '  echo ok<|im_end|>  ',
          'working_directory': ' /tmp/project ',
          'background': 'no',
        },
      );

      expect(calls, const [
        (command: 'echo ok', workingDirectory: '/tmp/project'),
      ]);
      expect(result.result, '{"ok":false,"code":"runner_failure"}');
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
    });

    test('blocks an out-of-project internal read before the runner', () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'built_in_command_read_fence_',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final project = await Directory('${sandbox.path}/project').create();
      final outside = await File(
        '${sandbox.path}/secret.txt',
      ).writeAsString('secret');
      var runnerCalls = 0;
      final handler = BuiltInLocalCommandToolHandler(
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              runnerCalls += 1;
              return 'unexpected';
            },
      );

      final result = await handler.execute(
        owner: owner,
        name: 'local_execute_command',
        arguments: {
          'command': 'cat ${outside.path}',
          'working_directory': project.path,
          'allowed_read_root': project.path,
        },
      );

      expect(result.isSuccess, isFalse);
      expect(
        jsonDecode(result.result),
        containsPair('code', 'project_read_outside_root'),
      );
      final backgroundResult = await handler.execute(
        owner: owner,
        name: 'process_start',
        arguments: {
          'command': 'cat ${outside.path}',
          'working_directory': project.path,
          'allowed_read_root': project.path,
        },
      );
      expect(backgroundResult.isSuccess, isFalse);
      expect(
        jsonDecode(backgroundResult.result),
        containsPair('code', 'project_read_outside_root'),
      );
      expect(runnerCalls, 0);
    });

    test('blocks an out-of-project write before the runner', () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'built_in_command_write_fence_',
      );
      addTearDown(() => sandbox.delete(recursive: true));
      final project = await Directory('${sandbox.path}/project').create();
      final sibling = await Directory(
        '${sandbox.path}/project-secrets',
      ).create();
      var runnerCalls = 0;
      final handler = BuiltInLocalCommandToolHandler(
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              runnerCalls += 1;
              return 'unexpected';
            },
      );

      final result = await handler.execute(
        owner: owner,
        name: 'local_execute_command',
        arguments: {
          'command': 'touch ../project-secrets/secret.txt',
          'working_directory': project.path,
          'allowed_read_root': project.path,
        },
      );

      expect(result.isSuccess, isFalse);
      expect(
        jsonDecode(result.result),
        containsPair('code', 'project_mutation_outside_root'),
      );
      expect(File('${sibling.path}/secret.txt').existsSync(), isFalse);
      expect(runnerCalls, 0);
    });

    test(
      'blocks a symlink-escaping working directory before the runner',
      () async {
        final sandbox = await Directory.systemTemp.createTemp(
          'built_in_command_cwd_fence_',
        );
        addTearDown(() => sandbox.delete(recursive: true));
        final project = await Directory('${sandbox.path}/project').create();
        final sibling = await Directory(
          '${sandbox.path}/project-secrets',
        ).create();
        final link = Link('${project.path}/escape');
        try {
          await link.create(sibling.path);
        } on FileSystemException {
          return;
        }
        var runnerCalls = 0;
        final handler = BuiltInLocalCommandToolHandler(
          foregroundCommandRunner:
              ({required command, required workingDirectory}) async {
                runnerCalls += 1;
                return 'unexpected';
              },
        );

        final result = await handler.execute(
          owner: owner,
          name: 'local_execute_command',
          arguments: {
            'command': 'touch secret.txt',
            'working_directory': link.path,
            'allowed_read_root': project.path,
          },
        );

        expect(result.isSuccess, isFalse);
        expect(
          jsonDecode(result.result),
          containsPair('code', 'project_mutation_outside_root'),
        );
        expect(File('${sibling.path}/secret.txt').existsSync(), isFalse);
        expect(runnerCalls, 0);
      },
    );

    test('carries the reported exit status without failing the tool', () async {
      // A command that exits non-zero is a command outcome, not a tool
      // failure: the result stays successful and the status rides along as a
      // fact, so downstream consumers stop parsing stdout to find it.
      final handler = BuiltInLocalCommandToolHandler(
        foregroundCommandResultRunner:
            ({required command, required workingDirectory}) async =>
                const FirstPartyToolExecutionResult(
                  result: '{"exit_code":2,"stdout":"","stderr":"tests failed"}',
                  outcome: ToolOutcome(exitCode: 2),
                ),
      );

      final result = await handler.execute(
        owner: owner,
        name: 'local_execute_command',
        arguments: const {
          'command': 'flutter test',
          'working_directory': '/tmp/project',
        },
      );

      expect(result.isSuccess, isTrue);
      expect(result.outcome?.exitCode, 2);
      expect(result.outcome?.hasFailingExitCode, isTrue);
    });

    test('reports no exit status when the command never reached one', () async {
      final handler = BuiltInLocalCommandToolHandler(
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async =>
                'command runner unavailable',
      );

      final result = await handler.execute(
        owner: owner,
        name: 'local_execute_command',
        arguments: const {
          'command': 'flutter test',
          'working_directory': '/tmp/project',
        },
      );

      expect(result.outcome, isNull);
    });

    test('coerces every supported truthy background value', () async {
      final foregroundCalls = <_CommandCall>[];
      final tools = _FakeBackgroundProcessTools(startResult: 'started');
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: tools,
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              foregroundCalls.add((
                command: command,
                workingDirectory: workingDirectory,
              ));
              return 'foreground';
            },
      );

      for (final value in <Object>[true, 1, -1, 'true', ' 1 ', 'YES']) {
        final result = await handler.execute(
          owner: owner,
          name: 'local_execute_command',
          arguments: <String, dynamic>{
            'command': ' sleep 1 ',
            'working_directory': ' /tmp/project ',
            'background': value,
            'label': ' job ',
          },
        );
        expect(result.result, 'started', reason: '$value');
        expect(result.isSuccess, isTrue, reason: '$value');
      }

      expect(foregroundCalls, isEmpty);
      expect(tools.startCalls, hasLength(6));
      expect(tools.startCalls.toSet(), {
        const (
          command: 'sleep 1',
          workingDirectory: '/tmp/project',
          label: 'job',
        ),
      });
    });

    test('treats unsupported background values as foreground', () async {
      final calls = <_CommandCall>[];
      final tools = _FakeBackgroundProcessTools();
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: tools,
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              calls.add((command: command, workingDirectory: workingDirectory));
              return 'foreground';
            },
      );

      for (final value in <Object?>[null, false, 0, 'false', 'no', const []]) {
        final result = await handler.execute(
          owner: owner,
          name: 'local_execute_command',
          arguments: <String, dynamic>{
            'command': 'echo ok',
            'working_directory': '/tmp',
            'background': value,
          },
        );
        expect(result.result, 'foreground', reason: '$value');
      }

      expect(calls, hasLength(6));
      expect(tools.startCalls, isEmpty);
    });

    test('attaches lifecycle outcomes to single-process results', () async {
      const running = '{"ok":true,"job_id":"job","status":"running"}';
      const exited =
          '{"ok":true,"job_id":"job","status":"exited","exit_code":4}';
      final tools = _FakeBackgroundProcessTools(
        startResult: running,
        statusResult: running,
        tailResult: running,
        waitResult: exited,
        cancelResult: exited,
      );
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: tools,
      );

      final start = await handler.execute(
        owner: owner,
        name: 'process_start',
        arguments: const {'command': 'sleep 1', 'working_directory': '/tmp'},
      );
      expect(start.outcome?.processState, ToolProcessState.running);
      expect(start.outcome?.exitCode, isNull);

      for (final name in const ['process_status', 'process_tail']) {
        final result = await handler.execute(
          owner: owner,
          name: name,
          arguments: const {'job_id': 'job'},
        );
        expect(
          result.outcome?.processState,
          ToolProcessState.running,
          reason: name,
        );
      }

      for (final name in const ['process_wait', 'process_cancel']) {
        final result = await handler.execute(
          owner: owner,
          name: name,
          arguments: const {'job_id': 'job'},
        );
        expect(
          result.outcome?.processState,
          ToolProcessState.exited,
          reason: name,
        );
        expect(result.outcome?.exitCode, 4, reason: name);
      }
    });

    test('blocks Git writes before foreground or background runners', () async {
      final foregroundCalls = <_CommandCall>[];
      final tools = _FakeBackgroundProcessTools();
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: tools,
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              foregroundCalls.add((
                command: command,
                workingDirectory: workingDirectory,
              ));
              return 'unexpected';
            },
      );
      final cases = <(String, Map<String, dynamic>)>[
        (
          'local_execute_command',
          const {
            'command': 'git merge feature/work',
            'working_directory': '/tmp',
          },
        ),
        (
          'local_execute_command',
          const {
            'command': 'git worktree remove /tmp/worktree',
            'working_directory': '/tmp',
            'background': true,
          },
        ),
        (
          'process_start',
          const {'command': 'git checkout main', 'working_directory': '/tmp'},
        ),
      ];

      for (final testCase in cases) {
        final result = await handler.execute(
          owner: owner,
          name: testCase.$1,
          arguments: testCase.$2,
        );
        expect(result.isSuccess, isFalse, reason: testCase.$1);
        expect(
          result.errorMessage,
          'Use git_execute_command for git write commands',
        );
        expect(
          jsonDecode(result.result),
          containsPair('code', 'local_shell_git_write_blocked'),
        );
      }
      expect(foregroundCalls, isEmpty);
      expect(tools.startCalls, isEmpty);
    });

    test('preserves every unavailable dependency envelope', () async {
      final handler = BuiltInLocalCommandToolHandler();
      final expectedToolsUnavailable = {
        'ok': false,
        'code': 'background_process_tools_unavailable',
        'error': 'Background process tools are not available',
      };

      final localBackground = await handler.execute(
        owner: owner,
        name: 'local_execute_command',
        arguments: const {
          'command': 'sleep 1',
          'working_directory': '/tmp',
          'background': true,
        },
      );
      expect(jsonDecode(localBackground.result), expectedToolsUnavailable);
      expect(localBackground.isSuccess, isFalse);
      expect(
        localBackground.errorMessage,
        'Background process tools are not available',
      );

      final processStart = await handler.execute(
        owner: owner,
        name: 'process_start',
        arguments: const {'command': 'sleep 1', 'working_directory': '/tmp'},
      );
      expect(processStart.result, isEmpty);
      expect(processStart.isSuccess, isFalse);
      expect(
        processStart.errorMessage,
        'Background process tools are not available',
      );

      for (final name in const [
        'process_status',
        'process_tail',
        'process_wait',
        'process_cancel',
      ]) {
        final result = await handler.execute(
          owner: owner,
          name: name,
          arguments: const {'job_id': 'missing'},
        );
        expect(
          jsonDecode(result.result),
          expectedToolsUnavailable,
          reason: name,
        );
        expect(result.isSuccess, isFalse, reason: name);
        expect(
          result.errorMessage,
          'Background process tools are not available',
          reason: name,
        );
      }

      final processList = await handler.execute(
        owner: owner,
        name: 'process_list',
        arguments: const {},
      );
      expect(jsonDecode(processList.result), {
        'ok': false,
        'code': 'background_process_monitor_unavailable',
        'error': 'Background process monitor is not available',
      });
      expect(processList.isSuccess, isFalse);
      expect(
        processList.errorMessage,
        'Background process monitor is not available',
      );
    });

    test('preserves legacy success for provider failure payloads', () async {
      const failure = '{"ok":false,"code":"provider_failure"}';
      final tools = _FakeBackgroundProcessTools(
        startResult: failure,
        statusResult: failure,
        tailResult: failure,
        waitResult: failure,
        cancelResult: failure,
      );
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: tools,
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async => failure,
      );
      final calls = <(String, Map<String, dynamic>)>[
        (
          'local_execute_command',
          const {'command': 'echo foreground', 'working_directory': '/tmp'},
        ),
        (
          'local_execute_command',
          const {
            'command': 'sleep 1',
            'working_directory': '/tmp',
            'background': true,
          },
        ),
        (
          'process_start',
          const {'command': 'sleep 1', 'working_directory': '/tmp'},
        ),
        ('process_status', const {'job_id': 'job'}),
        ('process_tail', const {'job_id': 'job'}),
        ('process_wait', const {'job_id': 'job'}),
        ('process_cancel', const {'job_id': 'job'}),
      ];

      for (final call in calls) {
        final result = await handler.execute(
          owner: owner,
          name: call.$1,
          arguments: call.$2,
        );
        expect(result.result, failure, reason: call.$1);
        expect(result.isSuccess, isTrue, reason: call.$1);
        expect(result.errorMessage, isNull, reason: call.$1);
      }
    });

    test(
      'forwards process operation arguments without reinterpretation',
      () async {
        final tools = _FakeBackgroundProcessTools(
          startResult: 'start',
          statusResult: 'status',
          tailResult: 'tail',
          waitResult: 'wait',
          cancelResult: 'cancel',
        );
        final handler = BuiltInLocalCommandToolHandler(
          backgroundProcessTools: tools,
        );

        await handler.execute(
          owner: owner,
          name: 'process_start',
          arguments: const {
            'command': ' sleep 1<|end|> ',
            'working_directory': ' /tmp/project ',
            'label': ' build ',
          },
        );
        await handler.execute(
          owner: owner,
          name: 'process_status',
          arguments: const {'job_id': ' job ', 'tail_chars': 123.9},
        );
        await handler.execute(
          owner: owner,
          name: 'process_tail',
          arguments: const {'job_id': ' job ', 'max_chars': 456.8},
        );
        await handler.execute(
          owner: owner,
          name: 'process_wait',
          arguments: const {'job_id': ' job ', 'wait_ms': 789.7},
        );
        await handler.execute(
          owner: owner,
          name: 'process_cancel',
          arguments: const {'job_id': ' job '},
        );

        expect(tools.startCalls, const [
          (
            command: 'sleep 1',
            workingDirectory: '/tmp/project',
            label: 'build',
          ),
        ]);
        expect(tools.statusCalls, const [(jobId: 'job', value: 123)]);
        expect(tools.tailCalls, const [(jobId: 'job', value: 456)]);
        expect(tools.waitCalls, const [(jobId: 'job', value: 789)]);
        expect(tools.cancelCalls, const ['job']);
        expect(tools.startOwners, [same(owner)]);
        expect(tools.statusOwners, [same(owner)]);
        expect(tools.tailOwners, [same(owner)]);
        expect(tools.waitOwners, [same(owner)]);
        expect(tools.cancelOwners, [same(owner)]);
      },
    );

    test('keeps process jobs invisible to a different turn owner', () async {
      final peerOwner = _turnOwner(generation: 2);
      const visibleResult =
          '{"ok":true,"job_id":"shared-job","status":"running"}';
      final tools = _FakeBackgroundProcessTools(
        visibleOwner: owner,
        statusResult: visibleResult,
        tailResult: visibleResult,
        waitResult: visibleResult,
        cancelResult: visibleResult,
      );
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessTools: tools,
      );
      const operations = <String>[
        'process_status',
        'process_tail',
        'process_wait',
        'process_cancel',
      ];

      for (final name in operations) {
        final visible = await handler.execute(
          owner: owner,
          name: name,
          arguments: const {'job_id': 'shared-job'},
        );
        final hidden = await handler.execute(
          owner: peerOwner,
          name: name,
          arguments: const {'job_id': 'shared-job'},
        );

        expect(jsonDecode(visible.result), containsPair('ok', true));
        expect(
          jsonDecode(hidden.result),
          containsPair('code', 'job_not_found'),
          reason: name,
        );
      }
      expect(tools.statusOwners, [same(owner), same(peerOwner)]);
      expect(tools.tailOwners, [same(owner), same(peerOwner)]);
      expect(tools.waitOwners, [same(owner), same(peerOwner)]);
      expect(tools.cancelOwners, [same(owner), same(peerOwner)]);
    });

    test('rejects invalid process_list job_ids before monitor calls', () async {
      final monitor = _FakeBackgroundProcessMonitorService();
      addTearDown(monitor.dispose);
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessMonitorService: monitor,
      );

      final result = await handler.execute(
        owner: owner,
        name: 'process_list',
        arguments: const {'job_ids': 'job-a'},
      );

      expect(result.isSuccess, isFalse);
      expect(jsonDecode(result.result), {
        'ok': false,
        'code': 'invalid_job_ids',
        'error': 'job_ids must be an array of strings',
      });
      expect(result.errorMessage, 'job_ids must be an array of strings');
      expect(monitor.listCalls, isEmpty);
      expect(monitor.refreshActiveCalls, 0);
      expect(monitor.refreshJobCalls, isEmpty);
    });

    test(
      'filters process_list ids and serializes counts at a fixed time',
      () async {
        final running = _snapshot(jobId: 'job-a', status: 'running');
        final finished = _snapshot(
          jobId: 'job-b',
          status: 'exited',
          exitCode: 0,
        );
        final monitor = _FakeBackgroundProcessMonitorService(
          snapshots: [running, finished],
          active: [
            running,
            _snapshot(jobId: 'job-c', status: 'running'),
          ],
        );
        addTearDown(monitor.dispose);
        final handler = BuiltInLocalCommandToolHandler(
          backgroundProcessMonitorService: monitor,
          clock: () => DateTime.parse('2026-07-17T03:04:05.000Z'),
        );

        final result = await handler.execute(
          owner: owner,
          name: 'process_list',
          arguments: const {
            'job_ids': [' job-a ', 3, '', 'job-b', null],
            'include_finished': 'false',
            'refresh': 'true',
            'limit': 2.9,
          },
        );

        expect(monitor.listCalls, hasLength(1));
        expect(monitor.listCalls.single.jobIds, ['job-a', 'job-b']);
        expect(monitor.listCalls.single.includeFinished, isTrue);
        expect(monitor.listCalls.single.limit, 2);
        expect(monitor.refreshActiveCalls, 0);
        expect(monitor.refreshJobCalls, isEmpty);
        expect(result.isSuccess, isTrue);
        expect(jsonDecode(result.result), {
          'ok': true,
          'generated_at': '2026-07-17T03:04:05.000Z',
          'job_count': 2,
          'jobs': [running.toJson(), finished.toJson()],
          'active_count': 2,
          'finished_count': 1,
        });
      },
    );

    test('uses process_list defaults and refreshes active jobs', () async {
      final monitor = _FakeBackgroundProcessMonitorService();
      addTearDown(monitor.dispose);
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessMonitorService: monitor,
      );

      await handler.execute(
        owner: owner,
        name: 'process_list',
        arguments: const {'refresh': true},
      );

      expect(monitor.refreshActiveCalls, 1);
      expect(monitor.refreshJobCalls, isEmpty);
      expect(monitor.listCalls, hasLength(1));
      expect(monitor.listCalls.single.jobIds, isEmpty);
      expect(monitor.listCalls.single.includeFinished, isTrue);
      expect(monitor.listCalls.single.limit, isNull);
    });

    test('refreshes only requested process_list jobs', () async {
      final monitor = _FakeBackgroundProcessMonitorService();
      addTearDown(monitor.dispose);
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessMonitorService: monitor,
      );

      await handler.execute(
        owner: owner,
        name: 'process_list',
        arguments: const {
          'job_ids': [' job-a ', false, 'job-b'],
          'include_finished': false,
          'refresh': true,
          'limit': 1,
        },
      );

      expect(monitor.refreshActiveCalls, 0);
      expect(monitor.refreshJobCalls, const [
        ['job-a', 'job-b'],
      ]);
      expect(monitor.listCalls, hasLength(1));
      expect(monitor.listCalls.single.jobIds, ['job-a', 'job-b']);
      expect(monitor.listCalls.single.includeFinished, isFalse);
      expect(monitor.listCalls.single.limit, 1);
    });

    test('keeps process_list snapshots isolated by exact owner', () async {
      final peerOwner = _turnOwner(
        conversationId: owner.conversationId,
        generation: 2,
      );
      final ownerSnapshot = _snapshot(jobId: 'owner-job', status: 'running');
      final peerSnapshot = _snapshot(jobId: 'peer-job', status: 'running');
      final monitor = _FakeBackgroundProcessMonitorService(
        snapshotsByOwner: {
          owner: [ownerSnapshot],
          peerOwner: [peerSnapshot],
        },
        activeByOwner: {
          owner: [ownerSnapshot],
          peerOwner: [peerSnapshot],
        },
      );
      addTearDown(monitor.dispose);
      final handler = BuiltInLocalCommandToolHandler(
        backgroundProcessMonitorService: monitor,
      );

      final ownerResult = await handler.execute(
        owner: owner,
        name: 'process_list',
        arguments: const {},
      );
      final peerResult = await handler.execute(
        owner: peerOwner,
        name: 'process_list',
        arguments: const {},
      );

      final ownerJobs =
          (jsonDecode(ownerResult.result) as Map<String, dynamic>)['jobs']
              as List<dynamic>;
      final peerJobs =
          (jsonDecode(peerResult.result) as Map<String, dynamic>)['jobs']
              as List<dynamic>;
      expect(
        ownerJobs.single as Map<String, dynamic>,
        containsPair('job_id', 'owner-job'),
      );
      expect(
        peerJobs.single as Map<String, dynamic>,
        containsPair('job_id', 'peer-job'),
      );
      expect(monitor.listOwners, [same(owner), same(peerOwner)]);
    });

    test('returns the exact run_tests approval sentinel', () async {
      final handler = BuiltInLocalCommandToolHandler();

      final result = await handler.execute(
        owner: owner,
        name: 'run_tests',
        arguments: const {},
      );

      expect(result.toolName, 'run_tests');
      expect(
        result.result,
        '{"error":"run_tests must be executed through the chat command approval flow.",'
        '"code":"approval_required","result_origin":"refusal"}',
      );
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'run_tests must be executed through the chat command approval flow',
      );
    });

    test('propagates command provider exceptions', () async {
      final handler = BuiltInLocalCommandToolHandler(
        foregroundCommandRunner:
            ({required command, required workingDirectory}) async {
              throw StateError('provider failed');
            },
      );

      expect(
        () => handler.execute(
          owner: owner,
          name: 'local_execute_command',
          arguments: const {'command': 'echo ok', 'working_directory': '/tmp'},
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

String _definitionName(Map<String, dynamic> definition) {
  return (definition['function']! as Map<String, dynamic>)['name']! as String;
}

BackgroundProcessMonitorSnapshot _snapshot({
  required String jobId,
  required String status,
  int? exitCode,
}) {
  return BackgroundProcessMonitorSnapshot(
    jobId: jobId,
    status: status,
    command: 'command-$jobId',
    workingDirectory: '/tmp',
    startedAt: DateTime.parse('2026-07-17T01:00:00.000Z'),
    lastCheckedAt: DateTime.parse('2026-07-17T02:00:00.000Z'),
    exitCode: exitCode,
  );
}

class _FakeBackgroundProcessTools extends BackgroundProcessTools {
  _FakeBackgroundProcessTools({
    this.supported = true,
    this.startResult = '{}',
    this.statusResult = '{}',
    this.tailResult = '{}',
    this.waitResult = '{}',
    this.cancelResult = '{}',
    this.visibleOwner,
  });

  final bool supported;
  final String startResult;
  final String statusResult;
  final String tailResult;
  final String waitResult;
  final String cancelResult;
  final ChatTurnOwner? visibleOwner;
  final List<_ProcessStartCall> startCalls = <_ProcessStartCall>[];
  final List<_ProcessValueCall> statusCalls = <_ProcessValueCall>[];
  final List<_ProcessValueCall> tailCalls = <_ProcessValueCall>[];
  final List<_ProcessValueCall> waitCalls = <_ProcessValueCall>[];
  final List<String> cancelCalls = <String>[];
  final List<ChatTurnOwner> startOwners = <ChatTurnOwner>[];
  final List<ChatTurnOwner> statusOwners = <ChatTurnOwner>[];
  final List<ChatTurnOwner> tailOwners = <ChatTurnOwner>[];
  final List<ChatTurnOwner> waitOwners = <ChatTurnOwner>[];
  final List<ChatTurnOwner> cancelOwners = <ChatTurnOwner>[];

  int get totalCalls =>
      startCalls.length +
      statusCalls.length +
      tailCalls.length +
      waitCalls.length +
      cancelCalls.length;

  @override
  bool get isSupported => supported;

  @override
  Future<String> start({
    required ChatTurnOwner owner,
    required String command,
    required String workingDirectory,
    String? label,
  }) async {
    startOwners.add(owner);
    startCalls.add((
      command: command,
      workingDirectory: workingDirectory,
      label: label,
    ));
    return startResult;
  }

  @override
  Future<FirstPartyToolExecutionResult> startExecution({
    required ChatTurnOwner owner,
    required String command,
    required String workingDirectory,
    String? label,
  }) async => _execution(
    await start(
      owner: owner,
      command: command,
      workingDirectory: workingDirectory,
      label: label,
    ),
  );

  @override
  Future<String> status({
    required ChatTurnOwner owner,
    required String jobId,
    int? tailChars,
  }) async {
    statusOwners.add(owner);
    statusCalls.add((jobId: jobId, value: tailChars));
    return _ownerResult(owner, jobId, statusResult);
  }

  @override
  Future<FirstPartyToolExecutionResult> statusExecution({
    required ChatTurnOwner owner,
    required String jobId,
    int? tailChars,
  }) async => _execution(
    await status(owner: owner, jobId: jobId, tailChars: tailChars),
  );

  @override
  Future<String> tail({
    required ChatTurnOwner owner,
    required String jobId,
    int? maxChars,
  }) async {
    tailOwners.add(owner);
    tailCalls.add((jobId: jobId, value: maxChars));
    return _ownerResult(owner, jobId, tailResult);
  }

  @override
  Future<FirstPartyToolExecutionResult> tailExecution({
    required ChatTurnOwner owner,
    required String jobId,
    int? maxChars,
  }) async =>
      _execution(await tail(owner: owner, jobId: jobId, maxChars: maxChars));

  @override
  Future<String> wait({
    required ChatTurnOwner owner,
    required String jobId,
    int? waitMs,
  }) async {
    waitOwners.add(owner);
    waitCalls.add((jobId: jobId, value: waitMs));
    return _ownerResult(owner, jobId, waitResult);
  }

  @override
  Future<FirstPartyToolExecutionResult> waitExecution({
    required ChatTurnOwner owner,
    required String jobId,
    int? waitMs,
  }) async =>
      _execution(await wait(owner: owner, jobId: jobId, waitMs: waitMs));

  @override
  Future<String> cancel({
    required ChatTurnOwner owner,
    required String jobId,
  }) async {
    cancelOwners.add(owner);
    cancelCalls.add(jobId);
    return _ownerResult(owner, jobId, cancelResult);
  }

  @override
  Future<FirstPartyToolExecutionResult> cancelExecution({
    required ChatTurnOwner owner,
    required String jobId,
  }) async => _execution(await cancel(owner: owner, jobId: jobId));

  String _ownerResult(ChatTurnOwner owner, String jobId, String result) {
    if (visibleOwner == null || owner == visibleOwner) {
      return result;
    }
    return jsonEncode({
      'ok': false,
      'code': 'job_not_found',
      'job_id': jobId,
      'error': 'No background process job exists for job_id: $jobId',
    });
  }

  FirstPartyToolExecutionResult _execution(String result) {
    Object? payload;
    try {
      payload = jsonDecode(result);
    } on FormatException {
      return FirstPartyToolExecutionResult.payloadOnly(result);
    }
    if (payload is! Map<String, dynamic> || payload['ok'] != true) {
      return FirstPartyToolExecutionResult.payloadOnly(result);
    }
    final state = switch (payload['status']) {
      'running' => ToolProcessState.running,
      'exited' => ToolProcessState.exited,
      _ => null,
    };
    final exitCode = payload['exit_code'];
    return FirstPartyToolExecutionResult(
      result: result,
      outcome: state == null
          ? null
          : ToolOutcome(
              processState: state,
              exitCode: exitCode is num ? exitCode.toInt() : null,
            ),
    );
  }
}

class _FakeBackgroundProcessMonitorService
    extends BackgroundProcessMonitorService {
  _FakeBackgroundProcessMonitorService({
    List<BackgroundProcessMonitorSnapshot> snapshots = const [],
    List<BackgroundProcessMonitorSnapshot> active = const [],
    Map<ChatTurnOwner, List<BackgroundProcessMonitorSnapshot>>
        snapshotsByOwner =
        const {},
    Map<ChatTurnOwner, List<BackgroundProcessMonitorSnapshot>> activeByOwner =
        const {},
  }) : _snapshots = snapshots,
       _active = active,
       _snapshotsByOwner = snapshotsByOwner,
       _activeByOwner = activeByOwner,
       super(tools: BackgroundProcessTools());

  final List<BackgroundProcessMonitorSnapshot> _snapshots;
  final List<BackgroundProcessMonitorSnapshot> _active;
  final Map<ChatTurnOwner, List<BackgroundProcessMonitorSnapshot>>
  _snapshotsByOwner;
  final Map<ChatTurnOwner, List<BackgroundProcessMonitorSnapshot>>
  _activeByOwner;
  final List<_ProcessListCall> listCalls = <_ProcessListCall>[];
  final List<ChatTurnOwner> listOwners = <ChatTurnOwner>[];
  int refreshActiveCalls = 0;
  final List<ChatTurnOwner> refreshActiveOwners = <ChatTurnOwner>[];
  final List<List<String>> refreshJobCalls = <List<String>>[];
  final List<ChatTurnOwner> refreshJobOwners = <ChatTurnOwner>[];

  @override
  List<BackgroundProcessMonitorSnapshot> activeSnapshots(ChatTurnOwner owner) =>
      _activeByOwner[owner] ?? _active;

  @override
  List<BackgroundProcessMonitorSnapshot> listJobs(
    ChatTurnOwner owner, {
    Iterable<String>? jobIds,
    bool includeFinished = true,
    int? limit,
  }) {
    listOwners.add(owner);
    listCalls.add((
      jobIds: jobIds?.toList(growable: false),
      includeFinished: includeFinished,
      limit: limit,
    ));
    return _snapshotsByOwner[owner] ?? _snapshots;
  }

  @override
  Future<List<BackgroundProcessMonitorSnapshot>> refreshActiveJobs(
    ChatTurnOwner owner,
  ) async {
    refreshActiveCalls += 1;
    refreshActiveOwners.add(owner);
    return const <BackgroundProcessMonitorSnapshot>[];
  }

  @override
  Future<List<BackgroundProcessMonitorSnapshot>> refreshJobs(
    ChatTurnOwner owner,
    Iterable<String> jobIds,
  ) async {
    refreshJobOwners.add(owner);
    refreshJobCalls.add(jobIds.toList(growable: false));
    return const <BackgroundProcessMonitorSnapshot>[];
  }
}
